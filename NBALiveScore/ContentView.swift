import SwiftUI

// MARK: - 悬停状态管理器 (全局唯一绑定)
class PopoverManager: ObservableObject {
    @Published var activeGameId: String? = nil
    @Published var isPopoverHovered: Bool = false
}

// MARK: - 主列表界面
struct ContentView: View {
    @EnvironmentObject var viewModel: SportsViewModel
    @StateObject private var popoverManager = PopoverManager()
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color(red: 26/255, green: 28/255, blue: 44/255),
                                            Color(red: 74/255, green: 25/255, blue: 44/255),
                                            Color(red: 18/255, green: 20/255, blue: 32/255)]),
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                HStack {
                    Text("每日赛程 • NBA").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.4)).tracking(2)
                    Spacer()
                    if #available(macOS 14.0, *) {
                        SettingsLink {
                            Image(systemName: "gearshape.fill").foregroundColor(.white.opacity(0.3)).font(.system(size: 14))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.trailing, 8)
                    } else {
                        Button(action: {
                            NSApp.sendAction(Selector("showSettingsWindow:"), to: nil, from: nil)
                        }) {
                            Image(systemName: "gearshape.fill").foregroundColor(.white.opacity(0.3)).font(.system(size: 14))
                        }.buttonStyle(PlainButtonStyle())
                            .padding(.trailing, 8)
                    }
                    
                    Button(action: { NSApplication.shared.terminate(nil) }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.3)).font(.system(size: 14))
                    }.buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 16).padding(.vertical, 12).background(Color.white.opacity(0.05))
                
                ScrollView {
                    VStack(spacing: 12) {
                        // 插入大图横幅
                        if let pinnedId = viewModel.pinnedGameId, let pinnedGame = viewModel.games.first(where: { $0.id == pinnedId }) {
                            PinnedGameBannerView(game: pinnedGame)
                                .padding(.bottom, 4)
                        }

                        if viewModel.isLoading && viewModel.games.isEmpty {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .orange)).padding(.top, 40)
                        } else {
                            ForEach(viewModel.games) { game in
                                GameRowView(game: game)
                            }
                        }
                    }.padding(14)
                }
                
                HStack {
                    Image(systemName: "network").font(.system(size: 10))
                    Text(viewModel.isLoading ? "数据刷新中..." : "数据已同步")
                    Spacer()
                    Circle().fill(Color.green).frame(width: 6, height: 6).shadow(color: .green.opacity(0.4), radius: 4, x: 0, y: 0)
                    Text("LIVEBAR PRO")
                }
                .font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.3)).padding(12).background(Color.black.opacity(0.3))
            }
        }
        .frame(minWidth: 320, idealWidth: 380, maxWidth: 500, minHeight: 400, idealHeight: 550, maxHeight: 850)
        .preferredColorScheme(.dark)
        .environmentObject(popoverManager)
    }
}

// MARK: - 大图置顶行
struct PinnedGameBannerView: View {
    let game: Game
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "pin.fill").foregroundColor(.orange).font(.system(size: 10))
                Text("已置顶 • 对阵详情").font(.system(size: 11, weight: .bold)).foregroundColor(.orange)
                Spacer()
                Text("今日焦点战").font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
            }
            
            HStack(alignment: .center) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.1)).frame(width: 36, height: 36)
                        AsyncImage(url: URL(string: game.awayTeam.logo)) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            ProgressView()
                        }.frame(width: 24, height: 24)
                    }
                    Text(game.awayTeam.name).font(.system(size: 11, weight: .bold)).foregroundColor(.white).lineLimit(1)
                }
                .frame(width: 70)
                
                Spacer()
                
                VStack(spacing: 4) {
                    if game.status == "scheduled" {
                        Text("VS").font(.system(size: 24, weight: .black, design: .rounded)).foregroundColor(.white)
                    } else {
                        Text("\(game.awayTeam.score) - \(game.homeTeam.score)")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .monospacedDigit()
                    }
                    
                    if game.status == "live" {
                        Text("\(translatePeriod(game.period)) \(formatGameTime(game.time))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2).cornerRadius(4))
                    } else if game.status == "final" {
                        Text("已结束").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.5))
                    } else {
                        Text(game.time).font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.5))
                    }
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.1)).frame(width: 36, height: 36)
                        AsyncImage(url: URL(string: game.homeTeam.logo)) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            ProgressView()
                        }.frame(width: 24, height: 24)
                    }
                    Text(game.homeTeam.name).font(.system(size: 11, weight: .bold)).foregroundColor(.white).lineLimit(1)
                }
                .frame(width: 70)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            LinearGradient(gradient: Gradient(colors: [Color(red: 45/255, green: 25/255, blue: 35/255), Color(red: 25/255, green: 20/255, blue: 30/255)]), startPoint: .top, endPoint: .bottom)
        )
        .cornerRadius(12)
    }
    
    func translatePeriod(_ p: String) -> String {
        switch p {
        case "Q1": return "第一节"
        case "Q2": return "第二节"
        case "Q3": return "第三节"
        case "Q4": return "第四节"
        case "OT1": return "加时1"
        case "OT2": return "加时2"
        case "OT3": return "加时3"
        case "OT4": return "加时4"
        case "OT5": return "加时5"
        case "OT6": return "加时6"
        case "OT7": return "加时7"
        default: return p
        }
    }
    
    func formatGameTime(_ t: String) -> String {
        if let last = t.split(separator: " ").last, String(last).contains(":") {
            return String(last)
        }
        if t.contains(":") {
            return t.replacingOccurrences(of: "Q1 ", with: "").replacingOccurrences(of: "Q2 ", with: "").replacingOccurrences(of: "Q3 ", with: "").replacingOccurrences(of: "Q4 ", with: "")
        }
        return t
    }
}

