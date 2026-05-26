import SwiftUI

enum AppTheme: String, CaseIterable {
    case purpleNight = "暗夜紫红"
    case midnightBlue = "午夜蓝"
    case pureWhite = "纯净白"
    case blackGold = "黑金"

    var displayName: String { rawValue }

    // MARK: - 背景渐变
    var backgroundGradient: [Color] {
        switch self {
        case .purpleNight:
            return [
                Color(red: 26/255, green: 28/255, blue: 44/255),
                Color(red: 74/255, green: 25/255, blue: 44/255),
                Color(red: 18/255, green: 20/255, blue: 32/255)
            ]
        case .midnightBlue:
            return [
                Color(red: 10/255, green: 15/255, blue: 40/255),
                Color(red: 20/255, green: 35/255, blue: 70/255),
                Color(red: 5/255, green: 10/255, blue: 30/255)
            ]
        case .pureWhite:
            return [
                Color(red: 245/255, green: 245/255, blue: 250/255),
                Color(red: 230/255, green: 235/255, blue: 245/255),
                Color(red: 220/255, green: 225/255, blue: 240/255)
            ]
        case .blackGold:
            return [
                Color(red: 8/255, green: 8/255, blue: 8/255),
                Color(red: 20/255, green: 18/255, blue: 12/255),
                Color(red: 5/255, green: 5/255, blue: 5/255)
            ]
        }
    }

    // MARK: - 置顶横幅渐变
    var pinnedGradient: [Color] {
        switch self {
        case .purpleNight:
            return [
                Color(red: 45/255, green: 25/255, blue: 35/255),
                Color(red: 25/255, green: 20/255, blue: 30/255)
            ]
        case .midnightBlue:
            return [
                Color(red: 25/255, green: 45/255, blue: 75/255),
                Color(red: 15/255, green: 25/255, blue: 50/255)
            ]
        case .pureWhite:
            return [
                Color(red: 200/255, green: 210/255, blue: 235/255),
                Color(red: 180/255, green: 190/255, blue: 220/255)
            ]
        case .blackGold:
            return [
                Color(red: 30/255, green: 25/255, blue: 10/255),
                Color(red: 20/255, green: 18/255, blue: 8/255)
            ]
        }
    }

    // MARK: - 详情弹窗背景
    var popoverBackground: Color {
        switch self {
        case .purpleNight, .midnightBlue:
            return Color(red: 25/255, green: 25/255, blue: 25/255)
        case .pureWhite:
            return Color(red: 250/255, green: 250/255, blue: 255/255)
        case .blackGold:
            return Color(red: 15/255, green: 12/255, blue: 8/255)
        }
    }

    // MARK: - 强调色
    var accentColor: Color {
        switch self {
        case .purpleNight, .midnightBlue, .pureWhite:
            return .orange
        case .blackGold:
            return Color(red: 255/255, green: 215/255, blue: 0/255) // Gold
        }
    }

