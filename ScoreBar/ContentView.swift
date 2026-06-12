import SwiftUI

// MARK: - 球员时间格式化
func formatPlayerTime(_ time: String) -> String {
    if time.contains(":") {
        // If seconds are :00, just show minutes (e.g., "23:00" -> "23")
        if time.hasSuffix(":00") {
            return String(time.dropLast(3))
        }
        return time
    }
    if let min = Int(time) { return "\(min)" }
    return time
}

// MARK: - 悬停状态管理器 (全局唯一绑定)
class PopoverManager: ObservableObject {
    @Published var activeGameId: String? = nil
    @Published var isPopoverHovered: Bool = false
}

// MARK: - 主列表界面
struct ContentView: View {
    @EnvironmentObject var viewModel: SportsViewModel
    @StateObject private var popoverManager = PopoverManager()
    @StateObject private var pinnedManager = GlobalPinnedGameManager.shared
    @AppStorage(ThemeManager.selectedThemeKey) private var selectedTheme: String = AppTheme.purpleNight.rawValue
    @AppStorage("selectedSport") private var selectedSport: String = "nba"

    private var currentTheme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .purpleNight
    }

    private var theme: AppTheme { ThemeManager.current }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: currentTheme.backgroundGradient),
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Picker("", selection: $selectedSport) {
                        Text("🏀 NBA").tag("nba")
                        Text("⚽ 足球").tag("soccer")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 160)
                    .foregroundColor(currentTheme.textPrimary)
                    .onChange(of: selectedSport) { newValue in
                        SportModeManager.shared.activeSport = newValue
                    }

                    Spacer()

                    if #available(macOS 14.0, *) {
                        SettingsLink {
                            Image(systemName: "gearshape.fill").foregroundColor(theme.headerIcon).font(.system(size: 14))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.trailing, 8)
                    } else {
                        Button(action: {
                            NSApp.sendAction(Selector("showSettingsWindow:"), to: nil, from: nil)
                        }) {
                            Image(systemName: "gearshape.fill").foregroundColor(theme.headerIcon).font(.system(size: 14))
                        }.buttonStyle(PlainButtonStyle())
                            .padding(.trailing, 8)
                    }

                    Button(action: { NSApplication.shared.terminate(nil) }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(theme.headerIcon).font(.system(size: 14))
                    }.buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 16).padding(.vertical, 12).background(theme.headerBackground)

                if selectedSport == "nba" {
                    nbaContentView
                } else {
                    SoccerContentView()
                }
            }
        }
        .frame(minWidth: 320, idealWidth: 380, maxWidth: 500, minHeight: 400, idealHeight: 550, maxHeight: 850)
        .preferredColorScheme(selectedTheme == AppTheme.pureWhite.rawValue ? .light : .dark)
        .environmentObject(popoverManager)
    }

    private var nbaContentView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    // NBA置顶横幅
                    if let pinnedId = viewModel.pinnedGameId, let pinnedGame = viewModel.games.first(where: { $0.id == pinnedId }) {
                        PinnedGameBannerView(game: pinnedGame)
                            .padding(.bottom, 4)
                    }
                    // 足球置顶横幅（跨模块显示）
                    if pinnedManager.pinnedSport == "soccer",
                       let soccerGame = pinnedManager.cachedSoccerGame {
                        SoccerPinnedBannerView(game: soccerGame)
                            .padding(.bottom, 4)
                    }

                    if viewModel.isLoading && viewModel.games.isEmpty {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: theme.loadingIndicator)).padding(.top, 40)
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
                Circle().fill(theme.liveIndicator).frame(width: 6, height: 6).shadow(color: theme.liveIndicator.opacity(0.4), radius: 4, x: 0, y: 0)
                Text("LIVEBAR PRO")
            }
            .font(.system(size: 10, weight: .bold)).foregroundColor(theme.statusBarText).padding(12).background(theme.statusBarBackground)
        }
    }
}

