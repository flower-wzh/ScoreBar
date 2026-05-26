import Foundation
import Combine
import SwiftUI

let nbaTeamTranslation: [String: String] = [
    "ATL": "老鹰", "BOS": "凯尔特人", "BKN": "篮网", "CHA": "黄蜂", "CHI": "公牛",
    "CLE": "骑士", "DAL": "独行侠", "DEN": "掘金", "DET": "活塞", "GSW": "勇士",
    "HOU": "火箭", "IND": "步行者", "LAC": "快船", "LAL": "湖人", "MEM": "灰熊",
    "MIA": "热火", "MIL": "雄鹿", "MIN": "森林狼", "NOP": "鹈鹕", "NY": "尼克斯", "NYK": "尼克斯",
    "OKC": "雷霆", "ORL": "魔术", "PHI": "76人", "PHX": "太阳", "POR": "开拓者",
    "SAC": "国王", "SA": "马刺", "SAS": "马刺", "TOR": "猛龙", "UTA": "爵士", "WAS": "奇才"
]

// 扩展 UserDefaults 支持 KVO
extension UserDefaults {
    @objc dynamic var refreshInterval: Double {
        return double(forKey: "refreshInterval")
    }
}

class SportsViewModel: ObservableObject {
    @Published var games: [Game] = []
    @Published var isLoading = false

    // 共享全局置顶管理器（统一篮球和足球的置顶）
    private var globalPinned = GlobalPinnedGameManager.shared

    // 强制刷新标记，用于触发视图更新
    var pinnedGameId: String? {
        get { globalPinned.pinnedIdOnly }
        set {
            if let id = newValue {
                globalPinned.pinnedGameId = "nba:\(id)"
                // 缓存置顶的比赛
                if let game = games.first(where: { $0.id == id }) {
                    globalPinned.cachedNBAGame = game
                }
            } else {
                globalPinned.pinnedGameId = nil
                globalPinned.cachedNBAGame = nil
            }
            // 通知视图刷新
            objectWillChange.send()
        }
    }

    var currentRefreshInterval: Double {
        let val = UserDefaults.standard.double(forKey: "refreshInterval")
        return val > 0 ? val : 10.0
    }

    private var timer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    init() {
        print("✅ ViewModel 初始化启动！准备发起数据请求...")

        // 观察全局置顶管理器的变化，同步通知视图
        GlobalPinnedGameManager.shared.$pinnedGameId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        fetchGames()
        startPolling()

        UserDefaults.standard.publisher(for: \.refreshInterval)
            .sink { [weak self] _ in self?.startPolling() }
            .store(in: &cancellables)
    }

    func startPolling() {
        timer?.cancel()
        let interval = max(5.0, currentRefreshInterval) // 最小不能低于5秒
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
        // 只在NBA页面活跃时才请求
        if !SportModeManager.shared.shouldFetch(sport: "nba") {
            print("🔵 [SportsViewModel fetchGamesSafely] 跳过：NBA不是活跃页面")
            return
        }
        if AppDelegate.isInBackgroundMode {
            print("🔵 [SportsViewModel fetchGamesSafely] 跳过：后台静默模式")
            return
        }
        if isRequesting { return }
        isRequesting = true
        print("🔵 [SportsViewModel fetchGamesSafely] 开始请求NBA数据")
        fetchGames()
    }
    
    func fetchGames() {
        DispatchQueue.main.async { self.isLoading = true }

        // ESPN API endpoint
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard") else {
            isRequesting = false
            return
        }

