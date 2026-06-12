import Foundation

// MARK: - 足球赛事数据模型
struct SoccerGame: Identifiable, Equatable {
    let id: String
    let status: String  // "pre", "in", "post"
    let time: String   // displayClock: "45'", "HT", "FT"
    let period: String // 半场标识 "1H", "2H", "HT", "FT"
    let homeTeam: SoccerTeam
    let awayTeam: SoccerTeam
    let competition: String  // 赛事名称，如 "FIFA World Cup"
    let leagueId: String    // 赛事ID，如 "fifa.world"
    // 扩展数据（用于详情悬浮窗）
    var venue: String?  // 场地
    var city: String?  // 城市
    var homeRecord: String?  // 主场近期战绩，如 "DDWWW"
    var awayRecord: String?  // 客场近期战绩，如 "LDLWL"
    var odds: SoccerOdds?  // 赔率信息
    var broadcasts: [String]?  // 转播信息
    var matchDate: String?  // 比赛日期时间（用于显示）
}

// MARK: - 足球赔率模型
struct SoccerOdds: Equatable {
    let bookmaker: String  // 博彩公司，如 "DraftKings"
    let overUnderLine: Double  // 大小球线，如 2.5
    let overOdds: Double  // 大球赔率
    let underOdds: Double  // 小球赔率
    let homeHandicap: Double  // 主队让球，如 -0.5
    let homeHandicapOdds: Double  // 主队让球赔率
    let awayHandicap: Double  // 客队受让
    let awayHandicapOdds: Double  // 客队受让赔率
    let homeMoneylineOdds: Double  // 主队胜赔率
    let awayMoneylineOdds: Double  // 客队胜赔率
    let drawMoneylineOdds: Double  // 平局赔率
}

// MARK: - 足球比赛详情数据模型
struct SoccerDetailData: Identifiable {
    let id: String
    let homeTeam: SoccerDetailTeam
    let awayTeam: SoccerDetailTeam
    let homeScore: Int
    let awayScore: Int
    let status: String  // "pre", "in", "post"
    let statusDetail: String  // "FT", "HT", "45'"
    let matchDate: String  // 比赛日期
    let league: String  // 联赛名称
    let venue: String?  // 场地
    let city: String?  // 城市
    let attendance: Int?  // 观众人数
    let broadcasts: [SoccerBroadcast]  // 转播信息
    let statistics: [SoccerTeamStatItem]  // 球队统计对比
    let keyEvents: [SoccerKeyEvent]  // 关键事件
    var homePenaltyScore: Int?  // 点球大战得分（如4）
    var awayPenaltyScore: Int?  // 点球大战得分（如3）
}

struct SoccerDetailTeam: Identifiable {
    let id: String
    let name: String
    let shortName: String
    let logo: String
    let formation: String?  // 阵型，如 "4-2-3-1"
    let players: [SoccerPlayerStat]  // 球员统计
}

struct SoccerPlayerStat: Identifiable {
    let id: String
    let name: String
    let position: String?  // 位置，如 "FW", "CB"
    let positionDisplayName: String?  // 位置显示名，如 "Center Forward"
    let formationPlace: String?  // 阵型中的编号（1-11）
    let number: Int?  // 球衣号
    let stats: [String: String]  // 个人统计项
    let isStarter: Bool  // 是否首发
    let isSubbedOut: Bool
    let isSubstituted: Bool
    let hasRedCard: Bool
    let hasYellowCard: Bool
    let hasGoal: Bool
    var originalDisplayName: String?  // 用于匹配 leaders 数据中的球员名
}

struct SoccerTeamStatItem: Identifiable {
    let id = UUID()
    let name: String  // 统计名称
    let label: String  // 显示名称
    let homeValue: String  // 主队值
    let awayValue: String  // 客队值
    let homeDisplay: String  // 主队显示值
    let awayDisplay: String  // 客队显示值
}

struct SoccerKeyEvent: Identifiable {
    let id: String
    let type: EventType  // "goal", "yellowCard", "redCard", "substitution"
    let team: String  // 球队全称
    let teamAbbr: String?  // 球队缩写（可能为空）
    let isHome: Bool  // 是否主队（创建时根据 team.id 标记,避免事后用中英文名匹配不可靠）
    let player: String  // 球员名称
    let minute: String?  // 时间，如 "45+2"
    let additionalInfo: String?  // 附加信息，如换人描述 "PlayerA replaces PlayerB"
}

