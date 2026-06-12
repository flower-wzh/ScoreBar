import Foundation
import Combine
import SwiftUI

class SoccerViewModel: ObservableObject {
    @Published var games: [SoccerGame] = []
    @Published var isLoading = false

    // 共享全局置顶管理器（统一篮球和足球的置顶）
    private var globalPinned = GlobalPinnedGameManager.shared

    var pinnedGameId: String? {
        get { globalPinned.pinnedIdOnly }
        set {
            if let id = newValue {
                globalPinned.pinnedGameId = "soccer:\(id)"
                // 缓存置顶的比赛
                if let game = games.first(where: { $0.id == id }) {
                    globalPinned.cachedSoccerGame = game
                }
            } else {
                globalPinned.pinnedGameId = nil
                globalPinned.cachedSoccerGame = nil
            }
            // 通知视图刷新
            objectWillChange.send()
        }
    }

    @Published var currentLeague: SoccerLeague = .fifaWorld

    var currentRefreshInterval: Double {
        let val = UserDefaults.standard.double(forKey: "soccerRefreshInterval")
        return val > 0 ? val : 15.0
    }

    private var timer: AnyCancellable?

    private var cancellables = Set<AnyCancellable>()

    init() {
        print("⚽ [SoccerViewModel] 初始化启动...")

        // 观察全局置顶管理器的变化，同步通知视图
        GlobalPinnedGameManager.shared.$pinnedGameId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                // 更新缓存的比赛
                if let id = GlobalPinnedGameManager.shared.pinnedIdOnly,
                   GlobalPinnedGameManager.shared.pinnedSport == "soccer",
                   let game = self?.games.first(where: { $0.id == id }) {
                    GlobalPinnedGameManager.shared.cachedSoccerGame = game
                }
            }
            .store(in: &cancellables)