// MARK: - 大图置顶行
struct PinnedGameBannerView: View {
    let game: Game
    @AppStorage(ThemeManager.selectedThemeKey) private var selectedTheme: String = AppTheme.purpleNight.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .purpleNight
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "pin.fill").foregroundColor(theme.statusLive).font(.system(size: 10))
                Text("已置顶 • 对阵详情").font(.system(size: 11, weight: .bold)).foregroundColor(theme.statusLive)
                Spacer()
                Text("今日焦点战").font(.system(size: 11)).foregroundColor(theme.textSecondary)
            }

            HStack(alignment: .center) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(theme.logoCircleBackground).frame(width: 36, height: 36)
                        TeamLogoManager.shared.logoView(tricode: game.homeTeam.tricode, networkURL: game.homeTeam.logo, size: 24)
                    }
                    Text(game.homeTeam.name).font(.system(size: 11, weight: .bold)).foregroundColor(theme.textPrimary).lineLimit(1)
                    if game.isPlayoff, let homeWins = game.homeTeam.seriesWins {
                        Text("(\(homeWins))")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(theme.seriesScoreColor)
                    }
                }
                .frame(width: 70)

                Spacer()

                VStack(spacing: 4) {
                    if game.status == "scheduled" {
                        Text("VS").font(.system(size: 24, weight: .black, design: .rounded)).foregroundColor(theme.textPrimary)
                    } else {
                        Text("\(game.homeTeam.score) - \(game.awayTeam.score)")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(theme.textPrimary)
                            .monospacedDigit()
                    }

                    if game.status == "live" {
                        Text("\(translatePeriod(game.period)) \(formatGameTime(game.time))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(theme.statusLive)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(theme.statusLive.opacity(0.2).cornerRadius(4))
                    } else if game.status == "final" {
                        Text("已结束").font(.system(size: 11, weight: .bold)).foregroundColor(theme.statusFinal)
                    } else {
                        Text(game.time).font(.system(size: 11, weight: .bold)).foregroundColor(theme.statusFinal)
                    }
                }

                Spacer()

                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(theme.logoCircleBackground).frame(width: 36, height: 36)
                        TeamLogoManager.shared.logoView(tricode: game.awayTeam.tricode, networkURL: game.awayTeam.logo, size: 24)
                    }
                    Text(game.awayTeam.name).font(.system(size: 11, weight: .bold)).foregroundColor(theme.textPrimary).lineLimit(1)
                    if game.isPlayoff, let awayWins = game.awayTeam.seriesWins {
                        Text("(\(awayWins))")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(theme.seriesScoreColor)
                    }
                }
                .frame(width: 70)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            LinearGradient(gradient: Gradient(colors: theme.pinnedGradient), startPoint: .top, endPoint: .bottom)
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
        // 0.0 表示该节刚结束，显示"已结束"
        if t == "0.0" || t == "0" || t.isEmpty {
            return "已结束"
        }
        if let last = t.split(separator: " ").last, String(last).contains(":") {
            return String(last)
        }
        if t.contains(":") {
            return t.replacingOccurrences(of: "Q1 ", with: "").replacingOccurrences(of: "Q2 ", with: "").replacingOccurrences(of: "Q3 ", with: "").replacingOccurrences(of: "Q4 ", with: "")
        }
        return t
    }
}

// MARK: - 足球置顶比赛横幅（跨模块显示）
struct SoccerPinnedBannerView: View {
    let game: SoccerGame
    @AppStorage(ThemeManager.selectedThemeKey) private var selectedTheme: String = AppTheme.purpleNight.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .purpleNight
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "pin.fill").foregroundColor(theme.statusLive).font(.system(size: 10))
                Text("已置顶 • 足球").font(.system(size: 11, weight: .bold)).foregroundColor(theme.statusLive)
                Spacer()
                Text(game.competition).font(.system(size: 11)).foregroundColor(theme.textSecondary)
            }

            HStack(alignment: .center) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(theme.logoCircleBackground).frame(width: 36, height: 36)
                        TeamLogoManager.shared.logoView(tricode: game.homeTeam.countryCode, networkURL: game.homeTeam.logo, size: 24)
                    }
                    Text(game.homeTeam.name).font(.system(size: 11, weight: .bold)).foregroundColor(theme.textPrimary).lineLimit(1)
                }
                .frame(width: 70)

                Spacer()

                VStack(spacing: 4) {
                    if game.status == "scheduled" {
                        Text("VS").font(.system(size: 24, weight: .black, design: .rounded)).foregroundColor(theme.textPrimary)
                    } else {
                        Text("\(game.homeTeam.score) - \(game.awayTeam.score)")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(theme.textPrimary)
                            .monospacedDigit()
                    }

                    if game.status == "live" {
                        let displayTime = (game.time == "0.0" || game.time == "0" || game.time.isEmpty) ? "已结束" : game.time
                        Text("\(game.period) \(displayTime)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(theme.statusLive)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(theme.statusLive.opacity(0.2).cornerRadius(4))
                    } else if game.status == "final" {
                        Text("已结束").font(.system(size: 11, weight: .bold)).foregroundColor(theme.statusFinal)
                    } else {
                        Text(formatGameTime(game.time)).font(.system(size: 11, weight: .bold)).foregroundColor(theme.statusFinal)
                    }
                }

                Spacer()

                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(theme.logoCircleBackground).frame(width: 36, height: 36)
                        TeamLogoManager.shared.logoView(tricode: game.awayTeam.countryCode, networkURL: game.awayTeam.logo, size: 24)
                    }
                    Text(game.awayTeam.name).font(.system(size: 11, weight: .bold)).foregroundColor(theme.textPrimary).lineLimit(1)
                }
                .frame(width: 70)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            LinearGradient(gradient: Gradient(colors: theme.pinnedGradient), startPoint: .top, endPoint: .bottom)
        )
        .cornerRadius(12)
    }

    private func formatGameTime(_ time: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date: Date? = formatter.date(from: time)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: time)
        }
        if let d = date {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "M月d日 HH:mm"
            displayFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            return displayFormatter.string(from: d)
        }
        return time
    }
}

// MARK: - 比赛行
struct GameRowView: View {
    let game: Game
    @EnvironmentObject var viewModel: SportsViewModel
    @EnvironmentObject var popoverManager: PopoverManager
    @State private var isHovered = false
    @State private var hoverTask: DispatchWorkItem?
    @State private var boxData: BoxscoreModel? = nil
    @State private var isFetchingBox = false
    private var theme: AppTheme { ThemeManager.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                teamInfoView
                Spacer()
                scoreAndPinView
            }
            .padding(14)