enum EventType: String {
    case goal = "goal"
    case yellowCard = "yellowCard"
    case yellowcard = "yellowcard"
    case redCard = "redCard"
    case redcard = "redcard"
    case substitution = "substitution"
}

struct SoccerBroadcast: Identifiable {
    let id = UUID()
    let name: String  // 频道名称
    let type: String  // "TV" or "STREAMING"
}

// MARK: - ESPN Summary API 数据模型
struct SoccerSummaryResponse: Codable {
    let boxscore: SoccerSummaryBoxscore?
    let header: SoccerSummaryHeader?
    let gameInfo: [SoccerSummaryGameInfo]?
    let broadcasts: [SoccerSummaryBroadcast]?
    let keyEvents: [SoccerSummaryKeyEvent]?
    let format: SoccerSummaryFormat?
}

struct SoccerSummaryBoxscore: Codable {
    let teams: [SoccerSummaryTeam]?
}

struct SoccerSummaryTeam: Codable {
    let team: SoccerSummaryTeamInfo
    let homeAway: String
    let displayOrder: Int?
}

struct SoccerSummaryTeamInfo: Codable {
    let id: String
    let displayName: String
    let abbreviation: String
    let logo: String?
}

struct SoccerSummaryHeader: Codable {
    let competitions: [SoccerSummaryCompetition]?
}

struct SoccerSummaryCompetition: Codable {
    let id: String
    let date: String
    let status: SoccerSummaryStatus?
    let competitors: [SoccerSummaryCompetitor]?
    let notes: [SoccerSummaryNote]?
}

struct SoccerSummaryStatus: Codable {
    let type: SoccerSummaryStatusType
}

struct SoccerSummaryStatusType: Codable {
    let state: String
    let detail: String
}

struct SoccerSummaryCompetitor: Codable {
    let id: String
    let homeAway: String
    let team: SoccerSummaryTeamInfo
    let score: String?
}

struct SoccerSummaryNote: Codable {
    let type: String?
    let description: String?
}

struct SoccerSummaryGameInfo: Codable {
    let venue: SoccerSummaryVenue?
    let attendance: Int?
    let officials: [SoccerSummaryOfficial]?
}

struct SoccerSummaryVenue: Codable {
    let fullName: String?
    let address: SoccerSummaryAddress?
}

struct SoccerSummaryAddress: Codable {
    let city: String?
    let country: String?
}

struct SoccerSummaryOfficial: Codable {
    let fullName: String?
}

struct SoccerSummaryBroadcast: Codable {
    let media: SoccerSummaryMedia?
    let type: SoccerSummaryBroadcastType?
}

struct SoccerSummaryMedia: Codable {
    let shortName: String?
}

struct SoccerSummaryBroadcastType: Codable {
    let shortName: String?
}

struct SoccerSummaryKeyEvent: Codable {
    let id: String?
    let type: String?
    let team: SoccerSummaryEventTeam?
    let player: SoccerSummaryEventPlayer?
    let minute: String?
    let time: String?
    let text: String?
}

struct SoccerSummaryEventTeam: Codable {
    let id: String?
    let abbreviation: String?
}

struct SoccerSummaryEventPlayer: Codable {
    let fullName: String?
}

struct SoccerSummaryFormat: Codable {
    let regulation: SoccerSummaryRegulation?
}

struct SoccerSummaryRegulation: Codable {
    let periods: Int?
    let clock: Double?
}

struct SoccerTeam: Equatable {
    let id: String
    let name: String
    let shortName: String  // 如 "MEX", "RSA"
    let logo: String
    let countryCode: String  // 用于本地国旗加载，如 "MEX", "RSA"
    let score: String
    var shootoutScore: Int?  // 点球大战得分，如 4（当比赛进入点球大战时非nil）
}

// MARK: - 足球联赛枚举
enum SoccerLeague: String, CaseIterable {
    case fifaWorld = "fifa.world"
    case premierLeague = "eng.1"
    case laLiga = "esp.1"
    case serieA = "ita.1"
    case bundesliga = "ger.1"
    case championsLeague = "uefa.champions"