    // MARK: - 卡片背景色
    var cardBackground: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color.white.opacity(0.04)
        case .pureWhite:
            return Color.black.opacity(0.05)
        }
    }

    var cardHoverBackground: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color.white.opacity(0.08)
        case .pureWhite:
            return Color.black.opacity(0.10)
        }
    }

    var cardBorder: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color.white.opacity(0.05)
        case .pureWhite:
            return Color.black.opacity(0.10)
        }
    }

    var cardHoverBorder: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color.white.opacity(0.15)
        case .pureWhite:
            return Color.black.opacity(0.20)
        }
    }

    // MARK: - 文字色
    var textPrimary: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return .white
        case .pureWhite:
            return Color(red: 30/255, green: 30/255, blue: 35/255)
        }
    }

    var textSecondary: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color.white.opacity(0.4)
        case .pureWhite:
            return Color.black.opacity(0.4)
        }
    }

    var textTertiary: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color.white.opacity(0.6)
        case .pureWhite:
            return Color.black.opacity(0.6)
        }
    }

    var textScoreDim: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color.white.opacity(0.1)
        case .pureWhite:
            return Color.black.opacity(0.10)
        }
    }

    // MARK: - 状态色
    var statusLive: Color {
        switch self {
        case .purpleNight, .midnightBlue:
            return .orange
        case .pureWhite:
            return .orange
        case .blackGold:
            return Color(red: 255/255, green: 215/255, blue: 0/255)
        }
    }

    var statusFinal: Color {
        return textSecondary
    }

    var seriesScoreColor: Color {
        switch self {
        case .purpleNight, .midnightBlue, .pureWhite:
            return Color.orange.opacity(0.8)
        case .blackGold:
            return Color(red: 255/255, green: 215/255, blue: 0/255).opacity(0.9)
        }
    }

    // MARK: - 底部状态栏
    var statusBarBackground: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color.black.opacity(0.3)
        case .pureWhite:
            return Color.black.opacity(0.08)
        }
    }

    var statusBarText: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color.white.opacity(0.3)
        case .pureWhite:
            return Color.black.opacity(0.35)
        }
    }

    var liveIndicator: Color {
        switch self {
        case .purpleNight, .midnightBlue, .pureWhite:
            return .green
        case .blackGold:
            return Color(red: 255/255, green: 215/255, blue: 0/255)
        }
    }

    // MARK: - 头部导航栏
    var headerBackground: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color.white.opacity(0.05)
        case .pureWhite:
            return Color.black.opacity(0.05)
        }
    }

    var headerIcon: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color.white.opacity(0.3)
        case .pureWhite:
            return Color.black.opacity(0.35)
        }
    }

    // MARK: - 加载指示器
    var loadingIndicator: Color {
        switch self {
        case .purpleNight, .midnightBlue, .pureWhite:
            return .orange
        case .blackGold:
            return Color(red: 255/255, green: 215/255, blue: 0/255)
        }
    }

    // MARK: - 得分文字
    var scoreText: Color {
        return textPrimary
    }

    // MARK: - +/- 统计色
    var plusMinusPositive: Color {
        switch self {
        case .purpleNight, .midnightBlue, .pureWhite:
            return .green
        case .blackGold:
            return Color(red: 255/255, green: 215/255, blue: 0/255)
        }
    }

    var plusMinusNegative: Color {
        switch self {
        case .purpleNight, .midnightBlue, .pureWhite:
            return .red
        case .blackGold:
            return Color(red: 255/255, green: 100/255, blue: 100/255)
        }
    }

    var plusMinusNeutral: Color {
        return textSecondary
    }

    // MARK: - 列表斑马条纹
    var listZebraStripe: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color.white.opacity(0.02)
        case .pureWhite:
            return Color.black.opacity(0.02)
        }
    }

    // MARK: - 球队 Logo 圆圈背景
    var logoCircleBackground: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color.white.opacity(0.1)
        case .pureWhite:
            return Color.black.opacity(0.08)
        }
    }

    // MARK: - Divider
    var dividerColor: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color.white.opacity(0.08)
        case .pureWhite:
            return Color.black.opacity(0.10)
        }
    }

    // MARK: - 球队分项板背景
    var scoreBoardBackground: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color.white.opacity(0.05)
        case .pureWhite:
            return Color.black.opacity(0.04)
        }
    }

    // MARK: - 球员小节背景
    var playerSectionBackground: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color(white: 0.12)
        case .pureWhite:
            return Color(white: 0.97)
        }
    }

    // MARK: - 选中态
    var selectionIndicator: Color {
        switch self {
        case .purpleNight, .midnightBlue:
            return .blue
        case .pureWhite:
            return .blue
        case .blackGold:
            return Color(red: 255/255, green: 215/255, blue: 0/255)
        }
    }

    // MARK: - 足球详情弹窗
    var soccerPopoverBackground: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color(red: 30/255, green: 30/255, blue: 35/255)
        case .pureWhite:
            return Color(red: 255/255, green: 255/255, blue: 255/255)
        }
    }

    var soccerOddsBoxBackground: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color(red: 50/255, green: 50/255, blue: 60/255)
        case .pureWhite:
            return Color(red: 240/255, green: 245/255, blue: 255/255)
        }
    }

    var soccerOddsBoxBorder: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color(red: 70/255, green: 130/255, blue: 200/255).opacity(0.4)
        case .pureWhite:
            return Color(red: 100/255, green: 150/255, blue: 220/255).opacity(0.5)
        }
    }

    var soccerFormWin: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return .green
        case .pureWhite:
            return .green
        }
    }

    var soccerFormDraw: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return .yellow
        case .pureWhite:
            return .orange
        }
    }

    var soccerFormLoss: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return .red
        case .pureWhite:
            return .red
        }
    }

    // MARK: - 足球详情页主题色
    var soccerDetailBackground: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color(red: 25/255, green: 25/255, blue: 30/255)
        case .pureWhite:
            return Color(red: 250/255, green: 250/255, blue: 255/255)
        }
    }

    var soccerDetailCardBackground: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color.white.opacity(0.05)
        case .pureWhite:
            return Color.black.opacity(0.03)
        }
    }

    var soccerStatBarBackground: Color {
        switch self {
        case .purpleNight, .midnightBlue, .blackGold:
            return Color.white.opacity(0.1)
        case .pureWhite:
            return Color.black.opacity(0.08)
        }
    }

    var soccerStatBarHome: Color {
        switch self {
        case .purpleNight, .midnightBlue, .pureWhite:
            return .blue
        case .blackGold:
            return Color(red: 255/255, green: 215/255, blue: 0/255)
        }
    }

    var soccerStatBarAway: Color {
        switch self {
        case .purpleNight, .midnightBlue, .pureWhite:
            return .orange
        case .blackGold:
            return Color(red: 255/255, green: 100/255, blue: 100/255)
        }
    }

    var soccerGoalColor: Color {
        switch self {
        case .purpleNight, .midnightBlue, .pureWhite:
            return .green
        case .blackGold:
            return Color(red: 255/255, green: 215/255, blue: 0/255)
        }
    }

    var soccerYellowCardColor: Color {
        return .yellow
    }

    var soccerRedCardColor: Color {
        return .red
    }
}

// MARK: - Theme Manager
struct ThemeManager {
    static let selectedThemeKey = "selectedTheme"

    static var current: AppTheme {
        let rawValue = UserDefaults.standard.string(forKey: selectedThemeKey) ?? AppTheme.purpleNight.rawValue
        return AppTheme(rawValue: rawValue) ?? .purpleNight
    }
}
