import SwiftUI
import AppKit
import Combine

var globalStatusItem: NSStatusItem?
var globalPopover: NSPopover?
var globalPopoverFrame: CGRect = .zero  // Store popover frame for soccer detail positioning

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
    var soccerViewModel = SoccerViewModel()  // 用于状态栏显示足球置顶比赛
    private var cancellables = Set<AnyCancellable>()

    // 静默模式：软件在后台时激活，只刷新置顶比赛
    static var isInBackgroundMode: Bool = false

    // 当前活跃页面：决定哪些数据需要轮询
    static var activeSport: String = "nba"  // "nba" 或 "soccer"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 1. 先加载本地 bundle 中的 players.json 作为默认词典
        // players.json is copied to Contents/Resources by Xcode build phase
        var localMapping: [String: String] = [:]
        var loadedCount = 0

        // Try direct resource path (players.json is in Resources folder)
        if let localUrl = Bundle.main.url(forResource: "players", withExtension: "json"),
           let localData = try? Data(contentsOf: localUrl),
           let localObj = try? JSONSerialization.jsonObject(with: localData) as? [String: Any],
           let localPlayers = localObj["players"] as? [[String: Any]] {
            for player in localPlayers {
                if let displayName = player["displayName"] as? String,
                   let lastName = player["lastName"] as? String,
                   let firstName = player["firstName"] as? String {
                    let zhName = firstName.isEmpty ? lastName : "\(firstName)·\(lastName)"
                    localMapping[displayName] = zhName.trimmingCharacters(in: .whitespaces)
                    loadedCount += 1
                }
            }
        }

        if loadedCount > 0 {
            PlayerTranslator.shared.updateCustomMapping(localMapping)
            print("📦 [AppDelegate] Loaded \(loadedCount) player translations from local bundle")
        } else {
            print("⚠️ [AppDelegate] Could not find players.json in bundle - loadedCount=\(loadedCount)")
        }

        // 加载足球球员翻译（本地 soccer_players.json）
        if let soccerUrl = Bundle.main.url(forResource: "soccer_players", withExtension: "json"),
           let soccerData = try? Data(contentsOf: soccerUrl),
           let soccerObj = try? JSONSerialization.jsonObject(with: soccerData) as? [String: [String: [String: String]]] {
            var soccerMapping: [String: String] = [:]
            for (_, teams) in soccerObj {
                for (_, players) in teams {
                    for (fullName, zhName) in players {
                        soccerMapping[fullName] = zhName
                    }
                }
            }
            if !soccerMapping.isEmpty {
                // 更新 SoccerPlayerTranslator 字典
                SoccerPlayerTranslator.shared.updateDictionary(soccerMapping)
                print("📦 [AppDelegate] Loaded \(soccerMapping.count) soccer player translations from bundle")
            }
        }

        // 拉取云端足球球员词典
        let savedSoccerDictUrl = UserDefaults.standard.string(forKey: "soccerPlayerDictUrl") ?? ""
        let soccerDictUrl = savedSoccerDictUrl.isEmpty ? "https://github.rzdpai.com/gh/flower-wzh/NBALiveScore/raw/refs/heads/main/NBALiveScore/data/soccer_players.json" : savedSoccerDictUrl

        if let url = URL(string: soccerDictUrl) {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            URLSession.shared.dataTask(with: request) { data, _, _ in
                if let data = data,
                   let soccerObj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: [String: String]]] {
                    var newMapping: [String: String] = [:]
                    for (_, teams) in soccerObj {
                        for (_, players) in teams {
                            for (fullName, zhName) in players {
                                newMapping[fullName] = zhName
                            }
                        }
                    }
                    if !newMapping.isEmpty {
                        SoccerPlayerTranslator.shared.updateDictionary(newMapping)
                        print("📦 [AppDelegate] Loaded \(newMapping.count) soccer player translations from cloud")
                    }
                }
            }.resume()
        }

        // 2. App冷启动：自动拉取一次云端词典 (如果配置了 URL)
        let savedUrl = UserDefaults.standard.string(forKey: "playerDictUrl") ?? ""
        let dictUrl = savedUrl.isEmpty ? "https://github.rzdpai.com/gh/flower-wzh/NBALiveScore/raw/refs/heads/main/NBALiveScore/data/players.json" : savedUrl
        
        if let url = URL(string: dictUrl) {
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
                            let zhName = firstName.isEmpty ? lastName : "\(firstName)·\(lastName)"
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
            self.setupBackgroundObservers()
        }
    }

    func setupBackgroundObservers() {
        // 监听应用进入后台/前台
        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppDelegate.isInBackgroundMode = true
            print("🔵 [AppDelegate] 进入后台静默模式，停止轮询")
            // 停止主轮询
            self?.viewModel.stopPolling()
            self?.soccerViewModel.stopPolling()
            // 开始后台置顶刷新
            self?.startBackgroundPinnedRefresh()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppDelegate.isInBackgroundMode = false
            print("🟢 [AppDelegate] 返回前台正常模式")
            // 停止后台刷新
            self?.backgroundTimer?.cancel()
            // 恢复主轮询
            self?.viewModel.startPolling()
            self?.soccerViewModel.startPolling()
            // 立即刷新一次
            self?.viewModel.fetchGames()
            self?.soccerViewModel.fetchGames()
        }
    }

    // 后台静默模式：定时刷新置顶比赛的简要信息（轻量）
    private var backgroundTimer: AnyCancellable?
    func startBackgroundPinnedRefresh() {
        print("🔵 [后台刷新] 启动后台置顶刷新定时器（每10秒）")
        backgroundTimer?.cancel()
        // 后台时每60秒更新一次置顶比赛状态（状态栏使用）
        backgroundTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard AppDelegate.isInBackgroundMode else { return }
            self?.refreshPinnedGameInBackground()
        }
    }

    func refreshPinnedGameInBackground() {
        // 只刷新置顶比赛，用于状态栏
        let pinnedSport = GlobalPinnedGameManager.shared.pinnedSport
        let pinnedIdOnly = GlobalPinnedGameManager.shared.pinnedIdOnly

        if pinnedSport == "nba", let gameId = pinnedIdOnly {
            print("🔵 [后台刷新] NBA置顶比赛: \(gameId)")
            // NBA置顶比赛：调用完整的 fetchGames（和激活时一样的数据源，复用相同的解析逻辑）
            viewModel.fetchGames()
        } else if pinnedSport == "soccer", let gameId = pinnedIdOnly {
            print("⚽ [后台刷新] 足球置顶比赛: \(gameId)")
            // 足球置顶比赛
            let league = soccerViewModel.currentLeague
            soccerViewModel.fetchSoccerGameDetail(eventId: gameId, league: league) { [weak self] detail in
                if let detail = detail {
                    print("⚽ [后台刷新] 足球详情获取成功: \(detail.homeScore) - \(detail.awayScore)")
                    // 更新缓存（在主线程）
                    let updatedGame = SoccerGame(
                        id: detail.id,
                        status: detail.status,
                        time: detail.statusDetail,
                        period: detail.statusDetail,
                        homeTeam: SoccerTeam(
                            id: detail.homeTeam.id,
                            name: detail.homeTeam.name,
                            shortName: detail.homeTeam.shortName,
                            logo: detail.homeTeam.logo,
                            countryCode: detail.homeTeam.shortName,
                            score: "\(detail.homeScore)"
                        ),
                        awayTeam: SoccerTeam(
                            id: detail.awayTeam.id,
                            name: detail.awayTeam.name,
                            shortName: detail.awayTeam.shortName,
                            logo: detail.awayTeam.logo,
                            countryCode: detail.awayTeam.shortName,
                            score: "\(detail.awayScore)"
                        ),
                        competition: detail.league,
                        leagueId: league.rawValue
                    )
                    DispatchQueue.main.async {
                        GlobalPinnedGameManager.shared.cachedSoccerGame = updatedGame
                        self?.updateStatusBarForPinnedGame()
                    }
                } else {
                    print("⚽ [后台刷新] 足球详情获取失败")
                }
            }
        } else {
            print("🔵 [后台刷新] 无置顶比赛，跳过刷新")
        }
    }

    private func fetchMinimalGame(urlString: String, sport: String, gameId: String) {
        print("🔵 [后台刷新] 请求NBA详情: \(urlString)")
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("🔵 [后台刷新] NBA详情解析失败")
                return
            }

            // 解析简要分数更新
            let header = json["header"] as? [String: Any]
            let competitions = header?["competitions"] as? [[String: Any]]
            let competition = competitions?.first
            let competitors = competition?["competitors"] as? [[String: Any]]

            var homeScore = "0", awayScore = "0"
            for comp in competitors ?? [] {
                let homeAway = comp["homeAway"] as? String
                let score = comp["score"] as? String ?? "0"
                if homeAway == "home" { homeScore = score }
                else if homeAway == "away" { awayScore = score }
            }

            print("🔵 [后台刷新] NBA详情获取成功，分数: \(homeScore) - \(awayScore)")

            // 更新缓存（在主线程）
            if sport == "nba" {
                print("🔵 [后台刷新] 开始更新缓存 NBA gameId=\(gameId)")
                // 直接使用fetch到的数据创建新的Game对象
                let header = json["header"] as? [String: Any]
                let competitions = header?["competitions"] as? [[String: Any]]
                let competition = competitions?.first
                let gameStatus = competition?["status"] as? [String: Any]
                let statusType = gameStatus?["type"] as? [String: Any]
                let state = statusType?["state"] as? String ?? "live"
                // 与SportsViewModel保持一致的状态映射：post->final, pre->scheduled, in->live
                let statusStr: String
                switch state {
                case "post": statusStr = "final"
                case "pre": statusStr = "scheduled"
                case "in": statusStr = "live"
                default: statusStr = state
                }
                let detail = statusType?["detail"] as? String ?? ""
                let periodRaw = statusType?["period"] as? String ?? "Q1"
                // 标准化 period 格式：将 "2nd Quarter" -> "Q2", "3rd Quarter" -> "Q3" 等
                let period: String
                if periodRaw.contains("Quarter") {
                    let numStr = periodRaw.replacingOccurrences(of: "Quarter", with: "").trimmingCharacters(in: .whitespaces)
                    let num: Int
                    if let n = Int(numStr) {
                        num = n
                    } else if numStr == "2nd" || numStr == "3rd" || numStr == "4th" {
                        num = Int(numStr.dropLast(2)) ?? 1
                    } else {
                        num = 1
                    }
                    period = "Q\(num)"
                } else if periodRaw.hasPrefix("OT") {
                    period = periodRaw
                } else {
                    period = periodRaw
                }
                let displayClock = gameStatus?["displayClock"] as? String ?? ""
                // 对于未开始的比赛，使用date字段获取实际时间
                // 对于live比赛，使用displayClock（比赛时钟）
                var gameTime: String
                if state == "pre" || state == "scheduled" {
                    if let dateStr = competition?["date"] as? String {
                        print("🔵 [后台刷新] 获取到开赛时间: \(dateStr)")
                        gameTime = dateStr
                    } else {
                        gameTime = detail
                    }
                } else if state == "live" {
                    // live比赛使用displayClock作为比赛时钟
                    gameTime = displayClock.isEmpty ? (GlobalPinnedGameManager.shared.cachedNBAGame?.time ?? detail) : displayClock
                } else {
                    gameTime = detail
                }

                let updatedGame = Game(
                    id: gameId,
                    status: statusStr,
                    time: gameTime,
                    period: period,
                    homeTeam: Team(id: "", name: "", score: homeScore, logo: "", tricode: "", seriesWins: nil, seriesLosses: nil),
                    awayTeam: Team(id: "", name: "", score: awayScore, logo: "", tricode: "", seriesWins: nil, seriesLosses: nil),
                    homeTeamSeriesWins: nil,
                    homeTeamSeriesLosses: nil,
                    awayTeamSeriesWins: nil,
                    awayTeamSeriesLosses: nil,
                    isPlayoff: false,
                    seriesTotalGames: nil
                )
                DispatchQueue.main.async {
                    print("🔵 [后台刷新] 主线程中更新状态栏")
                    GlobalPinnedGameManager.shared.cachedNBAGame = updatedGame
                    self?.updateStatusBarForPinnedGame()
                }
            } else {
                print("🔵 [后台刷新] 跳过更新：sport=\(sport)")
            }
        }.resume()
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
        // Observe NBA games
        viewModel.$games
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBarForPinnedGame()
            }
            .store(in: &cancellables)

        // Observe soccer games
        soccerViewModel.$games
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBarForPinnedGame()
            }
            .store(in: &cancellables)

        // Observe global pinned manager changes
        GlobalPinnedGameManager.shared.$pinnedGameId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBarForPinnedGame()
            }
            .store(in: &cancellables)
    }

    // 根据全局置顶状态更新状态栏
    func updateStatusBarForPinnedGame() {
        guard let button = globalStatusItem?.button else { return }

        let pinnedSport = GlobalPinnedGameManager.shared.pinnedSport
        let pinnedIdOnly = GlobalPinnedGameManager.shared.pinnedIdOnly

        if pinnedSport == "nba" {
            // NBA置顶：优先使用后台刷新的最新缓存数据
            if let cachedGame = GlobalPinnedGameManager.shared.cachedNBAGame, cachedGame.id == pinnedIdOnly {
                updateStatusBarWithNBAGame(cachedGame)
            } else if let game = viewModel.games.first(where: { $0.id == pinnedIdOnly }) {
                // 同时缓存到 GlobalPinnedGameManager
                GlobalPinnedGameManager.shared.cachedNBAGame = game
                updateStatusBarWithNBAGame(game)
            } else {
                // NBA但没找到比赛，尝试重新获取
                if let pinnedId = pinnedIdOnly {
                    viewModel.fetchGames()
                    if let game = viewModel.games.first(where: { $0.id == pinnedId }) {
                        GlobalPinnedGameManager.shared.cachedNBAGame = game
                        updateStatusBarWithNBAGame(game)
                    } else {
                        showDefaultStatusBar()
                    }
                } else {
                    showDefaultStatusBar()
                }
            }
        } else if pinnedSport == "soccer" {
            // 足球置顶
            if let game = soccerViewModel.games.first(where: { $0.id == pinnedIdOnly }) {
                updateStatusBarWithSoccerGame(game)
            } else if let cachedGame = GlobalPinnedGameManager.shared.cachedSoccerGame, cachedGame.id == pinnedIdOnly {
                // 使用缓存的比赛
                updateStatusBarWithSoccerGame(cachedGame)
            } else {
                // 足球但没找到比赛
                showDefaultStatusBar()
            }
        } else {
            showDefaultStatusBar()
        }
    }

    func updateStatusBarLabelNBA(games: [Game], pinnedId: String?) {
        if let game = games.first(where: { $0.id == pinnedId }) {
            updateStatusBarWithNBAGame(game)
        } else {
            showDefaultStatusBar()
        }
    }

    func updateStatusBarLabelSoccer(games: [SoccerGame]) {
        // 检查是否是足球置顶
        if GlobalPinnedGameManager.shared.pinnedSport == "soccer",
           let pinnedId = GlobalPinnedGameManager.shared.pinnedIdOnly,
           let game = games.first(where: { $0.id == pinnedId }) {
            updateStatusBarWithSoccerGame(game)
        }
    }

    func updateStatusBarWithNBAGame(_ game: Game) {
        guard let button = globalStatusItem?.button else {
            print("🔵 [状态栏] button 为 nil，无法更新")
            return
        }

        let awayName = game.awayTeam.name
        let homeName = game.homeTeam.name

        // 如果球队名为空（后台刷新的 summary API 缺少球队名称），从 viewModel.games 补充
        // 但要保留后台刷新的新比分和时间，不被旧数据覆盖
        var displayGame = game
        if awayName.isEmpty || homeName.isEmpty {
            if let fullGame = viewModel.games.first(where: { $0.id == game.id }) {
                // 只补充球队名称和标识，保留传入 game 的比分和时间
                displayGame = Game(
                    id: game.id,
                    status: game.status,
                    time: game.time,
                    period: game.period,
                    homeTeam: Team(
                        id: fullGame.homeTeam.id,
                        name: fullGame.homeTeam.name,
                        score: game.homeTeam.score,
                        logo: fullGame.homeTeam.logo,
                        tricode: fullGame.homeTeam.tricode,
                        seriesWins: game.homeTeamSeriesWins,
                        seriesLosses: game.homeTeamSeriesLosses
                    ),
                    awayTeam: Team(
                        id: fullGame.awayTeam.id,
                        name: fullGame.awayTeam.name,
                        score: game.awayTeam.score,
                        logo: fullGame.awayTeam.logo,
                        tricode: fullGame.awayTeam.tricode,
                        seriesWins: game.awayTeamSeriesWins,
                        seriesLosses: game.awayTeamSeriesLosses
                    ),
                    homeTeamSeriesWins: game.homeTeamSeriesWins,
                    homeTeamSeriesLosses: game.homeTeamSeriesLosses,
                    awayTeamSeriesWins: game.awayTeamSeriesWins,
                    awayTeamSeriesLosses: game.awayTeamSeriesLosses,
                    isPlayoff: game.isPlayoff,
                    seriesTotalGames: game.seriesTotalGames
                )
                print("🔵 [状态栏] 补充了完整球队名称: \(fullGame.awayTeam.name) vs \(fullGame.homeTeam.name)，但保留新比分 \(game.awayTeam.score)-\(game.homeTeam.score)")
            }
        }

        let awayScore = displayGame.status == "scheduled" ? "-" : "\(displayGame.awayTeam.score)"
        let homeScore = displayGame.status == "scheduled" ? "-" : "\(displayGame.homeTeam.score)"

        print("🔵 [状态栏] 更新显示: \(displayGame.awayTeam.name) \(awayScore) - \(homeScore) \(displayGame.homeTeam.name), 状态=\(displayGame.status), 时间=\(displayGame.time)")

        var periodStr = ""
        var clockStr = ""

        if displayGame.status == "live" {
            let periodMap = ["Q1":"第一节", "Q2":"第二节", "Q3":"第三节", "Q4":"第四节", "OT1":"加时1", "OT2":"加时2", "OT3":"加时3", "OT4":"加时4", "OT5":"加时5", "OT6":"加时6", "OT7":"加时7"]
            periodStr = periodMap[displayGame.period] ?? displayGame.period
            var clock = displayGame.time
            if let pt = clock.split(separator: " ").last, pt.contains(":") {
                clock = String(pt)
            }
            // 过滤无效时钟值：0.0 表示该节刚结束，显示"已结束"
            if clock == "0.0" || clock.isEmpty || clock == "0" {
                clockStr = "已结束"
            } else {
                clockStr = clock
            }
        } else if displayGame.status == "final" {
            periodStr = "全场战罢"
            clockStr = "已结束"
        } else {
            periodStr = "未开始"
            // 显示实际开赛时间
            let timeStr = displayGame.time
            if !timeStr.isEmpty && timeStr != "0.0" && timeStr != "0" {
                // 尝试格式化ISO时间字符串
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: timeStr) {
                    let displayFormatter = DateFormatter()
                    displayFormatter.dateFormat = "h:mm a"
                    displayFormatter.timeZone = TimeZone(identifier: "US/Eastern")
                    clockStr = displayFormatter.string(from: date) + " ET"
                } else {
                    // 尝试不带毫秒的格式
                    formatter.formatOptions = [.withInternetDateTime]
                    if let date = formatter.date(from: timeStr) {
                        let displayFormatter = DateFormatter()
                        displayFormatter.dateFormat = "h:mm a"
                        displayFormatter.timeZone = TimeZone(identifier: "US/Eastern")
                        clockStr = displayFormatter.string(from: date) + " ET"
                    } else {
                        // 如果解析失败，直接显示原字符串
                        clockStr = timeStr
                    }
                }
            } else {
                clockStr = "--:--"
            }
        }

        let image = generateStatusBarImage(leftName: displayGame.homeTeam.name, rightName: displayGame.awayTeam.name, periodStr: periodStr, clockStr: clockStr, leftScore: homeScore, rightScore: awayScore)

        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
        button.attributedTitle = NSAttributedString()
    }

    func updateStatusBarWithSoccerGame(_ game: SoccerGame) {
        guard let button = globalStatusItem?.button else { return }

        let awayName = game.awayTeam.name
        let homeName = game.homeTeam.name

        var periodStr = ""
        var clockStr = ""

        if game.status == "live" {
            periodStr = game.period
            clockStr = game.time
        } else if game.status == "final" {
            periodStr = "全场战罢"
            clockStr = "已结束"
        } else {
            periodStr = "未开始"
            clockStr = "--:--"
        }

        let awayScore = game.status == "scheduled" ? "-" : "\(game.awayTeam.score)"
        let homeScore = game.status == "scheduled" ? "-" : "\(game.homeTeam.score)"

        let image = generateStatusBarImage(leftName: homeName, rightName: awayName, periodStr: periodStr, clockStr: clockStr, leftScore: homeScore, rightScore: awayScore)

        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
        button.attributedTitle = NSAttributedString()
    }

    func showDefaultStatusBar() {
        guard let button = globalStatusItem?.button else { return }
        button.image = nil
        button.imagePosition = .imageLeft
        button.attributedTitle = NSAttributedString()
        button.title = "🏀 NBA"
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
    }

    // 自定义画布专门为 macOS 22pt 的状态栏生成无缝无阻挡的上下两行排版
    // leftName/leftScore: 主队(左) or 客队(左), rightName/rightScore: 客队(右) or 主队(右)
    func generateStatusBarImage(leftName: String, rightName: String, periodStr: String, clockStr: String, leftScore: String, rightScore: String) -> NSImage {
        let topFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let scoreFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

        let topStr = "\(leftName)  \(periodStr)  \(rightName)"
        let topSize = topStr.size(withAttributes: [.font: topFont])
        
        let leftScoreSize = leftScore.size(withAttributes: [.font: scoreFont])
        let rightScoreSize = rightScore.size(withAttributes: [.font: scoreFont])
        let clockSize = clockStr.size(withAttributes: [.font: timeFont])

        let spacing: CGFloat = 8
        let bottomWidth = leftScoreSize.width + spacing + clockSize.width + spacing + rightScoreSize.width
        let totalWidth = max(topSize.width, bottomWidth) + 12
        let totalHeight: CGFloat = 22 // 状态栏标准可用高度最大极限
        
        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
        image.lockFocus()
        
        let attrsTop: [NSAttributedString.Key: Any] = [.font: topFont, .foregroundColor: NSColor.black]
        let attrsScore: [NSAttributedString.Key: Any] = [.font: scoreFont, .foregroundColor: NSColor.black]
        let attrsTime: [NSAttributedString.Key: Any] = [.font: timeFont, .foregroundColor: NSColor.black]
        
        let topX = (totalWidth - topSize.width) / 2.0
        topStr.draw(at: NSPoint(x: topX, y: 11.5), withAttributes: attrsTop)
        
        let leftX = (totalWidth - bottomWidth) / 2.0
        leftScore.draw(at: NSPoint(x: leftX, y: -0.5), withAttributes: attrsScore)

        let clockX = leftX + leftScoreSize.width + spacing
        clockStr.draw(at: NSPoint(x: clockX, y: 0.5), withAttributes: attrsTime)

        let rightX = clockX + clockSize.width + spacing
        rightScore.draw(at: NSPoint(x: rightX, y: -0.5), withAttributes: attrsScore)
        
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

            // Store popover frame when shown
            if let window = popover.contentViewController?.view.window {
                globalPopoverFrame = window.frame
            }

            // 打开时刷新数据
            print("🟢 [Popover] 打开时刷新数据")
            self.viewModel.fetchGames()
            self.soccerViewModel.fetchGames()
        }
    }
}