    var displayName: String {
        switch self {
        case .fifaWorld: return "世界杯"
        case .premierLeague: return "英超"
        case .laLiga: return "西甲"
        case .serieA: return "意甲"
        case .bundesliga: return "德甲"
        case .championsLeague: return "欧冠"
        }
    }

    var apiUrl: String {
        return "https://site.api.espn.com/apis/site/v2/sports/soccer/\(rawValue)/scoreboard"
    }
}

// MARK: - 足球联赛球队翻译（按联赛分组，避免冲突）
struct SoccerLeagueTeams {
    let leagueId: String
    let teams: [String: String]
}

// 全量球队翻译（按联赛分组）
let allSoccerLeagueTeams: [SoccerLeagueTeams] = [
    // 世界杯
    SoccerLeagueTeams(leagueId: "fifa.world", teams: [
        "MEX": "墨西哥", "RSA": "南非", "KOR": "韩国", "CZE": "捷克",
        "BRA": "巴西", "ARG": "阿根廷", "FRA": "法国", "GER": "德国",
        "ENG": "英格兰", "ESP": "西班牙", "ITA": "意大利", "POR": "葡萄牙",
        "NED": "荷兰", "BEL": "比利时", "CRO": "克罗地亚", "URU": "乌拉圭",
        "JPN": "日本", "AUS": "澳大利亚", "USA": "美国", "CAN": "加拿大"
    ]),
    // 英超
    SoccerLeagueTeams(leagueId: "eng.1", teams: [
        "ARS": "阿森纳", "AVL": "阿斯顿维拉", "BOU": "伯恩茅斯",
        "BRE": "布伦特福德", "BHA": "布莱顿", "BUR": "伯恩利",
        "CHE": "切尔西", "CRY": "水晶宫", "EVE": "埃弗顿",
        "FUL": "富勒姆", "IPS": "伊普斯维奇", "LEI": "莱斯特城",
        "LIV": "利物浦", "MCI": "曼城", "MAN": "曼联", "MUN": "曼联",
        "MNC": "诺丁汉森林", "NEW": "纽卡斯尔", "NFO": "诺丁汉森林",
        "SOU": "南安普顿", "SUN": "桑德兰", "TOT": "热刺",
        "WHU": "西汉姆联", "WOL": "狼队", "WHA": "西汉姆联"
    ]),
    // 西甲
    SoccerLeagueTeams(leagueId: "esp.1", teams: [
        "ALA": "阿拉维斯", "ATH": "毕尔巴鄂", "ATM": "马竞",
        "BAR": "巴萨", "BET": "贝蒂斯", "CEL": "塞尔塔",
        "GET": "赫塔费", "GIR": "赫罗纳", "GRA": "格拉纳达",
        "LAS": "拉斯帕尔马斯", "LEG": "莱加内斯", "LEV": "莱万特",
        "MLL": "马洛卡", "OSA": "奥萨苏纳", "OVI": "奥维耶多",
        "RAY": "巴列卡诺", "RSO": "皇家社会", "SEV": "塞维利亚",
        "ELC": "埃瓦尔", "ESP": "西班牙人", "VAL": "瓦伦西亚",
        "VIL": "比利亚雷亚尔", "RMA": "皇马", "ZAR": "萨拉戈萨"
    ]),
    // 意甲
    SoccerLeagueTeams(leagueId: "ita.1", teams: [
        "ACM": "AC米兰", "MIL": "AC米兰", "ATAL": "亚特兰大", "ATA": "亚特兰大",
        "BOL": "博洛尼亚", "CAG": "卡利亚里", "COM": "科莫",
        "EMP": "恩波利", "FIO": "佛罗伦萨", "GEN": "热那亚",
        "INTER": "国米", "INT": "国米", "JUV": "尤文", "JUVE": "尤文",
        "LAZ": "拉齐奥", "LEC": "莱切", "MON": "蒙扎",
        "NAP": "那不勒斯", "PAR": "帕尔马", "PARMA": "帕尔马",
        "ROM": "罗马", "TOR": "都灵", "UDI": "乌迪内斯",
        "VEN": "威尼斯", "VER": "维罗纳", "SAM": "桑普多利亚"
    ]),
    // 德甲
    SoccerLeagueTeams(leagueId: "ger.1", teams: [
        "FCB": "拜仁", "BAY": "拜仁", "BVB": "多特", "DOR": "多特", "RBL": "莱比锡",
        "B04": "勒沃库森", "LEV": "勒沃库森", "SGE": "法兰克福", "FRA": "法兰克福",
        "SCF": "弗赖堡", "BMG": "门兴", "BOC": "波鸿", "D98": "达姆施塔特",
        "HEI": "海登海姆", "HDH": "海登海姆", "HOF": "霍芬海姆", "TSG": "霍芬海姆",
        "KOL": "科隆", "KOE": "科隆", "M05": "美因茨", "S04": "沙尔克",
        "STU": "斯图加特", "VFB": "斯图加特", "STP": "圣保利",
        "UNL": "柏林联合", "FCU": "柏林联合", "FCA": "奥格斯堡", "AUG": "奥格斯堡",
        "WOB": "沃尔夫斯堡", "WOL": "沃尔夫斯堡", "SVW": "不莱梅", "HSV": "汉堡",
        "MGB": "门兴"
    ]),
    // 欧冠
    SoccerLeagueTeams(leagueId: "uefa.champions", teams: [
        "ARS": "阿森纳", "ATM": "马竞", "BAR": "巴萨",
        "BAY": "拜仁", "BEN": "本菲卡", "BVB": "多特", "DOR": "多特",
        "CHE": "切尔西", "INT": "国米", "JUV": "尤文", "JUVE": "尤文",
        "LIV": "利物浦", "MCI": "曼城", "MIL": "AC米兰", "ACM": "AC米兰",
        "NAP": "那不勒斯", "PAR": "巴黎圣日耳曼", "PGS": "巴黎圣日耳曼", "PSG": "巴黎圣日耳曼",
        "POR": "波尔图", "RMA": "皇马", "REA": "皇马",
        "RBL": "莱比锡", "ROM": "罗马", "SEV": "塞维利亚",
        "TOT": "热刺", "VAL": "瓦伦西亚", "VIL": "比利亚雷亚尔",
        "LEI": "莱斯特城"
    ])
]