            /* ===== 小节分展开区域 (暂时隐藏) =====
            if popoverManager.activeGameId == game.id {
                if let box = boxData {
                    TeamScoreBoardView(box: box)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .top)),
                            removal: .opacity
                        ))
                } else if isFetchingBox {
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Spacer()
                    }
                    .padding(.bottom, 14)
                }
            }
            ===== 小节分展开区域结束 ===== */
        }
        .background(backgroundView)
        .cornerRadius(12)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.snappy(duration: 0.2), value: isHovered)
        .animation(.snappy(duration: 0.3), value: popoverManager.activeGameId == game.id)
        .onHover(perform: handleHover)
        .onTapGesture(perform: handleTap)
        .popover(isPresented: popoverBinding, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            GameDetailView(gameId: game.id, externalBoxData: boxData)
        }
        .onChange(of: popoverManager.activeGameId) { newValue in
            if newValue == game.id {
                fetchBoxscore()
            }
        }
        .onChange(of: viewModel.games) { _ in
            if popoverManager.activeGameId == game.id && game.status == "live" {
                fetchBoxscore()
            }
        }
    }
    
    private func fetchBoxscore() {
        guard !isFetchingBox else { return }
        isFetchingBox = true

        let urlString = "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/summary?event=\(game.id)"
        print("📡 [fetchBoxscore] gameId=\(game.id) url=\(urlString)")

        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { d, resp, err in
            if let err = err {
                print("❌ [fetchBoxscore] network error: \(err.localizedDescription)")
                DispatchQueue.main.async { self.isFetchingBox = false }
                return
            }

            guard let data = d else {
                print("❌ [fetchBoxscore] no data received")
                DispatchQueue.main.async { self.isFetchingBox = false }
                return
            }

            print("📦 [fetchBoxscore] data size: \(data.count) bytes")

            // Debug: print raw JSON structure
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("🔍 [fetchBoxscore] JSON keys: \(json.keys.map { $0 })")
                if let code = json["code"] as? Int {
                    print("❌ [fetchBoxscore] API error code: \(code)")
                }
                if let box = json["boxscore"] as? [String: Any] {
                    print("🔍 [fetchBoxscore] boxscore keys: \(box.keys.map { $0 })")
                    if let teams = box["teams"] as? [[String: Any]] {
                        print("🔍 [fetchBoxscore] teams count: \(teams.count)")
                        for (i, t) in teams.enumerated() {
                            if let teamInfo = t["team"] as? [String: Any] {
                                print("   team[\(i)] abbreviation: \(teamInfo["abbreviation"] ?? "nil")")
                            }
                            if let players = t["players"] as? [[String: Any]] {
                                print("   team[\(i)] players count: \(players.count)")
                            }
                        }
                    }
                }
                if let gameInfo = json["gameInfo"] as? [String: Any] {
                    print("🔍 [fetchBoxscore] gameInfo keys: \(gameInfo.keys.map { $0 })")
                }
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ [fetchBoxscore] failed to parse JSON")
                DispatchQueue.main.async { self.isFetchingBox = false }
                return
            }

            if let code = json["code"] as? Int {
                print("❌ [fetchBoxscore] API returned error code: \(code)")
                DispatchQueue.main.async { self.isFetchingBox = false }
                return
            }

            guard let box = json["boxscore"] as? [String: Any] else {
                print("❌ [fetchBoxscore] no 'boxscore' key in response")
                DispatchQueue.main.async { self.isFetchingBox = false }
                return
            }

            guard let teams = box["teams"] as? [[String: Any]] else {
                print("❌ [fetchBoxscore] no 'boxscore.teams' in response")
                DispatchQueue.main.async { self.isFetchingBox = false }
                return
            }

            let _ = json["gameInfo"] as? [String: Any] ?? [:]

            // Status is in header.competitions[0].status
            let statusType = json["header"] as? [String: Any] ?? [:]
            let competitions = statusType["competitions"] as? [[String: Any]] ?? []
            let competition = competitions.first ?? [:]
            let status = competition["status"] as? [String: Any] ?? [:]
            let state = status["type"] as? [String: Any] ?? [:]
            let isLive = (state["state"] as? String) == "in"
            let period = status["period"] as? Int ?? 0
            let displayClock = status["displayClock"] as? String ?? ""

            print("✅ [fetchBoxscore] parsed successfully, isLive=\(isLive) period=\(period) clock=\(displayClock)")
            print("   awayPlayers: \(parsePlayers(teams.first).count), homePlayers: \(parsePlayers(teams.count > 1 ? teams[1] : nil).count)")

            // Parse team scores and period scores from header competitors
            let competitors = competition["competitors"] as? [[String: Any]] ?? []
            var awayScore = "0", homeScore = "0"
            var awayTri = "", homeTri = ""
            var awayLinescores: [Int] = [], homeLinescores: [Int] = []
            for comp in competitors {
                let teamInfo = comp["team"] as? [String: Any] ?? [:]
                let abbr = teamInfo["abbreviation"] as? String ?? ""
                let score = comp["score"] as? String ?? "0"
                let homeAway = comp["homeAway"] as? String ?? ""
                let linescores = comp["linescores"] as? [[String: Any]] ?? []
                let periodScores = linescores.compactMap { Int($0["displayValue"] as? String ?? "0") }

                if homeAway == "home" {
                    homeScore = score
                    homeTri = abbr
                    homeLinescores = periodScores
                } else {
                    awayScore = score
                    awayTri = abbr
                    awayLinescores = periodScores
                }
            }

            print("   [fetchBoxscore] awayLinescores=\(awayLinescores), homeLinescores=\(homeLinescores)")

            func parsePeriods(_ teamData: [String: Any]?) -> [Int] {
                return []
            }

            func parsePlayers(_ teamData: [String: Any]?) -> [PlayerStat] {
                // ESPN player data is in boxscore.players, not boxscore.teams
                guard let allPlayers = json["boxscore"] as? [String: Any],
                      let playerGroups = allPlayers["players"] as? [[String: Any]] else {
                    return []
                }

                // Find player group matching this team abbreviation
                guard let teamAbbrev = teamData?["team"] as? [String: Any],
                      let abbrev = teamAbbrev["abbreviation"] as? String else { return [] }

                // Find the player group for this team
                let group = playerGroups.first { ($0["team"] as? [String: Any])?["abbreviation"] as? String == abbrev }
                guard let stats = group?["statistics"] as? [[String: Any]], let statBlock = stats.first else { return [] }

                // statBlock.keys = ["minutes", "points", "fieldGoalsMade-fieldGoalsAttempted", ...]
                // statBlock.athletes[n].athlete = player info
                // statBlock.athletes[n].stats = [value1, value2, ...] mapped to keys
                let keys = statBlock["keys"] as? [String] ?? []
                let athletes = statBlock["athletes"] as? [[String: Any]] ?? []

                return athletes.compactMap { a in
                    let athlete = a["athlete"] as? [String: Any] ?? [:]
                    let playerStats = a["stats"] as? [String] ?? []
                    let starter = a["starter"] as? Bool ?? false
                    let active = a["active"] as? Bool ?? false
                    let didNotPlay = a["didNotPlay"] as? Bool ?? false

                    // Skip players who didn't play (didNotPlay=True)
                    if didNotPlay { return nil }

                    let displayName = athlete["displayName"] as? String ?? ""
                    let lastName = athlete["lastName"] as? String ?? ""
                    let firstName = athlete["firstName"] as? String ?? ""
                    let name = PlayerTranslator.shared.translate(firstName: firstName, familyName: lastName, fallback: displayName.isEmpty ? lastName : displayName)

                    // Map stats by key index
                    func getStat(_ key: String, defaultVal: String = "0") -> String {
                        if let idx = keys.firstIndex(of: key), idx < playerStats.count {
                            return playerStats[idx]
                        }
                        return defaultVal
                    }

                    func getInt(_ key: String, defaultVal: Int = 0) -> Int {
                        return Int(getStat(key)) ?? defaultVal
                    }

                    let minutes = getStat("minutes")
                    let pts = getInt("points")
                    let reboundsTotal = getInt("rebounds")
                    let assists = getInt("assists")

                    // FG: fieldGoalsMade-fieldGoalsAttempted
                    let fgStr = getStat("fieldGoalsMade-fieldGoalsAttempted")
                    let fgParts = fgStr.split(separator: "-")
                    let fgm = fgParts.count > 0 ? Int(fgParts[0]) ?? 0 : 0
                    let fga = fgParts.count > 1 ? Int(fgParts[1]) ?? 0 : 0

                    // 3PT: threePointFieldGoalsMade-threePointFieldGoalsAttempted
                    let threeStr = getStat("threePointFieldGoalsMade-threePointFieldGoalsAttempted")
                    let threeParts = threeStr.split(separator: "-")
                    let tpm = threeParts.count > 0 ? Int(threeParts[0]) ?? 0 : 0
                    let tpa = threeParts.count > 1 ? Int(threeParts[1]) ?? 0 : 0

                    // FT: freeThrowsMade-freeThrowsAttempted
                    let ftStr = getStat("freeThrowsMade-freeThrowsAttempted")
                    let ftParts = ftStr.split(separator: "-")
                    let ftm = ftParts.count > 0 ? Int(ftParts[0]) ?? 0 : 0
                    let fta = ftParts.count > 1 ? Int(ftParts[1]) ?? 0 : 0

                    let plusMinusStr = getStat("plusMinus", defaultVal: "0")
                    let plusMinus = Int(plusMinusStr.replacingOccurrences(of: "+", with: "")) ?? 0

                    let onCourt = isLive && active

                    return PlayerStat(
                        name: name, time: minutes, pts: pts,
                        reb: reboundsTotal,
                        ast: assists,
                        fg: "\(fgm)/\(fga)",
                        threePt: "\(tpm)/\(tpa)",
                        ft: "\(ftm)/\(fta)",
                        plusMinus: plusMinus,
                        onCourt: onCourt, isStarter: starter
                    )
                }.sorted(by: { p1, p2 in
                    // First sort: on-court (live) or starters (finished) come first
                    let p1Priority = p1.onCourt ? 0 : (p1.isStarter ? 1 : 2)
                    let p2Priority = p2.onCourt ? 0 : (p2.isStarter ? 1 : 2)
                    if p1Priority != p2Priority { return p1Priority < p2Priority }

                    // Second sort: during game sort by pts, after game sort by plusMinus
                    if isLive {
                        return p1.pts > p2.pts
                    } else {
                        return p1.plusMinus > p2.plusMinus
                    }
                })
            }

            let awayData = teams.first?["team"] as? [String: Any]
            let homeData = teams.count > 1 ? (teams[1]["team"] as? [String: Any]) : nil

            let model = BoxscoreModel(
                awayName: popoverTeamTranslation[awayTri] ?? (awayData?["name"] as? String ?? "客队"),
                homeName: popoverTeamTranslation[homeTri] ?? (homeData?["name"] as? String ?? "主队"),
                awayScore: Int(awayScore) ?? 0,
                homeScore: Int(homeScore) ?? 0,
                awayPeriods: awayLinescores,
                homePeriods: homeLinescores,
                awayPlayers: parsePlayers(teams.first),
                homePlayers: parsePlayers(teams.count > 1 ? teams[1] : nil)
            )
            DispatchQueue.main.async {
                self.boxData = model
                self.isFetchingBox = false
            }
        }.resume()
    }
    
    // 【修改点】：追加了球队 Logo 显示
    private var teamInfoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // 主队
                HStack(spacing: 3) {
                    TeamLogoManager.shared.logoView(tricode: game.homeTeam.tricode, networkURL: game.homeTeam.logo, size: 16)

                    Text(game.homeTeam.name).font(.system(size: 13, weight: .bold)).foregroundColor(theme.textPrimary)

                    // Playoff series score
                    if game.isPlayoff, let homeWins = game.homeTeam.seriesWins {
                        Text("(\(homeWins))")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(theme.seriesScoreColor)
                    }
                }

                Text(":").font(.system(size: 10, weight: .black)).foregroundColor(theme.textSecondary.opacity(0.5))

                // 客队
                HStack(spacing: 3) {
                    TeamLogoManager.shared.logoView(tricode: game.awayTeam.tricode, networkURL: game.awayTeam.logo, size: 16)

                    Text(game.awayTeam.name).font(.system(size: 13, weight: .bold)).foregroundColor(theme.textPrimary)

                    // Playoff series score: show only when isPlayoff and seriesWins is not nil
                    if game.isPlayoff, let awayWins = game.awayTeam.seriesWins {
                        Text("(\(awayWins))")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(theme.seriesScoreColor)
                    }
                }
            }

            HStack(spacing: 6) {
                if game.status == "live" { Circle().fill(theme.statusLive).frame(width: 6, height: 6) }
                Text(statusText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(game.status == "live" ? theme.statusLive : theme.textSecondary)
            }
        }
    }

    private var statusText: String {
        if game.status == "live" {
            let displayTime = (game.time == "0.0" || game.time == "0" || game.time.isEmpty) ? "已结束" : game.time
            return "直播中 • \(displayTime)"
        }
        if game.status == "final" { return "已结束" }
        // scheduled: time 字段是 ISO 开赛时间,用 formatGameTime 美化
        return formatScheduledTime(game.time)
    }

    private func formatScheduledTime(_ time: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date: Date? = formatter.date(from: time)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: time)
        }
        if let d = date {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "M月d日 HH:mm"
            displayFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            return displayFormatter.string(from: d)
        }
        return "未开赛"
    }

    private var scoreAndPinView: some View {
        HStack {
            if game.status == "scheduled" {
                Text("-- : --").font(.system(size: 20, weight: .black)).foregroundColor(theme.textScoreDim).monospacedDigit()
            } else {
                Text("\(game.homeTeam.score) - \(game.awayTeam.score)").font(.system(size: 20, weight: .black)).foregroundColor(theme.scoreText).monospacedDigit()
            }

            Button(action: togglePin) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundColor(isPinned ? theme.statusLive : theme.textSecondary.opacity(0.5))
                    .font(.system(size: 14))
                    .padding(.leading, 8)
            }
            .buttonStyle(PlainButtonStyle())
            .help(isPinned ? "取消置顶" : "置顶比分")
        }
    }

    private var isPinned: Bool {
        GlobalPinnedGameManager.shared.isPinned(gameId: game.id, sport: "nba")
    }

    private func togglePin() {
        GlobalPinnedGameManager.shared.togglePin(gameId: game.id, sport: "nba")
    }

    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(isHovered ? theme.cardHoverBackground : theme.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isHovered ? theme.cardHoverBorder : theme.cardBorder, lineWidth: 1))
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
    "MIA": "热火", "MIL": "雄鹿", "MIN": "森林狼", "NOP": "鹈鹕", "NY": "尼克斯", "NYK": "尼克斯",
    "OKC": "雷霆", "ORL": "魔术", "PHI": "76人", "PHX": "太阳", "POR": "开拓者",
    "SAC": "国王", "SA": "马刺", "SAS": "马刺", "TOR": "猛龙", "UTA": "爵士", "WAS": "奇才"
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
    let externalBoxData: BoxscoreModel?
    @EnvironmentObject var popoverManager: PopoverManager
    @State private var data: BoxscoreModel? = nil
    @State private var isLoading = true
    @AppStorage(ThemeManager.selectedThemeKey) private var selectedTheme: String = AppTheme.purpleNight.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .purpleNight
    }

    var body: some View {
        ZStack {
            theme.popoverBackground.edgesIgnoringSafeArea(.all)

            let displayData = externalBoxData ?? data
            let isDisplayLoading = externalBoxData == nil ? isLoading : false

            if isDisplayLoading {
                VStack {
                    ProgressView().padding()
                    Text("获取数据中...").foregroundColor(theme.textSecondary)
                }
            } else if let box = displayData {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        TeamScoreBoardView(box: box)
                        PlayerStatsSection(teamName: "\(box.homeName) (主)", players: box.homePlayers)
                        PlayerStatsSection(teamName: "\(box.awayName) (客)", players: box.awayPlayers)
                    }
                    .padding(12)
                }
            } else {
                Text("暂无数据或比赛尚未开始").foregroundColor(theme.textSecondary)
            }
        }
        .frame(minWidth: 320, idealWidth: 380, maxWidth: 500, minHeight: 400, idealHeight: 600, maxHeight: 950)
        .preferredColorScheme(selectedTheme == AppTheme.pureWhite.rawValue ? .light : .dark)
        .onAppear {
            if externalBoxData == nil {
                fetchBoxscore()
            }
        }
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
        // ESPN boxscore API - use eventId parameter
        let urlString = "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/summary?event=\(gameId)"
        print("📡 [PopoverBoxscoreView fetchBoxscore] gameId=\(gameId) url=\(urlString)")

        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { d, resp, err in
            if let err = err {
                print("❌ [PopoverBoxscoreView fetchBoxscore] network error: \(err.localizedDescription)")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            guard let data = d else {
                print("❌ [PopoverBoxscoreView fetchBoxscore] no data received")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            print("📦 [PopoverBoxscoreView fetchBoxscore] data size: \(data.count) bytes")

            // Debug: print raw JSON structure
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("🔍 [PopoverBoxscoreView fetchBoxscore] JSON keys: \(json.keys.map { $0 })")
                if let code = json["code"] as? Int {
                    print("❌ [PopoverBoxscoreView fetchBoxscore] API error code: \(code)")
                }
                if let box = json["boxscore"] as? [String: Any] {
                    print("🔍 [PopoverBoxscoreView fetchBoxscore] boxscore keys: \(box.keys.map { $0 })")
                    if let teams = box["teams"] as? [[String: Any]] {
                        print("🔍 [PopoverBoxscoreView fetchBoxscore] teams count: \(teams.count)")
                        for (i, t) in teams.enumerated() {
                            if let teamInfo = t["team"] as? [String: Any] {
                                print("   team[\(i)] abbreviation: \(teamInfo["abbreviation"] ?? "nil")")
                            }
                            if let players = t["players"] as? [[String: Any]] {
                                print("   team[\(i)] players count: \(players.count)")
                            }
                        }
                    }
                }
                if let gameInfo = json["gameInfo"] as? [String: Any] {
                    print("🔍 [PopoverBoxscoreView fetchBoxscore] gameInfo keys: \(gameInfo.keys.map { $0 })")
                }
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ [PopoverBoxscoreView fetchBoxscore] failed to parse JSON")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            if let code = json["code"] as? Int {
                print("❌ [PopoverBoxscoreView fetchBoxscore] API returned error code: \(code)")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            guard let box = json["boxscore"] as? [String: Any] else {
                print("❌ [PopoverBoxscoreView fetchBoxscore] no 'boxscore' key in response")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            guard let teams = box["teams"] as? [[String: Any]] else {
                print("❌ [PopoverBoxscoreView fetchBoxscore] no 'boxscore.teams' in response")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            let _ = json["gameInfo"] as? [String: Any] ?? [:]

            // Status is in header.competitions[0].status
            let statusType = json["header"] as? [String: Any] ?? [:]
            let competitions = statusType["competitions"] as? [[String: Any]] ?? []
            let competition = competitions.first ?? [:]
            let status = competition["status"] as? [String: Any] ?? [:]
            let state = status["type"] as? [String: Any] ?? [:]
            let isLive = (state["state"] as? String) == "in"
            let period = status["period"] as? Int ?? 0
            let displayClock = status["displayClock"] as? String ?? ""

            print("✅ [PopoverBoxscoreView fetchBoxscore] parsed successfully, isLive=\(isLive) period=\(period) clock=\(displayClock)")

            // Parse team scores and period scores from header competitors
            let competitors = competition["competitors"] as? [[String: Any]] ?? []
            var awayScore = "0", homeScore = "0"
            var awayTri = "", homeTri = ""
            var awayLinescores: [Int] = [], homeLinescores: [Int] = []
            for comp in competitors {
                let teamInfo = comp["team"] as? [String: Any] ?? [:]
                let abbr = teamInfo["abbreviation"] as? String ?? ""
                let score = comp["score"] as? String ?? "0"
                let homeAway = comp["homeAway"] as? String ?? ""
                let linescores = comp["linescores"] as? [[String: Any]] ?? []
                let periodScores = linescores.compactMap { Int($0["displayValue"] as? String ?? "0") }

                if homeAway == "home" {
                    homeScore = score
                    homeTri = abbr
                    homeLinescores = periodScores
                } else {
                    awayScore = score
                    awayTri = abbr
                    awayLinescores = periodScores
                }
            }

            func parsePeriods(_ teamData: [String: Any]?) -> [Int] {
                return []
            }

            func parsePlayers(_ teamData: [String: Any]?) -> [PlayerStat] {
                // ESPN player data is in boxscore.players, not boxscore.teams
                guard let allPlayers = json["boxscore"] as? [String: Any],
                      let playerGroups = allPlayers["players"] as? [[String: Any]] else {
                    return []
                }

                // Find player group matching this team abbreviation
                guard let teamAbbrev = teamData?["team"] as? [String: Any],
                      let abbrev = teamAbbrev["abbreviation"] as? String else { return [] }

                // Find the player group for this team
                let group = playerGroups.first { ($0["team"] as? [String: Any])?["abbreviation"] as? String == abbrev }
                guard let stats = group?["statistics"] as? [[String: Any]], let statBlock = stats.first else { return [] }

                // statBlock.keys = ["minutes", "points", "fieldGoalsMade-fieldGoalsAttempted", ...]
                // statBlock.athletes[n].athlete = player info
                // statBlock.athletes[n].stats = [value1, value2, ...] mapped to keys
                let keys = statBlock["keys"] as? [String] ?? []
                let athletes = statBlock["athletes"] as? [[String: Any]] ?? []

                return athletes.compactMap { a in
                    let athlete = a["athlete"] as? [String: Any] ?? [:]
                    let playerStats = a["stats"] as? [String] ?? []
                    let starter = a["starter"] as? Bool ?? false
                    let active = a["active"] as? Bool ?? false
                    let didNotPlay = a["didNotPlay"] as? Bool ?? false

                    // Skip players who didn't play (didNotPlay=True)
                    if didNotPlay { return nil }

                    let displayName = athlete["displayName"] as? String ?? ""
                    let lastName = athlete["lastName"] as? String ?? ""
                    let firstName = athlete["firstName"] as? String ?? ""
                    let name = PlayerTranslator.shared.translate(firstName: firstName, familyName: lastName, fallback: displayName.isEmpty ? lastName : displayName)

                    // Map stats by key index
                    func getStat(_ key: String, defaultVal: String = "0") -> String {
                        if let idx = keys.firstIndex(of: key), idx < playerStats.count {
                            return playerStats[idx]
                        }
                        return defaultVal
                    }

                    func getInt(_ key: String, defaultVal: Int = 0) -> Int {
                        return Int(getStat(key)) ?? defaultVal
                    }

                    let minutes = getStat("minutes")
                    let pts = getInt("points")
                    let reboundsTotal = getInt("rebounds")
                    let assists = getInt("assists")

                    // FG: fieldGoalsMade-fieldGoalsAttempted
                    let fgStr = getStat("fieldGoalsMade-fieldGoalsAttempted")
                    let fgParts = fgStr.split(separator: "-")
                    let fgm = fgParts.count > 0 ? Int(fgParts[0]) ?? 0 : 0
                    let fga = fgParts.count > 1 ? Int(fgParts[1]) ?? 0 : 0

                    // 3PT: threePointFieldGoalsMade-threePointFieldGoalsAttempted
                    let threeStr = getStat("threePointFieldGoalsMade-threePointFieldGoalsAttempted")
                    let threeParts = threeStr.split(separator: "-")
                    let tpm = threeParts.count > 0 ? Int(threeParts[0]) ?? 0 : 0
                    let tpa = threeParts.count > 1 ? Int(threeParts[1]) ?? 0 : 0

                    // FT: freeThrowsMade-freeThrowsAttempted
                    let ftStr = getStat("freeThrowsMade-freeThrowsAttempted")
                    let ftParts = ftStr.split(separator: "-")
                    let ftm = ftParts.count > 0 ? Int(ftParts[0]) ?? 0 : 0
                    let fta = ftParts.count > 1 ? Int(ftParts[1]) ?? 0 : 0

                    let plusMinusStr = getStat("plusMinus", defaultVal: "0")
                    let plusMinus = Int(plusMinusStr.replacingOccurrences(of: "+", with: "")) ?? 0

                    let onCourt = isLive && active

                    return PlayerStat(
                        name: name, time: minutes, pts: pts,
                        reb: reboundsTotal,
                        ast: assists,
                        fg: "\(fgm)/\(fga)",
                        threePt: "\(tpm)/\(tpa)",
                        ft: "\(ftm)/\(fta)",
                        plusMinus: plusMinus,
                        onCourt: onCourt, isStarter: starter
                    )
                }.sorted(by: { p1, p2 in
                    // First sort: on-court (live) or starters (finished) come first
                    let p1Priority = p1.onCourt ? 0 : (p1.isStarter ? 1 : 2)
                    let p2Priority = p2.onCourt ? 0 : (p2.isStarter ? 1 : 2)
                    if p1Priority != p2Priority { return p1Priority < p2Priority }

                    // Second sort: during game sort by pts, after game sort by plusMinus
                    if isLive {
                        return p1.pts > p2.pts
                    } else {
                        return p1.plusMinus > p2.plusMinus
                    }
                })
            }

            let awayData = teams.first?["team"] as? [String: Any]
            let homeData = teams.count > 1 ? (teams[1]["team"] as? [String: Any]) : nil

            let model = BoxscoreModel(
                awayName: popoverTeamTranslation[awayTri] ?? (awayData?["name"] as? String ?? "客队"),
                homeName: popoverTeamTranslation[homeTri] ?? (homeData?["name"] as? String ?? "主队"),
                awayScore: Int(awayScore) ?? 0,
                homeScore: Int(homeScore) ?? 0,
                awayPeriods: awayLinescores,
                homePeriods: homeLinescores,
                awayPlayers: parsePlayers(teams.first),
                homePlayers: parsePlayers(teams.count > 1 ? teams[1] : nil)
            )
            DispatchQueue.main.async { self.data = model; self.isLoading = false }
        }.resume()
    }
}

// 球队总分板组件
struct TeamScoreBoardView: View {
    let box: BoxscoreModel
    @AppStorage(ThemeManager.selectedThemeKey) private var selectedTheme: String = AppTheme.purpleNight.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .purpleNight
    }

    var body: some View {
        let maxPeriods = max(4, max(box.awayPeriods.count, box.homePeriods.count))

        VStack(spacing: 8) {
            HStack {
                Text("球队").frame(width: 70, alignment: .leading)
                Spacer()
                ForEach(0..<maxPeriods, id: \.self) { i in
                    Text(i < 4 ? "Q\(i+1)" : "OT\(i-3)").frame(width: 20, alignment: .center)
                }
                Text("总").frame(width: 28, alignment: .trailing)
            }.font(.system(size: 10, weight: .medium)).foregroundColor(theme.textSecondary)

            Divider().background(theme.dividerColor)

            ScoreRow(name: box.homeName, periods: box.homePeriods, total: box.homeScore, maxP: maxPeriods)
            ScoreRow(name: box.awayName, periods: box.awayPeriods, total: box.awayScore, maxP: maxPeriods)
        }
        .padding(8)
        .background(theme.scoreBoardBackground.cornerRadius(10))
    }

    struct ScoreRow: View {
        let name: String; let periods: [Int]; let total: Int; let maxP: Int
        @AppStorage(ThemeManager.selectedThemeKey) private var selectedTheme: String = AppTheme.purpleNight.rawValue

        private var theme: AppTheme {
            AppTheme(rawValue: selectedTheme) ?? .purpleNight
        }

        var body: some View {
            HStack {
                Text(name).frame(width: 70, alignment: .leading).font(.system(size: 12, weight: .semibold)).foregroundColor(theme.textPrimary).lineLimit(1)
                Spacer()
                ForEach(0..<maxP, id: \.self) { i in
                    Text(i < periods.count ? "\(periods[i])" : "-").frame(width: 22, alignment: .center).foregroundColor(theme.textTertiary).font(.system(size: 12))
                }
                Text("\(total)").frame(width: 30, alignment: .trailing).font(.system(size: 13, weight: .bold)).foregroundColor(theme.accentColor)
            }
        }
    }
}

// 球员数据小节组件
struct PlayerStatsSection: View {
    let teamName: String
    let players: [PlayerStat]
    @State private var isExpanded = false
    @AppStorage(ThemeManager.selectedThemeKey) private var selectedTheme: String = AppTheme.purpleNight.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .purpleNight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(teamName).font(.system(size: 12, weight: .bold)).foregroundColor(theme.textTertiary)
                if players.count > 8 {
                    Button(action: { withAnimation { isExpanded.toggle() } }) {
                        HStack(spacing: 2) {
                            Text(isExpanded ? "收起" : "展开 (\(players.count))")
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(theme.accentColor)
                    }.buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            
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
            .font(.system(size: 10)).foregroundColor(theme.textSecondary)
            .padding(.horizontal, 10).padding(.bottom, 6)
            
            Divider().background(theme.dividerColor)
            
            let displayPlayers = isExpanded ? players : Array(players.prefix(8))
            VStack(spacing: 0) {
                ForEach(displayPlayers.indices, id: \.self) { idx in
                    let p = displayPlayers[idx]
                    HStack(spacing: 0) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(p.onCourt ? theme.accentColor : Color.clear)
                                .frame(width: 5, height: 5)
                            Text(p.name).lineLimit(1)
                                .foregroundColor(p.onCourt ? theme.accentColor : (p.isStarter ? theme.textPrimary : theme.textSecondary))
                        }.frame(width: 100, alignment: .leading)

                        Text(formatPlayerTime(p.time)).frame(width: 44, alignment: .center).foregroundColor(theme.textSecondary)
                        Text("\(p.pts)").frame(width: 22, alignment: .center).foregroundColor(theme.accentColor).font(.system(size: 11, weight: .bold))
                        Text("\(p.reb)").frame(width: 22, alignment: .center)
                        Text("\(p.ast)").frame(width: 22, alignment: .center)
                        Text(p.fg).frame(width: 32, alignment: .center).foregroundColor(theme.textSecondary)
                        Text(p.threePt).frame(width: 32, alignment: .center).foregroundColor(theme.textSecondary)
                        Text(p.ft).frame(width: 32, alignment: .center).foregroundColor(theme.textSecondary)
                        
                        Text(p.plusMinus > 0 ? "+\(p.plusMinus)" : "\(p.plusMinus)")
                            .frame(width: 28, alignment: .trailing)
                            .foregroundColor(p.plusMinus > 0 ? theme.plusMinusPositive : (p.plusMinus < 0 ? theme.plusMinusNegative : theme.plusMinusNeutral))
                    }
                    .font(.system(size: 11))
                    .foregroundColor(theme.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(idx % 2 == 0 ? Color.clear : theme.listZebraStripe)
                }
            }
        }
        .background(theme.playerSectionBackground.cornerRadius(10))
    }
}