        print("📡 [SportsViewModel fetchGames] Requesting ESPN scoreboard...")

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        // ESPN headers
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config)

        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                self.isRequesting = false
            }

            if let error = error {
                print("❌ [SportsViewModel fetchGames] network error: \(error.localizedDescription)")
                return
            }

            guard let data = data, error == nil else {
                print("❌ [SportsViewModel fetchGames] no data received")
                return
            }

            print("📦 [SportsViewModel fetchGames] received \(data.count) bytes")

            do {
                let decoder = JSONDecoder()
                let result = try decoder.decode(ESPNResponse.self, from: data)

                print("📊 [SportsViewModel fetchGames] events count: \(result.events.count)")
                for event in result.events {
                    print("   event.id=\(event.id) home=\(event.competitions.first?.competitors.first { $0.homeAway == "home" }?.team.abbreviation ?? "?") away=\(event.competitions.first?.competitors.first { $0.homeAway == "away" }?.team.abbreviation ?? "?")")
                }

                let parsedGames = result.events.map { event in
                    let competition = event.competitions.first!
                    let homeTeam = competition.competitors.first { $0.homeAway == "home" }!
                    let awayTeam = competition.competitors.first { $0.homeAway == "away" }!

                    // ESPN tricode mapping
                    let homeTri = homeTeam.team.abbreviation
                    let awayTri = awayTeam.team.abbreviation

                    let homeTeamName = nbaTeamTranslation[homeTri] ?? homeTri
                    let awayTeamName = nbaTeamTranslation[awayTri] ?? awayTri

                    // Status determination
                    let statusStr: String
                    switch event.status.type.state {
                    case "post": statusStr = "final"
                    case "pre": statusStr = "scheduled"
                    case "in": statusStr = "live"
                    default: statusStr = event.status.type.state
                    }

                    // Period
                    let period = event.status.period > 0 ? "Q\(event.status.period)" : ""

                    // Series wins/losses from venue detail if available
                    let homeSeriesWins = homeTeam.seriesWin
                    let homeSeriesLosses = homeTeam.seriesLoss
                    let awaySeriesWins = awayTeam.seriesWin
                    let awaySeriesLosses = awayTeam.seriesLoss

                    // Playoff series info
                    let isPlayoff = competition.series?.type == "playoff"
                    let seriesTotalGames = competition.series?.totalCompetitions

                    // Get series wins from series.competitors (more accurate than competitor.seriesWin)
                    var homeSeriesWinsFromSeries = homeSeriesWins
                    var awaySeriesWinsFromSeries = awaySeriesWins
                    if let seriesComps = competition.series?.competitors {
                        for sc in seriesComps {
                            if sc.id == homeTeam.team.id {
                                homeSeriesWinsFromSeries = sc.wins
                            } else if sc.id == awayTeam.team.id {
                                awaySeriesWinsFromSeries = sc.wins
                            }
                        }
                    }

                    return Game(
                        id: event.id,
                        status: statusStr,
                        time: event.status.displayClock.isEmpty ? event.date : event.status.displayClock,
                        period: period,
                        homeTeam: Team(id: homeTeam.team.id, name: homeTeamName, score: homeTeam.score ?? "0", logo: homeTeam.team.logo, tricode: homeTri, seriesWins: homeSeriesWinsFromSeries, seriesLosses: nil),
                        awayTeam: Team(id: awayTeam.team.id, name: awayTeamName, score: awayTeam.score ?? "0", logo: awayTeam.team.logo, tricode: awayTri, seriesWins: awaySeriesWinsFromSeries, seriesLosses: nil),
                        homeTeamSeriesWins: homeSeriesWinsFromSeries,
                        homeTeamSeriesLosses: nil,
                        awayTeamSeriesWins: awaySeriesWinsFromSeries,
                        awayTeamSeriesLosses: nil,
                        isPlayoff: isPlayoff,
                        seriesTotalGames: seriesTotalGames
                    )
                }

                DispatchQueue.main.async {
                    print("🎨 成功拿到了 \(parsedGames.count) 场 NBA 数据！")
                    self.games = parsedGames

                    // 更新缓存的置顶比赛
                    if self.globalPinned.pinnedSport == "nba",
                       let pinnedId = self.globalPinned.pinnedIdOnly,
                       let game = parsedGames.first(where: { $0.id == pinnedId }) {
                        self.globalPinned.cachedNBAGame = game
                    }
                }
            } catch {
                print("💥 JSON 解析失败: \(error)")
            }
        }.resume()
    }
}

// MARK: - App 实体定义
struct Game: Identifiable, Equatable {
    let id: String
    let status: String
    let time: String
    let period: String
    let homeTeam: Team
    let awayTeam: Team
    let homeTeamSeriesWins: Int?
    let homeTeamSeriesLosses: Int?
    let awayTeamSeriesWins: Int?
    let awayTeamSeriesLosses: Int?
    let isPlayoff: Bool
    let seriesTotalGames: Int?
}

struct Team: Equatable {
    let id: String
    let name: String
    let score: String
    let logo: String
    let tricode: String
    let seriesWins: Int?
    let seriesLosses: Int?
}