// MARK: - 比赛行
struct GameRowView: View {
    let game: Game
    @EnvironmentObject var viewModel: SportsViewModel
    @EnvironmentObject var popoverManager: PopoverManager
    @State private var isHovered = false
    @State private var hoverTask: DispatchWorkItem?
    
    var body: some View {
        HStack(alignment: .center) {
            teamInfoView
            Spacer()
            scoreAndPinView
        }
        .padding(14)
        .background(backgroundView)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.snappy(duration: 0.2), value: isHovered)
        .onHover(perform: handleHover)
        .onTapGesture(perform: handleTap)
        .popover(isPresented: popoverBinding, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            GameDetailView(gameId: game.id)
        }
    }
    
    // 【修改点】：追加了球队 Logo 显示
    private var teamInfoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                AsyncImage(url: URL(string: game.awayTeam.logo)) { image in
                    image.resizable().scaledToFit()
                } placeholder: { Circle().fill(Color.white.opacity(0.1)) }
                .frame(width: 16, height: 16)
                
                Text(game.awayTeam.name).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                Text("@").font(.system(size: 10, weight: .black)).foregroundColor(Color.white.opacity(0.2))
                
                AsyncImage(url: URL(string: game.homeTeam.logo)) { image in
                    image.resizable().scaledToFit()
                } placeholder: { Circle().fill(Color.white.opacity(0.1)) }
                .frame(width: 16, height: 16)
                
                Text(game.homeTeam.name).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
            }
            HStack(spacing: 6) {
                if game.status == "live" { Circle().fill(Color.orange).frame(width: 6, height: 6) }
                Text(statusText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(game.status == "live" ? .orange : Color.white.opacity(0.4))
            }
        }
    }
    
    private var statusText: String {
        if game.status == "live" { return "直播中 • \(game.time)" }
        if game.status == "final" { return "已结束" }
        return game.time
    }
    
    private var scoreAndPinView: some View {
        HStack {
            if game.status == "scheduled" {
                Text("-- : --").font(.system(size: 20, weight: .black)).foregroundColor(.white.opacity(0.1)).monospacedDigit()
            } else {
                Text("\(game.awayTeam.score) - \(game.homeTeam.score)").font(.system(size: 20, weight: .black)).foregroundColor(.white).monospacedDigit()
            }
            
            Button(action: togglePin) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundColor(isPinned ? .orange : .white.opacity(0.2))
                    .font(.system(size: 14))
                    .padding(.leading, 8)
            }
            .buttonStyle(PlainButtonStyle())
            .help(isPinned ? "取消置顶" : "置顶比分")
        }
    }
    
    private var isPinned: Bool {
        viewModel.pinnedGameId == game.id
    }
    
    private func togglePin() {
        viewModel.pinnedGameId = isPinned ? nil : game.id
    }
    
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(isHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isHovered ? Color.white.opacity(0.15) : Color.white.opacity(0.05), lineWidth: 1))
    }
    
    private func handleHover(_ hovering: Bool) {
        isHovered = hovering
        hoverTask?.cancel()
        if hovering {
            let task = DispatchWorkItem {
                if isHovered && popoverManager.activeGameId != game.id {
                    popoverManager.activeGameId = game.id
                }
            }
            hoverTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
        } else {
            let task = DispatchWorkItem {
                if popoverManager.activeGameId == game.id && !popoverManager.isPopoverHovered {
                    popoverManager.activeGameId = nil
                }
            }
            hoverTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: task)
        }
    }
    
    private func handleTap() {
        if popoverManager.activeGameId == game.id {
            popoverManager.activeGameId = nil
        } else {
            popoverManager.activeGameId = game.id
        }
    }
    
    private var popoverBinding: Binding<Bool> {
        Binding(
            get: { popoverManager.activeGameId == game.id },
            set: { isOpen in
                if !isOpen && popoverManager.activeGameId == game.id {
                    popoverManager.activeGameId = nil
                }
            }
        )
    }
}