// 全局球队翻译（无联赛信息时的fallback）
let globalSoccerTeamTranslation: [String: String] = [
    "MEX": "墨西哥", "RSA": "南非", "KOR": "韩国", "CZE": "捷克",
    "BRA": "巴西", "ARG": "阿根廷", "FRA": "法国", "GER": "德国",
    "ENG": "英格兰", "ESP": "西班牙", "ITA": "意大利", "POR": "葡萄牙",
    "NED": "荷兰", "BEL": "比利时", "CRO": "克罗地亚", "URU": "乌拉圭",
    "COL": "哥伦比亚", "JPN": "日本", "AUS": "澳大利亚", "USA": "美国",
    "CAN": "加拿大", "MAR": "摩洛哥", "SEN": "塞内加尔", "EGY": "埃及",
    "GHA": "加纳", "CMR": "喀麦隆", "NGA": "尼日利亚", "ALG": "阿尔及利亚",
    "TUN": "突尼斯", "IRN": "伊朗", "KSA": "沙特阿拉伯", "QAT": "卡塔尔",
    "UAE": "阿联酋", "NZL": "新西兰", "PAN": "巴拿马",
    "CRC": "哥斯达黎加", "HON": "洪都拉斯", "JAM": "牙买加", "CHI": "智利",
    "PAR": "巴拉圭", "BOL": "玻利维亚", "VEN": "委内瑞拉", "ECU": "厄瓜多尔",
    "POL": "波兰", "SUI": "瑞士", "SWE": "瑞典", "WAL": "威尔士",
    "AUT": "奥地利", "SCO": "苏格兰", "IRL": "爱尔兰", "NOR": "挪威",
    "DEN": "丹麦", "ISL": "冰岛", "SRB": "塞尔维亚", "UKR": "乌克兰",
    "TUR": "土耳其", "GRE": "希腊", "ROU": "罗马尼亚", "HUN": "匈牙利"
]

