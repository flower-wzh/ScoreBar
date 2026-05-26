import Foundation

// MARK: - 球员贡献评分计算器
struct PlayerRatingCalculator {

    // MARK: - 位置分类
    enum PositionCategory {
        case goalkeeper
        case defender
        case midfielder
        case forward
        case unknown
    }

    // MARK: - 球员评分结果
    struct PlayerRating: Identifiable {
        let id: String
        let name: String
        let positionDisplayName: String?
        let category: PositionCategory
        let totalScore: Double
        let details: [String: Any]
        let player: SoccerPlayerStat  // 原始球员数据，用于UI展示
    }

    // MARK: - 根据 positionDisplayName 判断位置分类
    static func categorizePosition(_ positionDisplayName: String?) -> PositionCategory {
        let name = positionDisplayName ?? ""

        if name.contains("Goalkeeper") {
            return .goalkeeper
        }
        if name.contains("Defender") || name.contains("Back") || name.contains("Wing Back") {
            return .defender
        }
        if name.contains("Midfielder") {
            return .midfielder
        }
        if name.contains("Forward") || name.contains("Striker") || name.contains("Winger") {
            return .forward
        }
        return .unknown
    }

    // MARK: - 安全获取 Double 值
    static func getDouble(_ stats: [String: String], key: String) -> Double {
        guard let str = stats[key], let value = Double(str) else { return 0.0 }
        return value
    }

    // MARK: - 计算单个球员评分
    static func calculateRating(for player: SoccerPlayerStat) -> PlayerRating {
        var score: Double = 6.0  // 基础分
        let stats = player.stats
        let category = categorizePosition(player.positionDisplayName)
        var details: [String: Any] = [:]

        // === 通用项 ===
        let yellowCards = getDouble(stats, key: "yellowCards")
        let redCards = getDouble(stats, key: "redCards")
        // 犯规通用项取消（不在通用项中扣）
        let subIns = getDouble(stats, key: "subIns") > 0  // 替补上场

        score += yellowCards * (-1.5)  // 黄牌 -1.5
        score += redCards * (-3.0)      // 红牌 -3.0

        // 替补上场惩罚
        if subIns {
            score += (-0.5)
            details["替补惩罚"] = -0.5
        }

        details["黄牌"] = yellowCards
        details["红牌"] = redCards

        // === 按位置计算 ===
        switch category {
        case .goalkeeper:
            let saves = getDouble(stats, key: "saves")
            let goalsConceded = getDouble(stats, key: "goalsConceded")
            let shotsFaced = getDouble(stats, key: "shotsFaced")

            score += saves * 0.8          // 扑救 +0.8/次
            score += goalsConceded * (-0.8) // 丢球 -0.8/球

            // 零封奖励
            if goalsConceded == 0 {
                score += 3.0
                details["零封"] = 3.0
            }

            // 扑救率 > 70% 奖励
            if shotsFaced > 0 && saves / shotsFaced > 0.7 {
                score += 1.0
                details["扑救率奖励"] = 1.0
            }

            details["扑救"] = saves
            details["丢球"] = goalsConceded

        case .defender:
            let goals = getDouble(stats, key: "totalGoals")
            let assists = getDouble(stats, key: "goalAssists")
            let shotsOnTarget = getDouble(stats, key: "shotsOnTarget")
            let totalShots = getDouble(stats, key: "totalShots")
            let offsides = getDouble(stats, key: "offsides")
            let accuratePasses = getDouble(stats, key: "accuratePasses")

            score += goals * 5.0      // 进球 +5.0
            score += assists * 3.0    // 助攻 +3.0
            score += shotsOnTarget * 0.5  // 射正 +0.5
            score += totalShots * 0.2     // 射门 +0.2
            score += offsides * (-0.5)     // 越位 -0.5
            score += accuratePasses * 0.05 // 传球成功 +0.05/次（权重较小）

            // 射门得分率 > 50%
            if totalShots > 0 && shotsOnTarget / totalShots > 0.5 {
                score += 1.0
                details["射门得分率奖励"] = 1.0
            }

            details["进球"] = goals
            details["助攻"] = assists

        case .midfielder:
            let goals = getDouble(stats, key: "totalGoals")
            let assists = getDouble(stats, key: "goalAssists")
            let shotsOnTarget = getDouble(stats, key: "shotsOnTarget")
            let totalShots = getDouble(stats, key: "totalShots")
            let offsides = getDouble(stats, key: "offsides")
            let accuratePasses = getDouble(stats, key: "accuratePasses")

            score += goals * 5.0      // 进球 +5.0
            score += assists * 3.0    // 助攻 +3.0
            score += shotsOnTarget * 0.5  // 射正 +0.5
            score += totalShots * 0.2     // 射门 +0.2
            score += offsides * (-0.5)    // 越位 -0.5
            score += accuratePasses * 0.05 // 传球成功 +0.05/次（权重较小）

            // 射门得分率 > 50%
            if totalShots > 0 && shotsOnTarget / totalShots > 0.5 {
                score += 1.0
                details["射门得分率奖励"] = 1.0
            }

            details["进球"] = goals
            details["助攻"] = assists

        case .forward:
            let goals = getDouble(stats, key: "totalGoals")
            let assists = getDouble(stats, key: "goalAssists")
            let shotsOnTarget = getDouble(stats, key: "shotsOnTarget")
            let totalShots = getDouble(stats, key: "totalShots")
            let offsides = getDouble(stats, key: "offsides")
            let accuratePasses = getDouble(stats, key: "accuratePasses")

            score += goals * 6.0      // 进球 +6.0
            score += assists * 4.0    // 助攻 +4.0
            score += shotsOnTarget * 0.5  // 射正 +0.5
            score += totalShots * 0.2     // 射门 +0.2
            score += offsides * (-1.0)    // 越位 -1.0
            score += accuratePasses * 0.03 // 传球成功 +0.03/次（前锋权重更小）

            // 射门得分率 > 50%
            if totalShots > 0 && shotsOnTarget / totalShots > 0.5 {
                score += 1.0
                details["射门得分率奖励"] = 1.0
            }

            details["进球"] = goals
            details["助攻"] = assists

        case .unknown:
            // 未知位置，只计算通用项
            break
        }

        details["基础分"] = 6.0
        details["总分"] = score

        return PlayerRating(
            id: player.id,
            name: player.name,
            positionDisplayName: player.positionDisplayName,
            category: category,
            totalScore: score,
            details: details,
            player: player
        )
    }

    // MARK: - 计算全队球员评分并排序
    static func rankPlayers(in team: SoccerDetailTeam) -> [PlayerRating] {
        return team.players.map { calculateRating(for: $0) }
            .sorted { $0.totalScore > $1.totalScore }
    }

    // MARK: - 获取每个球队评分最高的球员
    static func topPlayer(from team: SoccerDetailTeam) -> PlayerRating? {
        return rankPlayers(in: team).first
    }

    // MARK: - 获取每个球队评分最高的 N 名球员
    static func topPlayers(from team: SoccerDetailTeam, count: Int = 3) -> [PlayerRating] {
        return Array(rankPlayers(in: team).prefix(count))
    }
}