// MARK: - ESPN API 数据模型
struct ESPNResponse: Codable {
    let events: [ESPNEvent]
}

struct ESPNEvent: Codable {
    let id: String
    let date: String
    let status: ESPNStatus
    let competitions: [ESPNCompetition]
}

struct ESPNStatus: Codable {
    let period: Int
    let displayClock: String
    let type: ESPNStatusType
}

struct ESPNStatusType: Codable {
    let state: String
}

struct ESPNCompetition: Codable {
    let competitors: [ESPNCompetitor]
    let series: ESPNSeries?
}

struct ESPNSeries: Codable {
    let type: String
    let completed: Bool
    let totalCompetitions: Int
    let competitors: [ESPNSeriesCompetitor]
}

struct ESPNSeriesCompetitor: Codable {
    let id: String
    let wins: Int
}

struct ESPNCompetitor: Codable {
    let id: String
    let homeAway: String
    let team: ESPNTeam
    let score: String?
    let seriesWin: Int?
    let seriesLoss: Int?
}

struct ESPNTeam: Codable {
    let id: String
    let abbreviation: String
    let name: String
    let logo: String
}

// MARK: - 球员名字翻译器
class PlayerTranslator {
    static let shared = PlayerTranslator()
    
    // 全联盟核心与主力球员超大字典 (极致增强版，覆盖全联盟几乎所有轮换级别球员)
    var dictionary: [String: String] = [
        // 巨星与全明星
        "LeBron James": "詹姆斯", "Stephen Curry": "库里", "Kevin Durant": "杜兰特",
        "Nikola Jokic": "约基奇", "Luka Doncic": "东契奇", "Giannis Antetokounmpo": "字母哥",
        "Joel Embiid": "恩比德", "Jayson Tatum": "塔图姆", "Anthony Davis": "戴维斯",
        "Devin Booker": "布克", "Anthony Edwards": "华子/爱德华兹", "Shai Gilgeous-Alexander": "亚历山大",
        "Kyrie Irving": "欧文", "James Harden": "哈登", "Kawhi Leonard": "伦纳德",
        "Paul George": "乔治", "Damian Lillard": "利拉德", "Jimmy Butler": "巴特勒",
        "Victor Wembanyama": "文班亚马", "Jaylen Brown": "布朗", "Zion Williamson": "锡安",
        "Ja Morant": "莫兰特", "Donovan Mitchell": "米切尔", "De'Aaron Fox": "福克斯",
        "Domantas Sabonis": "萨博尼斯", "Tyrese Haliburton": "哈利伯顿", "Jalen Brunson": "布伦森",
        "Trae Young": "特雷杨", "Karl-Anthony Towns": "唐斯", "Klay Thompson": "汤普森",
        "Draymond Green": "追梦格林", "Russell Westbrook": "威少", "Chris Paul": "保罗",
        "Bam Adebayo": "阿德巴约", "Jamal Murray": "穆雷", "DeMar DeRozan": "德罗赞",
        "Bradley Beal": "比尔", "Pascal Siakam": "西亚卡姆", "Julius Randle": "兰德尔",
        "Rudy Gobert": "戈贝尔", "Paolo Banchero": "班切罗", "Chet Holmgren": "霍姆格伦",
        "Tyrese Maxey": "马克西", "Scottie Barnes": "巴恩斯", "Lauri Markkanen": "马尔卡宁",
        
        // 东西部各队主力与实力轮换 (按首字母或随机补充)
        "Aaron Gordon": "戈登", "Aaron Nesmith": "内史密斯", "Aaron Wiggins": "威金斯", "Al Horford": "霍福德", "Alec Burks": "伯克斯", "Aleksej Pokusevski": "波库舍夫斯基",
        "Alex Caruso": "卡鲁索", "Alperen Sengun": "申京", "Amen Thompson": "阿门", "Amir Coffey": "科菲", "Andre Drummond": "德拉蒙德", "Andre Jackson Jr.": "小杰克逊",
        "Andrew Wiggins": "维金斯", "Anfernee Simons": "西蒙斯", "Anthony Black": "布莱克", "Ausar Thompson": "奥萨尔", "Austin Reaves": "里夫斯", "Ayo Dosunmu": "多森姆",
        "Ben Sheppard": "谢泼德", "Bennedict Mathurin": "马瑟林", "Bilal Coulibaly": "库利巴利", "Blake Wesley": "韦斯利", "Boban Marjanovic": "博班", "Bobby Portis": "波蒂斯",
        "Bogdan Bogdanovic": "博格达", "Bojan Bogdanovic": "博扬", "Bol Bol": "波尔", "Bones Hyland": "海兰德", "Brandin Podziemski": "波杰姆斯基", "Brandon Ingram": "英格拉姆",
        "Brandon Miller": "米勒", "Brook Lopez": "大洛佩斯", "Bruce Brown": "布鲁斯布朗", "Buddy Hield": "希尔德", "Cade Cunningham": "坎宁安", "Caleb Houstan": "休斯坦",
        "Caleb Martin": "马丁", "Cam Reddish": "雷迪什", "Cam Thomas": "小托马斯", "Cam Whitmore": "惠特摩尔", "Cameron Johnson": "卡梅伦约翰逊", "Caris LeVert": "勒韦尔",
        "Cason Wallace": "华莱士", "Chris Boucher": "布歇", "Chris Duarte": "杜阿尔特", "Christian Braun": "布劳恩", "Christian Wood": "伍德",
        "Clint Capela": "卡佩拉", "Coby White": "科比怀特", "Cody Martin": "科迪马丁", "Cole Anthony": "科尔安东尼", "Collin Sexton": "塞克斯顿", "Corey Kispert": "基斯珀特",
        "Craig Porter Jr.": "小波特", "D'Angelo Russell": "拉塞尔", "Dalton Knecht": "克内克特", "Daniel Gafford": "加福德", "Daniel Theis": "泰斯", "Dante Exum": "埃克萨姆",
        "Dario Saric": "沙里奇", "Darius Garland": "加兰", "Davis Bertans": "贝尔坦斯", "Davion Mitchell": "米切尔", "Day'Ron Sharpe": "夏普", "De'Andre Hunter": "亨特",
        "DeAndre Jordan": "小乔丹", "Deandre Ayton": "艾顿", "Dean Wade": "韦德", "Deni Avdija": "阿夫迪亚", "Dennis Schroder": "施罗德",
        "Dereck Lively II": "莱夫利", "Derrick Jones Jr.": "小琼斯", "Derrick Rose": "罗斯", "Derrick White": "怀特", "Desmond Bane": "贝恩", "Devin Vassell": "瓦塞尔",
        "Dillon Brooks": "狄龙", "Donte DiVincenzo": "迪文琴佐", "Dorian Finney-Smith": "电风扇", "Drew Eubanks": "尤班克斯",
        "Duncan Robinson": "邓罗", "Dwight Powell": "鲍威尔", "Dyson Daniels": "丹尼尔斯", "Eric Gordon": "戈登/圆脸登", "Evan Fournier": "富尼耶", "Evan Mobley": "莫布里",
        "Franz Wagner": "小瓦格纳", "Fred VanVleet": "范弗利特", "Gabe Vincent": "文森特", "Garrison Mathews": "马修斯", "Gary Harris": "加里哈里斯", "Gary Payton II": "小佩顿",
        "Gary Trent Jr.": "小特伦特", "Georges Niang": "尼昂", "GG Jackson": "杰克逊", "Gradey Dick": "迪克", "Grant Williams": "格威", "Grayson Allen": "阿伦",
        "Gui Santos": "桑托斯", "Harrison Barnes": "巴恩斯", "Haywood Highsmith": "海史密斯", "Herbert Jones": "赫伯特琼斯", "Immanuel Quickley": "奎克利", "Isaac Okoro": "奥科罗",
        "Isaiah Hartenstein": "哈滕", "Isaiah Jackson": "杰克逊", "Isaiah Joe": "乔", "Isaiah Stewart": "斯图尔特", "Ivica Zubac": "祖巴茨", "JaVale McGee": "麦基",
        "Jabari Smith Jr.": "小史密斯", "Jaden Ivey": "艾维", "Jaden McDaniels": "麦克丹尼尔斯", "Jaden Springer": "斯普林格", "Jae'Sean Tate": "泰特", "Jaime Jaquez Jr.": "哈克斯",
        "Jakob Poeltl": "珀尔特尔", "Jalen Duren": "杜伦", "Jalen Green": "杰伦格林", "Jalen Johnson": "杰伦约翰逊", "Jalen Smith": "史密斯", "Jalen Suggs": "萨格斯",
        "Jalen Williams": "杰伦威廉姆斯", "James Wiseman": "怀斯曼", "Jaren Jackson Jr.": "小贾伦", "Jarrett Allen": "阿伦", "Jaylin Williams": "杰林", "Jeff Green": "姐夫/格林",
        "Jerami Grant": "格兰特", "Jericho Sims": "西姆斯", "Jeremy Sochan": "索汉", "Jevon Carter": "卡特", "Jock Landale": "兰代尔", "John Collins": "柯林斯",
        "Jonas Valanciunas": "瓦兰丘纳斯", "Jonathan Isaac": "艾萨克", "Jonathan Kuminga": "库明加", "Jordan Clarkson": "克拉克森", "Jordan McLaughlin": "麦克劳林", "Jordan Poole": "普尔",
        "Jose Alvarado": "老六/阿尔瓦拉多", "Josh Giddey": "吉迪", "Josh Green": "格林", "Josh Hart": "哈特", "Josh Okogie": "奥科吉", "Jrue Holiday": "霍勒迪",
        "Justin Holiday": "大霍勒迪", "Jusuf Nurkic": "努尔基奇", "Keegan Murray": "基根穆雷", "Keldon Johnson": "凯尔登",
        "Kelly Olynyk": "奥利尼克", "Kelly Oubre Jr.": "乌布雷", "Kenrich Williams": "肯里奇", "Kentavious Caldwell-Pope": "波普", "Keon Ellis": "埃利斯", "Kevin Huerter": "赫尔特",
        "Kevin Love": "乐福", "Kevon Looney": "卢尼", "Keyonte George": "乔治", "Khris Middleton": "米德尔顿", "Kristaps Porzingis": "波尔津吉斯",
        "Kyle Anderson": "李凯尔", "Kyle Kuzma": "库兹马", "Kyle Lowry": "洛瑞", "LaMelo Ball": "三球", "Larry Nance Jr.": "南斯",
        "Lonnie Walker IV": "朗尼沃克", "Luguentz Dort": "多尔特", "Luke Kennard": "肯纳德", "Luke Kornet": "科内特",
        "Malachi Flynn": "弗林", "Malaki Branham": "布兰纳姆", "Malcolm Brogdon": "布罗格登", "Malik Monk": "蒙克", "Marcus Sasser": "萨瑟", "Marcus Smart": "斯马特",
        "MarJon Beauchamp": "比彻姆", "Mark Williams": "马克威廉姆斯", "Markelle Fultz": "富尔茨", "Marvin Bagley III": "巴格利", "Mason Plumlee": "普拉姆利", "Max Christie": "克里斯蒂",
        "Max Strus": "斯特鲁斯", "Maxi Kleber": "克勒贝尔", "Michael Porter Jr.": "小波特", "Mikal Bridges": "大桥", "Miles Bridges": "小桥", "Miles McBride": "麦克布莱德",
        "Mitchell Robinson": "米罗", "Monte Morris": "莫里斯", "Moritz Wagner": "大瓦格纳", "Moses Moody": "穆迪", "Myles Turner": "特纳", "Naji Marshall": "马绍尔",
        "Naz Reid": "里德", "Neemias Queta": "克塔", "Nic Claxton": "克拉克斯顿", "Nickeil Alexander-Walker": "沃克", "Nicolas Batum": "巴图姆", "Nikola Jovic": "约维奇",
        "Norman Powell": "鲍威尔", "OG Anunoby": "阿努诺比", "Obi Toppin": "托平", "Onyeka Okongwu": "奥孔古", "P.J. Washington": "华盛顿", "PJ Tucker": "塔克",
        "Pat Connaughton": "康诺顿", "Patrick Williams": "帕威", "Paul Reed": "里德", "Payton Pritchard": "普理查德", "Peyton Watson": "沃特森",
        "Precious Achiuwa": "阿丘瓦", "RJ Barrett": "巴雷特", "Reggie Jackson": "雷吉", "Robert Covington": "考文顿", "Robert Williams III": "罗威", "Royce O'Neale": "奥尼尔",
        "Rui Hachimura": "八村塁", "Saddiq Bey": "贝", "Sam Hauser": "豪瑟", "Sam Merrill": "梅里尔", "Santi Aldama": "阿尔达马",
        "Sasha Vezenkov": "韦津科夫", "Scoot Henderson": "亨德森", "Shaedon Sharpe": "夏普", "Simone Fontecchio": "丰泰基奥",
        "Spencer Dinwiddie": "丁威迪", "T.J. McConnell": "麦康奈尔", "Tari Eason": "伊森", "Taurean Prince": "普林斯", "Taylor Hendricks": "亨德里克斯", "Terance Mann": "曼恩",
        "Tim Hardaway Jr.": "哈达威", "Tobias Harris": "哈里斯", "Torrey Craig": "克雷格", "Tre Jones": "琼斯", "Tre Mann": "曼恩",
        "Trayce Jackson-Davis": "TJD", "Trendon Watford": "沃特福德", "Trey Lyles": "莱尔斯", "Trey Murphy III": "墨菲",
        "Tyus Jones": "琼斯", "Vasilije Micic": "米西奇", "Vince Williams Jr.": "威廉姆斯", "Vit Krejci": "克雷伊奇", "Walker Kessler": "凯斯勒",
        "Wendell Carter Jr.": "温德尔卡特", "Xavier Tillman": "蒂尔曼", "Zach Collins": "柯林斯", "Zach Edey": "周志豪", "Zach LaVine": "拉文", "Zeke Nnaji": "纳吉"
    ]
    