// 根据联赛和缩写字典查找球队名称
func soccerTeamTranslation(for league: SoccerLeague, abbreviation: String) -> String {
    if let leagueTeams = allSoccerLeagueTeams.first(where: { $0.leagueId == league.rawValue }),
       let name = leagueTeams.teams[abbreviation] {
        return name
    }
    // Fallback to global translation
    return globalSoccerTeamTranslation[abbreviation] ?? abbreviation
}

// MARK: - 足球统计字段翻译
let soccerStatTranslation: [String: String] = [
    "Possession": "控球率",
    "Shots": "射门",
    "Shots On Target": "射正",
    "Yellow Cards": "黄牌",
    "Corners": "角球",
    "Saves": "扑救",
    "Fouls": "犯规",
    "Offsides": "越位",
    "Red Cards": "红牌",
    "totalShots": "射门",
    "shotsOnTarget": "射正",
    "wonCorners": "角球",
    "yellowCards": "黄牌",
    "possessionPct": "控球率"
]

// MARK: - 足球事件类型翻译
let soccerEventTypeTranslation: [String: String] = [
    "goal": "进球",
    "yellowCard": "黄牌",
    "redCard": "红牌",
    "substitution": "换人"
]

// MARK: - 足球比赛状态翻译
let soccerStatusTranslation: [String: String] = [
    "post": "已结束",
    "in": "直播中",
    "pre": "未开始",
    "HT": "半场",
    "FT": "全场"
]

// MARK: - 球员名称翻译
var soccerPlayerTranslation: [String: String] = [:]

// MARK: - 全局置顶游戏管理器（统一足球和篮球的置顶逻辑）
class GlobalPinnedGameManager: ObservableObject {
    static let shared = GlobalPinnedGameManager()

    // 格式: "nba:gameId" 或 "soccer:gameId"
    private let pinnedGameKey = "GlobalPinnedGameId"

    @Published var pinnedGameId: String? {
        didSet {
            UserDefaults.standard.set(pinnedGameId, forKey: pinnedGameKey)
        }
    }

    // 缓存置顶的足球比赛（用于状态栏显示）
    @Published var cachedSoccerGame: SoccerGame?

    // 缓存置顶的NBA比赛
    @Published var cachedNBAGame: Game?

    // 返回sport前缀: "nba" 或 "soccer"
    var pinnedSport: String? {
        guard let id = pinnedGameId else { return nil }
        return String(id.split(separator: ":").first ?? "")
    }

    // 返回纯gameId（去掉sport前缀）
    var pinnedIdOnly: String? {
        guard let id = pinnedGameId else { return nil }
        if let colonIndex = id.firstIndex(of: ":") {
            return String(id[id.index(after: colonIndex)...])
        }
        return id
    }

    // 判断给定gameId是否为当前置顶
    func isPinned(gameId: String, sport: String) -> Bool {
        return pinnedGameId == "\(sport):\(gameId)"
    }

    // 切换置顶状态
    func togglePin(gameId: String, sport: String) {
        let fullId = "\(sport):\(gameId)"
        if pinnedGameId == fullId {
            pinnedGameId = nil
        } else {
            pinnedGameId = fullId
        }
    }

    private init() {
        self.pinnedGameId = UserDefaults.standard.string(forKey: pinnedGameKey)
    }
}

// MARK: - 页面活跃状态管理器（决定哪些数据需要轮询）
class SportModeManager: ObservableObject {
    static let shared = SportModeManager()

    @Published var activeSport: String = "nba" {
        didSet {
            print("🏐 [SportModeManager] activeSport changed to: \(activeSport)")
        }
    }

    // 检查指定运动是否应该刷新
    func shouldFetch(sport: String) -> Bool {
        return activeSport == sport && !AppDelegate.isInBackgroundMode
    }

    private init() {}
}

// MARK: - 足球球员翻译器
class SoccerPlayerTranslator {
    static let shared = SoccerPlayerTranslator()

    // 主翻译字典
    var dictionary: [String: String] = [:]

    // 自定义映射（用户配置）
    var customMapping: [String: String] = [:]