// MARK: - 侧边悬浮窗口：技术统计详情页
// 新增全局翻译字典
let popoverTeamTranslation: [String: String] = [
    "ATL": "老鹰", "BOS": "凯尔特人", "BKN": "篮网", "CHA": "黄蜂", "CHI": "公牛",
    "CLE": "骑士", "DAL": "独行侠", "DEN": "掘金", "DET": "活塞", "GSW": "勇士",
    "HOU": "火箭", "IND": "步行者", "LAC": "快船", "LAL": "湖人", "MEM": "灰熊",
    "MIA": "热火", "MIL": "雄鹿", "MIN": "森林狼", "NOP": "鹈鹕", "NYK": "尼克斯",
    "OKC": "雷霆", "ORL": "魔术", "PHI": "76人", "PHX": "太阳", "POR": "开拓者",
    "SAC": "国王", "SAS": "马刺", "TOR": "猛龙", "UTA": "爵士", "WAS": "奇才"
]

struct BoxscoreModel {
    let awayName: String; let homeName: String
    let awayScore: Int; let homeScore: Int
    let awayPeriods: [Int]; let homePeriods: [Int]
    let awayPlayers: [PlayerStat]; let homePlayers: [PlayerStat]
}

struct PlayerStat: Identifiable {
    let id = UUID()
    let name: String; let time: String
    let pts: Int; let reb: Int; let ast: Int
    let fg: String; let threePt: String; let ft: String
    let plusMinus: Int; let onCourt: Bool; let isStarter: Bool
}

struct GameDetailView: View {
    let gameId: String
    @EnvironmentObject var popoverManager: PopoverManager
    @State private var data: BoxscoreModel? = nil
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            Color(red: 30/255, green: 30/255, blue: 30/255).edgesIgnoringSafeArea(.all)
            
