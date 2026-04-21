import SwiftUI
import AppKit
import Combine

var globalStatusItem: NSStatusItem?
var globalPopover: NSPopover?

@main
struct LiveBarNBAApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel = SportsViewModel()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        // App冷启动：自动拉取一次云端词典 (如果配置了 URL)
        let dictUrl = UserDefaults.standard.string(forKey: "playerDictUrl") ?? ""
        if !dictUrl.isEmpty, let url = URL(string: dictUrl) {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            URLSession.shared.dataTask(with: request) { data, _, _ in
                if let data = data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let players = obj["players"] as? [[String: Any]] {
                    
                    var newMapping: [String: String] = [:]
                    for player in players {
                        if let displayName = player["displayName"] as? String,
                           let lastName = player["lastName"] as? String,
                           let firstName = player["firstName"] as? String {
                            let zhName = firstName.isEmpty ? lastName : "\(firstName) \(lastName)"
                            newMapping[displayName] = zhName.trimmingCharacters(in: .whitespaces)
                        }
                    }
                    if !newMapping.isEmpty {
                        PlayerTranslator.shared.updateCustomMapping(newMapping)
                    }
                } else if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                    PlayerTranslator.shared.updateCustomMapping(json)
                }
            }.resume()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.setupStatusBar()
            self.setupObservers()
        }
    }
    
    func setupStatusBar() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.behavior = .transient
        // Use an external coordinator to safely host the swiftui popover
        popover.contentViewController = NSHostingController(
            rootView: ContentView().environmentObject(viewModel)
        )
        globalPopover = popover
        
        globalStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = globalStatusItem?.button {
            button.title = "🏀 NBA"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
    }

    func setupObservers() {
        // Observe changes to games and pinnedGameId simultaneously
        Publishers.CombineLatest(viewModel.$games, viewModel.$pinnedGameId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] games, pinnedId in
                self?.updateStatusBarLabel(games: games, pinnedId: pinnedId)
            }
            .store(in: &cancellables)
    }
    
    func updateStatusBarLabel(games: [Game], pinnedId: String?) {
        guard let button = globalStatusItem?.button else { return }
        
        if let pinnedId = pinnedId, let pinnedGame = games.first(where: { $0.id == pinnedId }) {
            let awayName = pinnedGame.awayTeam.name
            let homeName = pinnedGame.homeTeam.name
            
            var periodStr = ""
            var clockStr = ""
            
            if pinnedGame.status == "live" {
                let periodMap = ["Q1":"第一节", "Q2":"第二节", "Q3":"第三节", "Q4":"第四节", "OT1":"加时1", "OT2":"加时2", "OT3":"加时3", "OT4":"加时4", "OT5":"加时5", "OT6":"加时6", "OT7":"加时7"]
                periodStr = periodMap[pinnedGame.period] ?? pinnedGame.period
                var clock = pinnedGame.time
                if let pt = clock.split(separator: " ").last, pt.contains(":") {
                    clock = String(pt)
                }
                clockStr = clock
            } else if pinnedGame.status == "final" {
                periodStr = "全场战罢"
                clockStr = "已结束"
            } else {
                periodStr = "未开始"
                clockStr = "--:--"
            }
            
            let awayScore = pinnedGame.status == "scheduled" ? "-" : "\(pinnedGame.awayTeam.score)"
            let homeScore = pinnedGame.status == "scheduled" ? "-" : "\(pinnedGame.homeTeam.score)"
            
            // 弃用富文本，直接使用 CoreGraphics / AppKit 画图，来绕过苹果状态栏高度固定只有单行的历史包袱
            let image = generateStatusBarImage(awayName: awayName, homeName: homeName, periodStr: periodStr, clockStr: clockStr, awayScore: awayScore, homeScore: homeScore)
            
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
            button.attributedTitle = NSAttributedString() // 清空防止干扰
        } else {
            button.image = nil
            button.imagePosition = .imageLeft
            button.attributedTitle = NSAttributedString()
            button.title = "🏀 NBA"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        }
    }
    
    // 自定义画布专门为 macOS 22pt 的状态栏生成无缝无阻挡的上下两行排版
    func generateStatusBarImage(awayName: String, homeName: String, periodStr: String, clockStr: String, awayScore: String, homeScore: String) -> NSImage {
        let topFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let scoreFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

        let topStr = "\(awayName)  \(periodStr)  \(homeName)"
        let topSize = topStr.size(withAttributes: [.font: topFont])
        
        let awayScoreSize = awayScore.size(withAttributes: [.font: scoreFont])
        let homeScoreSize = homeScore.size(withAttributes: [.font: scoreFont])
        let clockSize = clockStr.size(withAttributes: [.font: timeFont])
        
        let spacing: CGFloat = 8
        let bottomWidth = awayScoreSize.width + spacing + clockSize.width + spacing + homeScoreSize.width
        let totalWidth = max(topSize.width, bottomWidth) + 12
        let totalHeight: CGFloat = 22 // 状态栏标准可用高度最大极限
        
        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        image.lockFocus()
        
        let attrsTop: [NSAttributedString.Key: Any] = [.font: topFont, .foregroundColor: NSColor.black]
        let attrsScore: [NSAttributedString.Key: Any] = [.font: scoreFont, .foregroundColor: NSColor.black]
        let attrsTime: [NSAttributedString.Key: Any] = [.font: timeFont, .foregroundColor: NSColor.black]
        
        let topX = (totalWidth - topSize.width) / 2.0
        topStr.draw(at: NSPoint(x: topX, y: 11.5), withAttributes: attrsTop)
        
        let awayX = (totalWidth - bottomWidth) / 2.0
        awayScore.draw(at: NSPoint(x: awayX, y: -0.5), withAttributes: attrsScore)
        
        let clockX = awayX + awayScoreSize.width + spacing
        clockStr.draw(at: NSPoint(x: clockX, y: 0.5), withAttributes: attrsTime)
        
        let homeX = clockX + clockSize.width + spacing
        homeScore.draw(at: NSPoint(x: homeX, y: -0.5), withAttributes: attrsScore)
        
        image.unlockFocus()
        // 【关键】启用 Template 模版图！这样不管用户是暗色模式还是亮色主题，macOS 都会主动将这部分染白/染黑，无缝融入系统UI
        image.isTemplate = true
        return image
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let popover = globalPopover, let button = globalStatusItem?.button else { return }
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