    // 特殊稀缺姓氏（难以匹配的球员）
    let uniqueFamilyNames: [String: String] = [
        "Odegaard": "厄德高",
        "De Bruyne": "德布劳内",
        "Gündogan": "京多安",
        "Sánchez": "桑切斯",
        "Thuram": "图拉姆",
        "Calhanoglu": "恰尔汗奥卢",
        "Barella": "巴雷拉",
        "Leão": "莱奥",
        "Vlahovic": "弗拉霍维奇",
        "Koopmeiners": "库普梅纳斯",
        "Schlotterbeck": "施洛特贝克",
        "Wirtz": "维尔茨",
        "Frimpong": "弗林蓬",
        "Sané": "萨内",
        "Musiala": "穆西亚拉",
        "Mats Hummels": "胡梅尔斯",
        "Hummels": "胡梅尔斯",
        "Goretzka": "格雷茨卡",
        "Kane": "凯恩",
        "Mbappé": "姆巴佩",
        "Vinícius": "小熊",
        "Bellingham": "贝林厄姆",
        "Valverde": "巴尔韦德",
        "Courtois": "库尔图瓦",
        "Ter Stegen": "特尔施特根",
        "De Jong": "德容",
        "Pedri": "佩德里",
        "Gavi": "加维",
        "Lewandowski": "莱万",
        "Olmo": "奥尔莫",
        "Raum": "劳姆",
        "Kimmich": "基米希",
        "Undav": "温达夫",
        "Demirovic": "德米罗维奇",
        "Pobega": "波贝加",
        "Sommer": "索默",
        "Maignan": "迈尼昂",
        "Reijnders": "赖因德斯",
        "Pulisic": "普利西奇",
        "Lukaku": "卢卡库",
        "Martínez": "马丁内斯",
        "Skriniar": "什克里尼亚尔",
        "Brozovic": "布罗佐维奇",
        "Caldara": "卡尔达拉",
        "Dalbert": "达尔伯特",
        "Felix": "菲利克斯",
        "João Félix": "若昂·菲利克斯",
        "Niguez": "尼格斯",
        "Saul": "索尔",
        "Lodi": "洛迪",
        "Reinier": "雷尼尔",
        "Eriksen": "埃里克森",
        "Fernandes": "费尔南德斯",
        "Bruno Fernandes": "B·费尔南德斯",
        "Casemiro": "卡塞米罗",
        "Varane": "瓦拉内",
        "Shaw": "肖",
        "Maguire": "马奎尔",
        "Dalot": "达洛特",
        "Onana": "奥纳纳",
        "Garnacho": "加纳乔",
        "Mount": "芒特",
        "Rashford": "拉什福德",
        "Haaland": "哈兰德",
        "Rodri": "罗德里",
        "Foden": "福登",
        "Silva": "席尔瓦",
        "Cancelo": "坎塞洛",
        "Walker": "沃克",
        "Stones": "斯通斯",
        "Dias": "迪亚斯",
        "Grealish": "格里利什",
        "Phillips": "菲利普斯",
        "Rice": "赖斯",
        "Saka": "萨卡",
        "Martinelli": "马丁内利",
        "Saliba": "萨利巴",
        "White": "怀特",
        "Zinchenko": "津琴科",
        "Ødegaard": "厄德高",
        "Partey": "帕蒂",
        "Jesus": "热苏斯",
        "Tomiyasu": "富安健洋",
        "Tierney": "蒂尔尼",
        "Smith Rowe": "史密斯·罗",
        "Trossard": "特罗萨德"
    ]

    private init() {}

    // 更新字典
    func updateDictionary(_ newDict: [String: String]) {
        dictionary.merge(newDict) { _, new in new }
    }

    // 更新自定义映射
    func updateCustomMapping(_ mapping: [String: String]) {
        customMapping.merge(mapping) { _, new in new }
    }