            if isLoading {
                VStack {
                    ProgressView().padding()
                    Text("获取数据中...").foregroundColor(.gray)
                }
            } else if let box = data {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        TeamScoreBoardView(box: box)
                        PlayerStatsSection(teamName: "\(box.awayName) (客)", players: box.awayPlayers)
                        PlayerStatsSection(teamName: "\(box.homeName) (主)", players: box.homePlayers)
                    }
                    .padding(16)
                }
            } else {
                Text("暂无数据或比赛尚未开始").foregroundColor(.gray)
            }
        }
        // 【高度与宽度自适应修复】：整体调小适配 13-14 英寸屏幕。使用同一类的弹性修饰符。
        .frame(minWidth: 320, idealWidth: 380, maxWidth: 500, minHeight: 400, idealHeight: 550, maxHeight: 850)
        .preferredColorScheme(.dark)
        .onAppear(perform: fetchBoxscore)
        .onHover { hovering in
            popoverManager.isPopoverHovered = hovering
            if !hovering {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if !popoverManager.isPopoverHovered && popoverManager.activeGameId == gameId {
                        popoverManager.activeGameId = nil
                    }
                }
            }
        }
    }
    
    func fetchBoxscore() {
        let urlString = "https://cdn.nba.com/static/json/liveData/boxscore/boxscore_\(gameId).json"
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { d, _, _ in
            guard let d = d, let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let g = json["game"] as? [String: Any] else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            
            let gameStatus = (g["gameStatus"] as? Int) ?? 1
            let isLive = gameStatus == 2
            
            func parsePeriods(_ teamData: [String: Any]?) -> [Int] {
                guard let p = teamData?["periods"] as? [[String: Any]] else { return [] }
                return p.sorted(by: { ($0["period"] as? Int ?? 0) < ($1["period"] as? Int ?? 0) })
                        .compactMap { $0["score"] as? Int }
            }
            
            func parsePlayers(_ teamData: [String: Any]?) -> [PlayerStat] {
                guard let players = teamData?["players"] as? [[String: Any]] else { return [] }
                return players.compactMap { p in
                    guard let stats = p["statistics"] as? [String: Any], let pts = stats["points"] as? Int else { return nil }
                    
                    let firstName = (p["firstName"] as? String) ?? ""
                    let familyName = (p["familyName"] as? String) ?? ""
                    let fallbackName = (p["nameI"] as? String) ?? familyName
                    let name = PlayerTranslator.shared.translate(firstName: firstName, familyName: familyName, fallback: fallbackName)
                    
                    let starter = (p["starter"] as? String) == "1"
                    let onCourt = isLive && (p["oncourt"] as? String) == "1"
                    
                    // Format time as 分:秒:毫秒
                    var rawTime = (stats["minutes"] as? String) ?? "00:00"
                    rawTime = rawTime.replacingOccurrences(of: "PT", with: "")
                    var m = "00"; var s = "00"; var ms = "00"
                    
                    if rawTime.contains("M") {
                        let comps = rawTime.components(separatedBy: "M")
                        m = comps[0]
                        rawTime = comps.count > 1 ? comps[1] : ""
                    }
                    if rawTime.contains("S") {
                        rawTime = rawTime.replacingOccurrences(of: "S", with: "")
                        if rawTime.contains(".") {
                            let parts = rawTime.components(separatedBy: ".")
                            s = parts[0]
                            ms = parts.count > 1 ? parts[1] : "00"
                        } else {
                            s = rawTime
                        }
                    }
                    if m.count == 1 { m = "0" + m }
                    if s.count == 1 { s = "0" + s }
                    let timeStr = "\(m):\(s)"
                    
                    return PlayerStat(
                        name: name, time: timeStr, pts: pts,
                        reb: (stats["reboundsTotal"] as? Int) ?? 0,
                        ast: (stats["assists"] as? Int) ?? 0,
                        fg: "\(stats["fieldGoalsMade"] ?? 0)/\(stats["fieldGoalsAttempted"] ?? 0)",
                        threePt: "\(stats["threePointersMade"] ?? 0)/\(stats["threePointersAttempted"] ?? 0)",
                        ft: "\(stats["freeThrowsMade"] ?? 0)/\(stats["freeThrowsAttempted"] ?? 0)",
                        plusMinus: (stats["plusMinusPoints"] as? Int) ?? 0,
                        onCourt: onCourt, isStarter: starter
                    )
                }.sorted(by: {
                    if isLive {
                        if $0.onCourt != $1.onCourt { return $0.onCourt }
                    } else {
                        if $0.isStarter != $1.isStarter { return $0.isStarter }
                    }
                    return $0.pts > $1.pts
                })
            }
            
            let aData = g["awayTeam"] as? [String: Any]
            let hData = g["homeTeam"] as? [String: Any]
            
            let awayTri = aData?["teamTricode"] as? String ?? ""
            let homeTri = hData?["teamTricode"] as? String ?? ""
            
            let model = BoxscoreModel(
                // 【修改点】：直接通过中文翻译字典把 popover 里的球队名也汉化
                awayName: popoverTeamTranslation[awayTri] ?? (aData?["teamName"] as? String ?? "客队"),
                homeName: popoverTeamTranslation[homeTri] ?? (hData?["teamName"] as? String ?? "主队"),
                awayScore: aData?["score"] as? Int ?? 0,
                homeScore: hData?["score"] as? Int ?? 0,
                awayPeriods: parsePeriods(aData),
                homePeriods: parsePeriods(hData),
                awayPlayers: parsePlayers(aData),
                homePlayers: parsePlayers(hData)
            )
            DispatchQueue.main.async { self.data = model; self.isLoading = false }
        }.resume()
    }
}