    // 一些极其罕见且全联盟独享的姓氏，用于在 firstName 获取失败时强力命中
    let uniqueFamilyNames: [String: String] = [
        "Antetokounmpo": "字母哥", "Doncic": "东契奇", "Jokic": "约基奇", "Embiid": "恩比德",
        "Wembanyama": "文班亚马", "Durant": "杜兰特", "Curry": "库里", "Gobert": "戈贝尔",
        "Sengun": "申京", "Porzingis": "波尔津吉斯", "Gilgeous-Alexander": "亚历山大",
        "Haliburton": "哈利伯顿", "Brunson": "布伦森"
    ]
    
    private let defaultsKey = "CustomPlayerTranslations"
    
    init() {
        loadCustomMapping()
    }
    
    func updateCustomMapping(_ newMapping: [String: String]) {
        for (k, v) in newMapping {
            dictionary[k] = v
        }
        if let data = try? JSONEncoder().encode(newMapping) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
    
    func loadCustomMapping() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let custom = try? JSONDecoder().decode([String: String].self, from: data) {
            for (k, v) in custom {
                dictionary[k] = v
            }
        }
    }
    
    func translate(firstName: String, familyName: String, fallback: String) -> String {
        // 直接用 displayName 作为完整名字来查找翻译（字典 key 是 "Jarrett Allen" 格式）
        var translated = fallback

        // 1. 最高优先级：直接用 fallback（通常是 displayName）匹配字典
        if let matched = dictionary[fallback] {
            translated = matched
            print("✅ [PlayerTranslator] matched fallback '\(fallback)' -> '\(translated)'")
        } else if !familyName.isEmpty {
            // 2. 次高优先级：FirstName + LastName 全名匹配
            let fullName = "\(firstName) \(familyName)".trimmingCharacters(in: .whitespaces)
            if let matched = dictionary[fullName] {
                translated = matched
                print("✅ [PlayerTranslator] matched fullName '\(fullName)' -> '\(translated)'")
            } else if let matched = uniqueFamilyNames[familyName] {
                // 3. 特殊稀缺姓氏匹配
                translated = matched
                print("✅ [PlayerTranslator] matched uniqueFamilyNames '\(familyName)' -> '\(translated)'")
            }
        }

        // Debug logging
        if translated == fallback {
            print("⚠️ [PlayerTranslator] no translation for '\(fallback)', dictionary count=\(dictionary.count)")
        }

        let showFullName = UserDefaults.standard.bool(forKey: "showFullName")
        
        // 按照用户设置过滤：如果用户只想要单名 (LastName) 且翻译字符串是以“·”间隔的，截取后半段
        if !showFullName && translated.contains("·") {
            return String(translated.split(separator: "·").last ?? "")
        }
        
        return translated
    }
}