    // 翻译球员名称
    func translate(originalName: String, firstName: String, lastName: String) -> String {
        var translated = originalName

        // 1. 最高优先级：直接匹配 originalName
        if let t = dictionary[originalName] {
            translated = t
        }
        // 2. 检查自定义映射
        else if let t = customMapping[originalName] {
            translated = t
        }
        // 3. 检查特殊姓氏字典
        else if !lastName.isEmpty {
            // 尝试 lastName 全匹配
            if let t = uniqueFamilyNames[lastName] {
                translated = t
            } else {
                // 尝试 FirstName + LastName 组合
                let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                if let t = dictionary[fullName] {
                    translated = t
                } else if let t = customMapping[fullName] {
                    translated = t
                } else if let t = uniqueFamilyNames[fullName] {
                    translated = t
                }
            }
        }

        // 按照用户设置过滤：如果用户只想要 lastName 且翻译字符串包含 "·"，截取后半段
        let showFullName = UserDefaults.standard.bool(forKey: "showFullName")
        if !showFullName && translated.contains("·") {
            return String(translated.split(separator: "·").last ?? "")
        }

        return translated
    }
}

// MARK: - 位置名称翻译
let soccerPositionTranslation: [String: String] = [
    "Goalkeeper": "门将",
    "Center Forward": "中锋",
    "Forward": "前锋",
    "Left Wing": "左边锋",
    "Right Wing": "右边锋",
    "Attacking Midfielder": "前腰",
    "Center Midfielder": "中前卫",
    "Defensive Midfielder": "后腰",
    "Left Midfielder": "左边前卫",
    "Right Midfielder": "右边前卫",
    "Center Left Defender": "左中卫",
    "Center Right Defender": "右中卫",
    "Center Back": "中后卫",
    "Left Back": "左后卫",
    "Right Back": "右后卫",
    "Substitute": "替补"
]

// MARK: - ESPN API 数据模型
struct SoccerAPIResponse: Codable {
    let events: [SoccerAPIEvent]
}

struct SoccerAPIEvent: Codable {
    let id: String
    let uid: String
    let date: String
    let name: String
    let shortName: String
    let competitions: [SoccerAPICompetition]
    let status: SoccerAPIStatus
}

struct SoccerAPIStatus: Codable {
    let clock: Double
    let displayClock: String
    let type: SoccerAPIStatusType
}

struct SoccerAPIStatusType: Codable {
    let id: String
    let name: String
    let state: String
    let completed: Bool
    let description: String
    let detail: String
    let shortDetail: String
}

struct SoccerAPICompetition: Codable {
    let id: String
    let uid: String
    let date: String
    let competitors: [SoccerAPICompetitor]
    let venue: SoccerAPIVenue?
    let broadcasts: [SoccerAPIBroadcast]?
    let odds: [SoccerAPIOdds?]?  // Array elements can be null
}

struct SoccerAPIVenue: Codable {
    let fullName: String?
    let address: SoccerAPIAddress?
}

struct SoccerAPIAddress: Codable {
    let city: String?
    let country: String?
}

struct SoccerAPIBroadcast: Codable {
    let market: String?
    let names: [String]?
}

struct SoccerAPICompetitor: Codable {
    let id: String
    let uid: String
    let homeAway: String
    let team: SoccerAPITeam
    let score: String?
    let form: String?
    let shootoutScore: Int?  // 点球大战得分，如 4
}

struct SoccerAPIOdds: Codable {
    let overUnder: Double?
    let provider: SoccerAPIProvider?
    let drawOdds: SoccerAPIDrawOdds?
    let total: SoccerAPITotal?
    let pointSpread: SoccerAPIPointSpread?
    let moneyline: SoccerAPIMoneyline?
}

struct SoccerAPIProvider: Codable {
    let id: String?
    let name: String?
}

struct SoccerAPIDrawOdds: Codable {
    let moneyLine: Double?
}

struct SoccerAPITotal: Codable {
    let over: SoccerAPIOddsLine?
    let under: SoccerAPIOddsLine?
}

struct SoccerAPIOddsLine: Codable {
    let open: SoccerAPIOddsValue?
    let close: SoccerAPIOddsValue?
}

struct SoccerAPIOddsValue: Codable {
    let line: String?
    let odds: String?
}

struct SoccerAPIPointSpread: Codable {
    let home: SoccerAPIOddsLine?
    let away: SoccerAPIOddsLine?
}

struct SoccerAPIMoneyline: Codable {
    let home: SoccerAPIOddsLine?
    let away: SoccerAPIOddsLine?
    let draw: SoccerAPIOddsLine?
}

struct SoccerAPITeam: Codable {
    let id: String
    let uid: String
    let abbreviation: String
    let name: String
    let shortDisplayName: String
    let logo: String
}