        fetchGames()
        startPolling()
    }

    func startPolling() {
        timer?.cancel()
        let interval = max(10.0, currentRefreshInterval)
        timer = Timer.publish(every: interval, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.fetchGamesSafely()
        }
    }

    func stopPolling() {
        timer?.cancel()
        timer = nil
    }

    private var isRequesting = false
    func fetchGamesSafely() {
        // 只在足球页面活跃时才请求
        if !SportModeManager.shared.shouldFetch(sport: "soccer") {
            print("⚽ [SoccerViewModel fetchGamesSafely] 跳过：足球不是活跃页面")
            return
        }
        if AppDelegate.isInBackgroundMode {
            print("⚽ [SoccerViewModel fetchGamesSafely] 跳过：后台静默模式")
            return
        }
        if isRequesting { return }
        isRequesting = true
        print("⚽ [SoccerViewModel fetchGamesSafely] 开始请求足球数据")
        fetchGames()
    }

    func switchLeague(_ league: SoccerLeague) {
        currentLeague = league
        fetchGames()
    }

    func fetchGames() {
        DispatchQueue.main.async { self.isLoading = true }

        guard let url = URL(string: currentLeague.apiUrl) else {
            isRequesting = false
            return
        }

        print("⚽ [SoccerViewModel fetchGames] Requesting \(currentLeague.displayName) scoreboard...")

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config)

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                self.isRequesting = false
            }

            if let error = error {
                print("❌ [SoccerViewModel fetchGames] network error: \(error.localizedDescription)")
                return
            }

            guard let data = data, error == nil else {
                print("❌ [SoccerViewModel fetchGames] no data received")
                return
            }

            do {
                let decoder = JSONDecoder()
                let result = try decoder.decode(SoccerAPIResponse.self, from: data)

                let parsedGames = result.events.map { [league = self.currentLeague] event in
                    let competition = event.competitions.first!
                    let homeTeam = competition.competitors.first { $0.homeAway == "home" }!
                    let awayTeam = competition.competitors.first { $0.homeAway == "away" }!

                    let homeShortName = homeTeam.team.abbreviation
                    let awayShortName = awayTeam.team.abbreviation

                    let homeTeamName = soccerTeamTranslation(for: league, abbreviation: homeShortName)
                    let awayTeamName = soccerTeamTranslation(for: league, abbreviation: awayShortName)

                    // Status determination
                    let statusStr: String
                    switch event.status.type.state {
                    case "post": statusStr = "final"
                    case "pre": statusStr = "scheduled"
                    case "in": statusStr = "live"
                    default: statusStr = event.status.type.state
                    }

                    // Period - convert displayClock to readable format
                    // ESPN 在半场 / 全场时 displayClock 仍停留在定格时刻 (45'+3' / 90'+8'),
                    // 真正的半场/全场标志是 status.type.detail ("HT" / "FT"),必须优先用它
                    let period = self.parseSoccerPeriod(
                        displayClock: event.status.displayClock,
                        state: event.status.type.state,
                        detail: event.status.type.detail
                    )
                    // time 字段在半场/全场/未开始时也要替换为人话,避免显示定格时刻 45'+3'
                    let timeText: String
                    if event.status.type.detail == "HT" {
                        timeText = "中场休息"
                    } else if event.status.type.state == "post" || event.status.type.detail == "FT" {
                        timeText = "已结束"
                    } else if event.status.type.state == "pre" {
                        timeText = event.status.displayClock
                    } else {
                        timeText = event.status.displayClock
                    }

                    // Parse match date - format the date for display
                    let matchDate = self.formatMatchDate(event.date)

                    // Parse venue and city
                    let venue = competition.venue?.fullName
                    let city = competition.venue?.address?.city

                    // Parse form (recent record)
                    let homeRecord = homeTeam.form
                    let awayRecord = awayTeam.form

                    // Parse broadcasts
                    let broadcasts = competition.broadcasts?.first?.names

                    // Parse odds
                    var odds: SoccerOdds? = nil
                    if let oddsArray = competition.odds, let firstOdds = oddsArray.first, let validOdds = firstOdds {
                        odds = self.parseOdds(validOdds)
                    }

                    return SoccerGame(
                        id: event.id,
                        status: statusStr,
                        time: timeText,
                        period: period,
                        homeTeam: SoccerTeam(
                            id: homeTeam.team.id,
                            name: homeTeamName,
                            shortName: homeShortName,
                            logo: homeTeam.team.logo,
                            countryCode: homeShortName,
                            score: homeTeam.score ?? "0",
                            shootoutScore: homeTeam.shootoutScore
                        ),
                        awayTeam: SoccerTeam(
                            id: awayTeam.team.id,
                            name: awayTeamName,
                            shortName: awayShortName,
                            logo: awayTeam.team.logo,
                            countryCode: awayShortName,
                            score: awayTeam.score ?? "0",
                            shootoutScore: awayTeam.shootoutScore
                        ),
                        competition: self.currentLeague.displayName,
                        leagueId: self.currentLeague.rawValue,
                        venue: venue,
                        city: city,
                        homeRecord: homeRecord,
                        awayRecord: awayRecord,
                        odds: odds,
                        broadcasts: broadcasts,
                        matchDate: matchDate
                    )
                }

                DispatchQueue.main.async {
                    self.games = parsedGames

                    // 更新缓存的置顶比赛
                    if GlobalPinnedGameManager.shared.pinnedSport == "soccer",
                       let pinnedId = GlobalPinnedGameManager.shared.pinnedIdOnly,
                       let game = parsedGames.first(where: { $0.id == pinnedId }) {
                        GlobalPinnedGameManager.shared.cachedSoccerGame = game
                    }
                }
            } catch {
                print("💥 [SoccerViewModel] JSON 解析失败: \(error)")
            }
        }.resume()
    }

    private func parseSoccerPeriod(displayClock: String, state: String, detail: String) -> String {
        // 半场/全场标志来自 status.type.detail (ESPN 在这些时刻 displayClock 仍是定格分钟数,如 45'+3' / 90'+8')
        if detail == "HT" { return "半场" }
        if state == "post" || detail == "FT" { return "全场" }
        if displayClock.hasSuffix("'") {
            // 从 "45'+3'" 提取基础分钟数 45;处理补时格式
            let base = displayClock.replacingOccurrences(of: "'", with: "")
            let numericPrefix = base.prefix { $0.isNumber }
            if let min = Int(numericPrefix) {
                if min <= 45 { return "上半场" }
                else { return "下半场" }
            }
        }
        return displayClock
    }

    private func parseOdds(_ oddsData: SoccerAPIOdds) -> SoccerOdds {
        let providerName = oddsData.provider?.name ?? "DraftKings"
        let overUnder = oddsData.overUnder ?? 2.5

        let overOdds = self.parseDouble(oddsData.total?.over?.close?.odds)
        let underOdds = self.parseDouble(oddsData.total?.under?.close?.odds)

        let homeHandicap = self.parseDouble(oddsData.pointSpread?.home?.close?.line)
        let homeHandicapOdds = self.parseDouble(oddsData.pointSpread?.home?.close?.odds)
        let awayHandicap = self.parseDouble(oddsData.pointSpread?.away?.close?.line)
        let awayHandicapOdds = self.parseDouble(oddsData.pointSpread?.away?.close?.odds)

        let homeMoneylineOdds = self.parseDouble(oddsData.moneyline?.home?.close?.odds)
        let awayMoneylineOdds = self.parseDouble(oddsData.moneyline?.away?.close?.odds)
        let drawMoneylineOdds = oddsData.drawOdds?.moneyLine ?? 0

        return SoccerOdds(
            bookmaker: providerName,
            overUnderLine: overUnder,
            overOdds: overOdds,
            underOdds: underOdds,
            homeHandicap: homeHandicap,
            homeHandicapOdds: homeHandicapOdds,
            awayHandicap: awayHandicap,
            awayHandicapOdds: awayHandicapOdds,
            homeMoneylineOdds: homeMoneylineOdds,
            awayMoneylineOdds: awayMoneylineOdds,
            drawMoneylineOdds: drawMoneylineOdds
        )
    }

    private func parseDouble(_ string: String?) -> Double {
        guard let str = string else { return 0 }
        return Double(str) ?? 0
    }

    private func formatMatchDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            // 北京时间 (UTC+8)
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "yyyy-MM-dd HH:mm E"
            displayFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            displayFormatter.locale = Locale(identifier: "zh_CN")
            return displayFormatter.string(from: date)
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "yyyy-MM-dd HH:mm E"
            displayFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            displayFormatter.locale = Locale(identifier: "zh_CN")
            return displayFormatter.string(from: date)
        }
        return dateString
    }

    func fetchSoccerGameDetail(eventId: String, league: SoccerLeague, completion: @escaping (SoccerDetailData?) -> Void) {
        let urlString = "https://site.api.espn.com/apis/site/v2/sports/soccer/\(league.rawValue)/summary?event=\(eventId)"
        print("⚽ [SoccerViewModel fetchSoccerGameDetail] eventId=\(eventId), url=\(urlString)")

        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ [fetchSoccerGameDetail] network error: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let data = data else {
                print("❌ [fetchSoccerGameDetail] no data received")
                completion(nil)
                return
            }

            print("📦 [fetchSoccerGameDetail] received \(data.count) bytes")

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("❌ [fetchSoccerGameDetail] failed to parse JSON")
                    completion(nil)
                    return
                }

                let detail = self.parseSoccerDetailData(json: json, eventId: eventId, league: league)
                DispatchQueue.main.async {
                    completion(detail)
                }
            } catch {
                print("💥 [fetchSoccerGameDetail] JSON parsing failed: \(error)")
                completion(nil)
            }
        }.resume()
    }

    private func parseSoccerDetailData(json: [String: Any], eventId: String, league: SoccerLeague) -> SoccerDetailData? {
        // Parse header
        let header = json["header"] as? [String: Any]
        let competitions = header?["competitions"] as? [[String: Any]]
        let competition = competitions?.first

        let statusType = competition?["status"] as? [String: Any]
        let typeInfo = statusType?["type"] as? [String: Any]
        let statusState = typeInfo?["state"] as? String ?? "unknown"
        let statusDetail = typeInfo?["detail"] as? String ?? ""

        let competitors = competition?["competitors"] as? [[String: Any]]
        let homeCompetitor = competitors?.first { ($0["homeAway"] as? String) == "home" }
        let awayCompetitor = competitors?.first { ($0["homeAway"] as? String) == "away" }

        let homeTeamInfo = homeCompetitor?["team"] as? [String: Any]
        let awayTeamInfo = awayCompetitor?["team"] as? [String: Any]

        let homeTeam = SoccerDetailTeam(
            id: homeTeamInfo?["id"] as? String ?? "",
            name: soccerTeamTranslation(for: league, abbreviation: homeTeamInfo?["abbreviation"] as? String ?? ""),
            shortName: homeTeamInfo?["abbreviation"] as? String ?? "",
            logo: homeTeamInfo?["logo"] as? String ?? "",
            formation: nil,
            players: []
        )

        let awayTeam = SoccerDetailTeam(
            id: awayTeamInfo?["id"] as? String ?? "",
            name: soccerTeamTranslation(for: league, abbreviation: awayTeamInfo?["abbreviation"] as? String ?? ""),
            shortName: awayTeamInfo?["abbreviation"] as? String ?? "",
            logo: awayTeamInfo?["logo"] as? String ?? "",
            formation: nil,
            players: []
        )

        let homeScore = Int(homeCompetitor?["score"] as? String ?? "0") ?? 0
        let awayScore = Int(awayCompetitor?["score"] as? String ?? "0") ?? 0

        // Parse penalty shootout scores
        let homePenaltyScore: Int? = (homeCompetitor?["shootoutScore"] as? NSNumber)?.intValue
        let awayPenaltyScore: Int? = (awayCompetitor?["shootoutScore"] as? NSNumber)?.intValue

        // Parse match date
        let matchDateStr = competition?["date"] as? String ?? ""
        let matchDate = formatMatchDate(matchDateStr)

        // Parse league
        let league = header?["league"] as? [String: Any]
        let leagueName = league?["displayName"] as? String ?? ""

        // Parse gameInfo
        let gameInfo = json["gameInfo"] as? [[String: Any]]
        let venueInfo = gameInfo?.first?["venue"] as? [String: Any]
        let venueAddress = venueInfo?["address"] as? [String: Any]
        let venue = venueInfo?["fullName"] as? String
        let city = venueAddress?["city"] as? String
        let attendance = gameInfo?.first?["attendance"] as? Int

        // Parse broadcasts
        let broadcastsJson = json["broadcasts"] as? [[String: Any]] ?? []
        let broadcasts = broadcastsJson.compactMap { bc -> SoccerBroadcast? in
            let media = bc["media"] as? [String: Any]
            let type = bc["type"] as? [String: Any]
            return SoccerBroadcast(
                name: media?["shortName"] as? String ?? "",
                type: type?["shortName"] as? String ?? ""
            )
        }

        // Parse statistics from boxscore
        var statistics: [SoccerTeamStatItem] = []
        if let boxscore = json["boxscore"] as? [String: Any],
           let teams = boxscore["teams"] as? [[String: Any]] {
            let homeTeamStats = teams.first { ($0["homeAway"] as? String) == "home" }?["statistics"] as? [[String: Any]] ?? []
            let awayTeamStats = teams.first { ($0["homeAway"] as? String) == "away" }?["statistics"] as? [[String: Any]] ?? []

            // Key stats to display (matching image layout): Possession, Shots on Goal, Shots, Yellow Cards, Corners, Saves
            let keyStats = ["possessionPct", "shotsOnTarget", "totalShots", "yellowCards", "wonCorners", "saves"]
            let statLabels = ["Possession", "Shots On Goal", "Shots", "Yellow Cards", "Corner Kicks", "Saves"]

            for (i, statName) in keyStats.enumerated() {
                let homeStat = homeTeamStats.first { ($0["name"] as? String) == statName }
                let awayStat = awayTeamStats.first { ($0["name"] as? String) == statName }

                let statItem = SoccerTeamStatItem(
                    name: statName,
                    label: statLabels[i],
                    homeValue: homeStat?["displayValue"] as? String ?? "-",
                    awayValue: awayStat?["displayValue"] as? String ?? "-",
                    homeDisplay: homeStat?["displayValue"] as? String ?? "-",
                    awayDisplay: awayStat?["displayValue"] as? String ?? "-"
                )
                statistics.append(statItem)
            }
        }

        // Parse key events
        var keyEvents: [SoccerKeyEvent] = []
        if let events = json["keyEvents"] as? [[String: Any]] {
            for event in events {
                let typeInfo = event["type"] as? [String: Any]
                let typeRaw = typeInfo?["type"] as? String ?? ""
                // 统一转为小写，并处理各种变体
                let type = typeRaw.lowercased()

                // 判断是否是事件类型（goal, yellow card, red card, substitution）
                // 包含 goal（可能有后缀如 goal---header）、penalty---scored、yellowcard/yellow-card、redcard/red-card、substitution
                let isGoal = type.contains("goal")
                let isPenalty = type.contains("penalty")
                let isYellowCard = type.contains("yellow") && type.contains("card")
                let isRedCard = type.contains("red") && type.contains("card")
                let isSubstitution = type.contains("substitution")

                if isGoal || isPenalty || isYellowCard || isRedCard || isSubstitution {
                    let teamInfo = event["team"] as? [String: Any]
                    let clockInfo = event["clock"] as? [String: Any]
                    let participants = event["participants"] as? [[String: Any]]

                    // 换人事件有2个参与者：participants[0]=换上球员, participants[1]=被换下球员
                    // 其他事件只有1个参与者
                    var playerName = ""
                    var additionalInfoText: String? = nil

                    if isSubstitution {
                        let athleteIn = participants?.first?["athlete"] as? [String: Any]
                        playerName = athleteIn?["displayName"] as? String ?? ""
                        // additionalInfo 存储完整的换人描述，如 "Jurriën Timber replaces Cristhian Mosquera"
                        additionalInfoText = event["text"] as? String
                    } else {
                        let athleteInfo = participants?.first?["athlete"] as? [String: Any]
                        playerName = athleteInfo?["displayName"] as? String ?? ""
                        additionalInfoText = typeInfo?["text"] as? String
                    }

                    // 确定事件类型枚举
                    let eventType: EventType
                    if isGoal || isPenalty {
                        eventType = .goal
                    } else if isYellowCard {
                        eventType = .yellowCard
                    } else if isRedCard {
                        eventType = .redCard
                    } else {
                        eventType = .substitution
                    }

                    // 对于换人事件，player 字段存储换上球员，additionalInfo 存储完整描述
                    let eventTeamId = teamInfo?["id"] as? String
                    let isHome = eventTeamId == homeTeam.id
                    let keyEvent = SoccerKeyEvent(
                        id: event["id"] as? String ?? UUID().uuidString,
                        type: eventType,
                        team: teamInfo?["displayName"] as? String ?? "",
                        teamAbbr: teamInfo?["abbreviation"] as? String,
                        isHome: isHome,
                        player: playerName,
                        minute: clockInfo?["displayValue"] as? String,
                        additionalInfo: additionalInfoText
                    )
                    keyEvents.append(keyEvent)
                }
            }
        }

        // Parse rosters (formation and players)
        let rosters = json["rosters"] as? [[String: Any]] ?? []

        // Parse passing leaders from leaders section
        var homePassingLeaders: [String: String] = [:]  // playerName -> passes
        var awayPassingLeaders: [String: String] = [:]
        if let leadersData = json["leaders"] as? [[String: Any]] {
            for leader in leadersData {
                let homeAway = leader["homeAway"] as? String
                let teamLeaders = leader["leaders"] as? [[String: Any]] ?? []
                for category in teamLeaders {
                    let catName = category["name"] as? String ?? ""
                    if catName == "Accurate Passes" {
                        for player in category["leaders"] as? [[String: Any]] ?? [] {
                            let athlete = player["athlete"] as? [String: Any] ?? [:]
                            let playerName = athlete["displayName"] as? String ?? ""
                            let displayValue = player["displayValue"] as? String ?? ""
                            if homeAway == "home" {
                                homePassingLeaders[playerName] = displayValue
                            } else {
                                awayPassingLeaders[playerName] = displayValue
                            }
                        }
                    }
                }
            }
        }

        // Parse home team roster
        var homeFormation: String? = nil
        var homePlayers: [SoccerPlayerStat] = []
        if let homeRoster = rosters.first(where: { ($0["homeAway"] as? String) == "home" }) {
            homeFormation = homeRoster["formation"] as? String
            homePlayers = parsePlayers(from: homeRoster["roster"] as? [[String: Any]] ?? [])
        }

        // Parse away team roster
        var awayFormation: String? = nil
        var awayPlayers: [SoccerPlayerStat] = []
        if let awayRoster = rosters.first(where: { ($0["homeAway"] as? String) == "away" }) {
            awayFormation = awayRoster["formation"] as? String
            awayPlayers = parsePlayers(from: awayRoster["roster"] as? [[String: Any]] ?? [])
        }

        // Inject passing data into player stats
        homePlayers = homePlayers.map { player in
            var updatedStats = player.stats
            if let passes = homePassingLeaders[player.originalDisplayName ?? player.name] {
                updatedStats["accuratePasses"] = passes
            }
            return SoccerPlayerStat(
                id: player.id,
                name: player.name,
                position: player.position,
                positionDisplayName: player.positionDisplayName,
                formationPlace: player.formationPlace,
                number: player.number,
                stats: updatedStats,
                isStarter: player.isStarter,
                isSubbedOut: player.isSubbedOut,
                isSubstituted: player.isSubstituted,
                hasRedCard: player.hasRedCard,
                hasYellowCard: player.hasYellowCard,
                hasGoal: player.hasGoal,
                originalDisplayName: player.originalDisplayName
            )
        }

        awayPlayers = awayPlayers.map { player in
            var updatedStats = player.stats
            if let passes = awayPassingLeaders[player.originalDisplayName ?? player.name] {
                updatedStats["accuratePasses"] = passes
            }
            return SoccerPlayerStat(
                id: player.id,
                name: player.name,
                position: player.position,
                positionDisplayName: player.positionDisplayName,
                formationPlace: player.formationPlace,
                number: player.number,
                stats: updatedStats,
                isStarter: player.isStarter,
                isSubbedOut: player.isSubbedOut,
                isSubstituted: player.isSubstituted,
                hasRedCard: player.hasRedCard,
                hasYellowCard: player.hasYellowCard,
                hasGoal: player.hasGoal,
                originalDisplayName: player.originalDisplayName
            )
        }

        // Update teams with formation and players
        let updatedHomeTeam = SoccerDetailTeam(
            id: homeTeam.id,
            name: homeTeam.name,
            shortName: homeTeam.shortName,
            logo: homeTeam.logo,
            formation: homeFormation,
            players: homePlayers
        )

        let updatedAwayTeam = SoccerDetailTeam(
            id: awayTeam.id,
            name: awayTeam.name,
            shortName: awayTeam.shortName,
            logo: awayTeam.logo,
            formation: awayFormation,
            players: awayPlayers
        )

        return SoccerDetailData(
            id: eventId,
            homeTeam: updatedHomeTeam,
            awayTeam: updatedAwayTeam,
            homeScore: homeScore,
            awayScore: awayScore,
            status: statusState,
            statusDetail: statusDetail,
            matchDate: matchDate,
            league: leagueName,
            venue: venue,
            city: city,
            attendance: attendance,
            broadcasts: broadcasts,
            statistics: statistics,
            keyEvents: keyEvents,
            homePenaltyScore: homePenaltyScore,
            awayPenaltyScore: awayPenaltyScore
        )
    }

    // MARK: - Helper Methods

    // 根据设置决定球员名称显示
    private func displayName(for originalName: String, displayName: String, lastName: String, firstName: String) -> String {
        return SoccerPlayerTranslator.shared.translate(
            originalName: originalName,
            firstName: firstName,
            lastName: lastName
        )
    }

    private func parsePlayers(from rosterArray: [[String: Any]]) -> [SoccerPlayerStat] {
        return rosterArray.compactMap { playerJson -> SoccerPlayerStat? in
            // Player data is nested inside "athlete" object
            let athlete = playerJson["athlete"] as? [String: Any] ?? playerJson
            let id = athlete["id"] as? String ?? UUID().uuidString
            let firstName = athlete["firstName"] as? String ?? ""
            let lastName = athlete["lastName"] as? String ?? ""
            let originalDisplayName = athlete["displayName"] as? String ?? "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            let position = playerJson["position"] as? [String: Any]
            let positionName = position?["name"] as? String
            let positionDisplayName = position?["displayName"] as? String
            let formationPlace = playerJson["formationPlace"] as? String
            let jersey = playerJson["jersey"] as? String
            let starter = playerJson["starter"] as? Bool ?? false

            // Parse stats
            var playerStats: [String: String] = [:]
            var hasGoal = false
            var hasYellowCard = false
            var hasRedCard = false

            if let statsArray = playerJson["stats"] as? [[String: Any]] {
                for stat in statsArray {
                    if let name = stat["name"] as? String, let displayValue = stat["displayValue"] as? String {
                        playerStats[name] = displayValue

                        // Check for special events
                        if name == "totalGoals", (stat["value"] as? Int ?? 0) > 0 {
                            hasGoal = true
                        }
                        if name == "yellowCards", (stat["value"] as? Int ?? 0) > 0 {
                            hasYellowCard = true
                        }
                        if name == "redCards", (stat["value"] as? Int ?? 0) > 0 {
                            hasRedCard = true
                        }
                    }
                }
            }

            // Determine substitution status
            let isSubbedOut = playerStats["substituted"] == "true" || playerStats["substituted"] == "1"
            let isSubstituted = playerStats["substituted"] == "true" || playerStats["substituted"] == "1"

            let finalName = displayName(for: originalDisplayName, displayName: originalDisplayName, lastName: lastName, firstName: firstName)

            return SoccerPlayerStat(
                id: id,
                name: finalName,
                position: positionName,
                positionDisplayName: positionDisplayName,
                formationPlace: formationPlace,
                number: Int(jersey ?? ""),
                stats: playerStats,
                isStarter: starter,
                isSubbedOut: isSubbedOut,
                isSubstituted: isSubstituted,
                hasRedCard: hasRedCard,
                hasYellowCard: hasYellowCard,
                hasGoal: hasGoal,
                originalDisplayName: originalDisplayName
            )
        }
    }
}