// 球队总分板组件
struct TeamScoreBoardView: View {
    let box: BoxscoreModel
    var body: some View {
        let maxPeriods = max(4, max(box.awayPeriods.count, box.homePeriods.count))
        
        VStack(spacing: 8) {
            HStack {
                Text("球队").frame(width: 70, alignment: .leading)
                Spacer()
                ForEach(0..<maxPeriods, id: \.self) { i in
                    Text(i < 4 ? "Q\(i+1)" : "OT\(i-3)").frame(width: 22, alignment: .center)
                }
                Text("总").frame(width: 30, alignment: .trailing)
            }.font(.system(size: 10)).foregroundColor(.gray)
            
            Divider().background(Color.white.opacity(0.1))
            
            ScoreRow(name: box.awayName, periods: box.awayPeriods, total: box.awayScore, maxP: maxPeriods)
            ScoreRow(name: box.homeName, periods: box.homePeriods, total: box.homeScore, maxP: maxPeriods)
        }
        .padding(10).background(Color(white: 0.15).cornerRadius(10))
    }
    
    struct ScoreRow: View {
        let name: String; let periods: [Int]; let total: Int; let maxP: Int
        var body: some View {
            HStack {
                Text(name).frame(width: 70, alignment: .leading).font(.system(size: 12, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                Spacer()
                ForEach(0..<maxP, id: \.self) { i in
                    Text(i < periods.count ? "\(periods[i])" : "-").frame(width: 22, alignment: .center).foregroundColor(.white.opacity(0.8)).font(.system(size: 12))
                }
                Text("\(total)").frame(width: 30, alignment: .trailing).font(.system(size: 13, weight: .bold)).foregroundColor(.orange)
            }
        }
    }
}

// 球员数据小节组件
struct PlayerStatsSection: View {
    let teamName: String
    let players: [PlayerStat]
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(teamName).font(.system(size: 12, weight: .bold)).foregroundColor(.white.opacity(0.8))
                Spacer()
                if players.count > 8 {
                    Button(action: { withAnimation { isExpanded.toggle() } }) {
                        HStack(spacing: 2) {
                            Text(isExpanded ? "收起" : "展开 (\(players.count))")
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                    }.buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 8)
            
            // 数据表头 (极度紧凑间距)
            HStack(spacing: 0) {
                Text("球员").frame(width: 100, alignment: .leading)
                Text("时间").frame(width: 40, alignment: .center)
                Text("分").frame(width: 22, alignment: .center)
                Text("板").frame(width: 22, alignment: .center)
                Text("助").frame(width: 22, alignment: .center)
                Text("投篮").frame(width: 32, alignment: .center)
                Text("三分").frame(width: 32, alignment: .center)
                Text("罚球").frame(width: 32, alignment: .center)
                Text("+/-").frame(width: 28, alignment: .trailing)
            }
            .font(.system(size: 10)).foregroundColor(.gray)
            .padding(.horizontal, 10).padding(.bottom, 6)
            
            Divider().background(Color.white.opacity(0.1))
            
            let displayPlayers = isExpanded ? players : Array(players.prefix(8))
            VStack(spacing: 0) {
                ForEach(displayPlayers.indices, id: \.self) { idx in
                    let p = displayPlayers[idx]
                    HStack(spacing: 0) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(p.onCourt ? Color.orange : Color.clear)
                                .frame(width: 5, height: 5)
                            Text(p.name).lineLimit(1)
                                .foregroundColor(p.onCourt ? .orange : (p.isStarter ? .white : .white.opacity(0.6)))
                        }.frame(width: 100, alignment: .leading)
                        
                        Text(p.time).frame(width: 40, alignment: .center).foregroundColor(.gray)
                        Text("\(p.pts)").frame(width: 22, alignment: .center).foregroundColor(.orange).font(.system(size: 11, weight: .bold))
                        Text("\(p.reb)").frame(width: 22, alignment: .center)
                        Text("\(p.ast)").frame(width: 22, alignment: .center)
                        Text(p.fg).frame(width: 32, alignment: .center).foregroundColor(.gray)
                        Text(p.threePt).frame(width: 32, alignment: .center).foregroundColor(.gray)
                        Text(p.ft).frame(width: 32, alignment: .center).foregroundColor(.gray)
                        
                        Text(p.plusMinus > 0 ? "+\(p.plusMinus)" : "\(p.plusMinus)")
                            .frame(width: 28, alignment: .trailing)
                            .foregroundColor(p.plusMinus > 0 ? .green : (p.plusMinus < 0 ? .red : .gray))
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(idx % 2 == 0 ? Color.clear : Color.white.opacity(0.02))
                }
            }
        }
        .background(Color(white: 0.12).cornerRadius(10))
    }
}
