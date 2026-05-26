import SwiftUI
import AppKit

// MARK: - 鼠标跟随悬浮窗管理器
class SoccerFloatingPopoverManager: ObservableObject {
    static let shared = SoccerFloatingPopoverManager()

    @Published var currentGame: SoccerGame?
    @Published var currentTheme: AppTheme = .purpleNight
    @Published var currentDetail: SoccerDetailData?

    private var panel: NSPanel?
    private var detailPanel: NSPanel?
    private var hideTimer: DispatchWorkItem?
    private var hoverOffset: CGFloat = 2
    private var previewPanelX: CGFloat = 0  // Track preview panel X for opposite positioning
    private var previewPanelY: CGFloat = 0  // Track preview panel Y for vertical alignment

    // Menu bar popover position (the main list window)
    private var menuBarPopoverFrame: CGRect = .zero

    private init() {}

    func show(game: SoccerGame, theme: AppTheme) {
        hideTimer?.cancel()

        // Get mouse location in screen coordinates (origin at bottom-left)
        let mouseLocation = NSEvent.mouseLocation
        let panelWidth: CGFloat = 320
        let panelHeight: CGFloat = 380

        // Get available screen bounds
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero

        // Calculate available space above and below the cursor
        let spaceAbove = screenFrame.maxY - mouseLocation.y
        let spaceBelow = mouseLocation.y - screenFrame.minY

        var panelY: CGFloat
        if spaceAbove >= panelHeight {
            // Enough space above, show above cursor
            panelY = mouseLocation.y
        } else if spaceBelow >= panelHeight {
            // Not enough space above, show below cursor
            panelY = mouseLocation.y - panelHeight
        } else {
            // Neither direction has full space, just show above (will be clipped)
            panelY = mouseLocation.y
        }

        // Horizontal position
        let spaceRight = screenFrame.maxX - mouseLocation.x
        let spaceLeft = mouseLocation.x - screenFrame.minX

        var panelX: CGFloat
        if spaceRight >= panelWidth {
            panelX = mouseLocation.x
        } else {
            panelX = mouseLocation.x - panelWidth
        }

        previewPanelX = panelX
        previewPanelY = panelY

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentGame = game
            self.currentTheme = theme
            self.createOrUpdatePanel(at: NSPoint(x: panelX, y: panelY), theme: theme)
        }
    }

    func hide() {
        hideTimer?.cancel()

        let task = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
            self?.detailPanel?.orderOut(nil)
            self?.currentGame = nil
            self?.currentDetail = nil
        }
        hideTimer = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
    }

    func getMenuBarPopoverFrame() -> CGRect {
        // Get the menu bar popover frame from global variable in NBALiveScoreApp
        return globalPopoverFrame
    }

    private func createOrUpdatePanel(at position: NSPoint, theme: AppTheme) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 380),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .screenSaver
            panel.hasShadow = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            self.panel = panel
        }

        guard let panel = panel, let game = currentGame else { return }

        // Create content view with explicit size
        let contentView = SoccerGameDetailPopover(game: game, theme: theme)
            .frame(width: 320, height: 380)

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 380)
        hostingView.setFrameSize(CGSize(width: 320, height: 380))

        panel.contentView = hostingView
        panel.setContentSize(CGSize(width: 320, height: 380))
        panel.setFrameOrigin(position)
        panel.alphaValue = 0

        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0.95 // 95% opacity
        }
    }

    func showDetail(detail: SoccerDetailData, theme: AppTheme) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        let detailWidth: CGFloat = 420
        let detailHeight: CGFloat = 610

        // Get menu bar popover frame and preview position
        let popoverFrame = SoccerFloatingPopoverManager.shared.getMenuBarPopoverFrame()

        // Position detail panel on OPPOSITE side from preview
        // Check if preview would be blocked by detail on the right side
        let previewRightEdge = previewPanelX + 320  // preview's right edge
        let detailWouldBlockPreview = previewRightEdge > popoverFrame.maxX

        let detailX: CGFloat
        if detailWouldBlockPreview {
            // Preview extends to right edge, detail would block it -> put detail on LEFT
            detailX = popoverFrame.minX - detailWidth
        } else {
            // Preview doesn't reach right edge -> put detail on RIGHT
            detailX = popoverFrame.maxX
        }

        // Calculate Y - align with menu bar popover's top edge
        let detailY = popoverFrame.maxY - detailHeight

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentDetail = detail
            self.createOrUpdateDetailPanel(at: NSPoint(x: detailX, y: detailY), theme: theme)
        }
    }

    private func createOrUpdateDetailPanel(at position: NSPoint, theme: AppTheme) {
        if detailPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 610),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .screenSaver
            panel.hasShadow = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            self.detailPanel = panel
        }

        guard let panel = detailPanel, let detail = currentDetail else { return }

        let contentView = SoccerMatchDetailPopover(detail: detail, theme: theme)
            .frame(width: 420, height: 610)

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: 610)
        hostingView.setFrameSize(CGSize(width: 420, height: 610))

        panel.contentView = hostingView
        panel.setContentSize(CGSize(width: 420, height: 610))
        panel.setFrameOrigin(position)
        panel.alphaValue = 0

        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0.95
        }
    }
}

// MARK: - 悬浮窗视图控制器
class SoccerPopoverViewController: NSViewController {
    let game: SoccerGame
    let theme: AppTheme

    init(game: SoccerGame, theme: AppTheme) {
        self.game = game
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let view = SoccerGameDetailPopover(game: game, theme: theme)
        self.view = NSHostingView(rootView: view)
        self.view.frame.size = CGSize(width: 320, height: 380)
        self.view.setFrameSize(CGSize(width: 320, height: 380))
        // Force the hosting view to not shrink
        self.view.translatesAutoresizingMaskIntoConstraints = false
    }
}

// MARK: - 足球比赛列表视图
struct SoccerContentView: View {
    @StateObject private var viewModel = SoccerViewModel()
    @StateObject private var popoverManager = PopoverManager()
    @StateObject private var pinnedManager = GlobalPinnedGameManager.shared
    @AppStorage(ThemeManager.selectedThemeKey) private var selectedTheme: String = AppTheme.purpleNight.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .purpleNight
    }

    // 当前置顶的足球比赛（可能来自其他联赛，需要单独管理）
    @State private var pinnedSoccerGame: SoccerGame?

    var body: some View {
        VStack(spacing: 0) {
            // League selector
            leagueSelector

            ScrollView {
                VStack(spacing: 12) {
                    // 足球置顶横幅
                    if pinnedManager.pinnedSport == "soccer",
                       let pinnedGame = pinnedManager.cachedSoccerGame {
                        SoccerPinnedGameBannerView(game: pinnedGame)
                            .padding(.bottom, 4)
                    }
                    // NBA置顶横幅（跨模块显示）
                    if pinnedManager.pinnedSport == "nba",
                       let nbaGame = pinnedManager.cachedNBAGame {
                        NBAPinnedBannerView(game: nbaGame)
                            .padding(.bottom, 4)
                    }

                    if viewModel.isLoading && viewModel.games.isEmpty && pinnedSoccerGame == nil {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: theme.loadingIndicator)).padding(.top, 40)
                    } else if viewModel.games.isEmpty && pinnedSoccerGame == nil {
                        Text("暂无比赛").foregroundColor(theme.textSecondary).padding(.top, 40)
                    } else {
                        ForEach(viewModel.games) { game in
                            SoccerGameRowView(game: game, viewModel: viewModel)
                        }
                    }
                }.padding(14)
            }

            // Bottom status bar
            HStack {
                Image(systemName: "network").font(.system(size: 10))
                Text(viewModel.isLoading ? "数据刷新中..." : "数据已同步")
                Spacer()
                Circle().fill(theme.liveIndicator).frame(width: 6, height: 6).shadow(color: theme.liveIndicator.opacity(0.4), radius: 4, x: 0, y: 0)
                Text("⚽ \(viewModel.currentLeague.displayName)")
            }
            .font(.system(size: 10, weight: .bold)).foregroundColor(theme.statusBarText).padding(12).background(theme.statusBarBackground)
        }
        .frame(minWidth: 320, idealWidth: 380, maxWidth: 500, minHeight: 400, idealHeight: 550, maxHeight: 850)
        .preferredColorScheme(selectedTheme == AppTheme.pureWhite.rawValue ? .light : .dark)
        .environmentObject(popoverManager)
        .onAppear {
            SportModeManager.shared.activeSport = "soccer"
            loadPinnedSoccerGame()
        }
        .onReceive(GlobalPinnedGameManager.shared.$pinnedGameId) { _ in
            loadPinnedSoccerGame()
        }
        .onReceive(GlobalPinnedGameManager.shared.$cachedSoccerGame) { cachedGame in
            if let game = cachedGame, GlobalPinnedGameManager.shared.pinnedSport == "soccer" {
                self.pinnedSoccerGame = game
            }
        }
        .onChange(of: viewModel.games) { _ in
            loadPinnedSoccerGame()
        }
    }

    private func loadPinnedSoccerGame() {
        // 检查全局置顶是否是足球
        guard GlobalPinnedGameManager.shared.pinnedSport == "soccer",
              let gameId = GlobalPinnedGameManager.shared.pinnedIdOnly else {
            pinnedSoccerGame = nil
            return
        }

        // 优先从当前列表找
        if let game = viewModel.games.first(where: { $0.id == gameId }) {
            pinnedSoccerGame = game
            GlobalPinnedGameManager.shared.cachedSoccerGame = game
        } else if let cachedGame = GlobalPinnedGameManager.shared.cachedSoccerGame, cachedGame.id == gameId {
            // 从缓存中获取
            pinnedSoccerGame = cachedGame
        } else {
            // 没找到，设置为nil
            pinnedSoccerGame = nil
        }
    }

    private func fetchPinnedSoccerGame(gameId: String) {
        // 尝试从已知的联赛中查找
        // 暂时从当前联赛获取，如果找不到则用当前联赛尝试
        viewModel.fetchSoccerGameDetail(eventId: gameId, league: viewModel.currentLeague) { detail in
            if detail != nil {
                // 创建 SoccerGame 从 detail（简化处理，直接使用备用方案）
            }
        }
    }

    private var leagueSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SoccerLeague.allCases, id: \.self) { league in
                    Button(action: {
                        viewModel.switchLeague(league)
                    }) {
                        Text(league.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(viewModel.currentLeague == league ? .white : theme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(viewModel.currentLeague == league ? theme.accentColor : theme.cardBackground)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(theme.headerBackground)
    }
}

// MARK: - 足球置顶比赛横幅
struct SoccerPinnedGameBannerView: View {
    let game: SoccerGame
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
                        Text("\(game.period) \(game.time)")
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
        // Format ISO date to readable
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: time) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "HH:mm"
            return displayFormatter.string(from: date)
        }
        return time
    }
}

// MARK: - NBA置顶比赛横幅（跨模块显示）
struct NBAPinnedBannerView: View {
    let game: Game
    @AppStorage(ThemeManager.selectedThemeKey) private var selectedTheme: String = AppTheme.purpleNight.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .purpleNight
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "pin.fill").foregroundColor(theme.statusLive).font(.system(size: 10))
                Text("已置顶 • NBA").font(.system(size: 11, weight: .bold)).foregroundColor(theme.statusLive)
                Spacer()
            }

            HStack(alignment: .center) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(theme.logoCircleBackground).frame(width: 36, height: 36)
                        TeamLogoManager.shared.logoView(tricode: game.awayTeam.tricode, networkURL: game.awayTeam.logo, size: 24)
                    }
                    Text(game.awayTeam.name).font(.system(size: 11, weight: .bold)).foregroundColor(theme.textPrimary).lineLimit(1)
                }
                .frame(width: 70)

                Spacer()

                VStack(spacing: 4) {
                    if game.status == "scheduled" {
                        Text("VS").font(.system(size: 24, weight: .black, design: .rounded)).foregroundColor(theme.textPrimary)
                    } else {
                        Text("\(game.awayTeam.score) - \(game.homeTeam.score)")
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
                        TeamLogoManager.shared.logoView(tricode: game.homeTeam.tricode, networkURL: game.homeTeam.logo, size: 24)
                    }
                    Text(game.homeTeam.name).font(.system(size: 11, weight: .bold)).foregroundColor(theme.textPrimary).lineLimit(1)
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

    private func translatePeriod(_ p: String) -> String {
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

    private func formatGameTime(_ t: String) -> String {
        if let last = t.split(separator: " ").last, String(last).contains(":") {
            return String(last)
        }
        if t.contains(":") {
            return t.replacingOccurrences(of: "Q1 ", with: "").replacingOccurrences(of: "Q2 ", with: "").replacingOccurrences(of: "Q3 ", with: "").replacingOccurrences(of: "Q4 ", with: "")
        }
        return t
    }
}

// MARK: - 足球比赛行
struct SoccerGameRowView: View {
    let game: SoccerGame
    @ObservedObject var viewModel: SoccerViewModel
    @EnvironmentObject var popoverManager: PopoverManager
    @State private var isHovered = false
    @State private var hoverTask: DispatchWorkItem?
    @AppStorage(ThemeManager.selectedThemeKey) private var selectedTheme: String = AppTheme.purpleNight.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .purpleNight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                teamInfoView
                Spacer()
                scoreAndPinView
            }
            .padding(14)
        }
        .background(backgroundView)
        .cornerRadius(12)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.snappy(duration: 0.2), value: isHovered)
        .onHover(perform: handleHover)
    }

    private var teamInfoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    TeamLogoManager.shared.logoView(tricode: game.homeTeam.countryCode, networkURL: game.homeTeam.logo, size: 16)
                    Text(game.homeTeam.name).font(.system(size: 13, weight: .bold)).foregroundColor(theme.textPrimary)
                }

                Text(":").font(.system(size: 10, weight: .black)).foregroundColor(theme.textSecondary.opacity(0.5))

                HStack(spacing: 3) {
                    TeamLogoManager.shared.logoView(tricode: game.awayTeam.countryCode, networkURL: game.awayTeam.logo, size: 16)
                    Text(game.awayTeam.name).font(.system(size: 13, weight: .bold)).foregroundColor(theme.textPrimary)
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
        if game.status == "live" { return "直播中 • \(game.time)" }
        if game.status == "final" { return "已结束" }
        return formatScheduledTime(game.time)
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
        GlobalPinnedGameManager.shared.isPinned(gameId: game.id, sport: "soccer")
    }

    private func togglePin() {
        GlobalPinnedGameManager.shared.togglePin(gameId: game.id, sport: "soccer")
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
                if self.isHovered {
                    SoccerFloatingPopoverManager.shared.show(game: self.game, theme: self.theme)
                    // Fetch detail data and show detail panel on opposite side
                    self.viewModel.fetchSoccerGameDetail(eventId: self.game.id, league: self.viewModel.currentLeague) { detail in
                        if let detail = detail {
                            SoccerFloatingPopoverManager.shared.showDetail(detail: detail, theme: self.theme)
                        }
                    }
                }
            }
            hoverTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
        } else {
            let task = DispatchWorkItem {
                SoccerFloatingPopoverManager.shared.hide()
            }
            hoverTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
        }
    }

    private func formatScheduledTime(_ time: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: time) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "HH:mm"
            return displayFormatter.string(from: date)
        }
        return time
    }
}

// MARK: - 足球比赛详情悬浮窗
struct SoccerGameDetailPopover: View {
    let game: SoccerGame
    var theme: AppTheme = ThemeManager.current

    var body: some View {
        VStack(spacing: 0) {
            // Header: Teams VS
            headerSection

            Divider().background(theme.dividerColor)

            // Status & Venue
            statusVenueSection

            Divider().background(theme.dividerColor)

            // Broadcast & Recent Form
            broadcastFormSection

            // Odds Section
            if game.odds != nil {
                Divider().background(theme.dividerColor)
                oddsSection
            }
        }
        .frame(width: 320)
        .background(theme.soccerPopoverBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 4)
        .padding(.top, -8)
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                // Home team
                VStack(spacing: 4) {
                    TeamLogoManager.shared.logoView(tricode: game.homeTeam.countryCode, networkURL: game.homeTeam.logo, size: 32)
                    Text(game.homeTeam.name).font(.system(size: 12, weight: .bold)).foregroundColor(theme.textPrimary)
                }
                .frame(maxWidth: .infinity)

                // VS
                Text("VS")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(theme.textSecondary)

                // Away team
                VStack(spacing: 4) {
                    TeamLogoManager.shared.logoView(tricode: game.awayTeam.countryCode, networkURL: game.awayTeam.logo, size: 32)
                    Text(game.awayTeam.name).font(.system(size: 12, weight: .bold)).foregroundColor(theme.textPrimary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
    }

    // MARK: - Status & Venue Section
    private var statusVenueSection: some View {
        VStack(spacing: 8) {
            // Status & Venue Row
            HStack(spacing: 12) {
                // Status pill
                HStack(spacing: 4) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(statusText).font(.system(size: 10, weight: .medium)).foregroundColor(theme.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(theme.cardBackground)
                .cornerRadius(12)

                // Venue
                if let venue = game.venue {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill").font(.system(size: 10)).foregroundColor(theme.accentColor)
                        Text(venueText(venue)).font(.system(size: 10)).foregroundColor(theme.textSecondary)
                    }
                }
            }

            // Date & Time
            HStack(spacing: 4) {
                Image(systemName: "calendar").font(.system(size: 10)).foregroundColor(.blue)
                Text(displayMatchDate).font(.system(size: 11, weight: .medium)).foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Recent Form Section
    private var broadcastFormSection: some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 9)).foregroundColor(theme.accentColor)
            Text("近期状态").font(.system(size: 10, weight: .medium)).foregroundColor(theme.textSecondary)

            Spacer()

            // 主队近期战绩 (左)
            Text(game.homeTeam.name).font(.system(size: 9, weight: .medium)).foregroundColor(theme.textSecondary)
            formIndicators(game.homeRecord ?? "-----")

            Text(":").font(.system(size: 9)).foregroundColor(theme.textSecondary)

            // 客队近期战绩 (右)
            formIndicators(game.awayRecord ?? "-----")
            Text(game.awayTeam.name).font(.system(size: 9, weight: .medium)).foregroundColor(theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Odds Section
    private var oddsSection: some View {
        VStack(spacing: 8) {
            // Bookmaker header
            HStack(spacing: 4) {
                Image(systemName: "dice.fill").font(.system(size: 9)).foregroundColor(theme.accentColor)
                Text("赔率 (\(game.odds?.bookmaker ?? "DraftKings"))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(theme.textSecondary)
                Spacer()
            }

            // Three columns of odds
            if let odds = game.odds {
                HStack(spacing: 8) {
                    // Moneyline
                    oddsBox(title: "胜平负", content: [
                        "\(game.homeTeam.name): \(formatOdds(odds.homeMoneylineOdds))",
                        "平局: \(formatOdds(odds.drawMoneylineOdds))",
                        "\(game.awayTeam.name): \(formatOdds(odds.awayMoneylineOdds))"
                    ])

                    // Spread
                    oddsBox(title: "让球盘", content: [
                        "\(game.homeTeam.name) \(odds.homeHandicap): \(formatOdds(odds.homeHandicapOdds))",
                        "\(game.awayTeam.name) \(odds.awayHandicap): \(formatOdds(odds.awayHandicapOdds))"
                    ])

                    // Over/Under
                    oddsBox(title: "大小球", content: [
                        "大球 (\(odds.overUnderLine)): \(formatOdds(odds.overOdds))",
                        "小球 (\(odds.overUnderLine)): \(formatOdds(odds.underOdds))"
                    ])
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func oddsBox(title: String, content: [String]) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 9, weight: .medium)).foregroundColor(theme.textSecondary)
            ForEach(content, id: \.self) { line in
                Text(line)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(theme.soccerOddsBoxBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.soccerOddsBoxBorder, lineWidth: 1)
        )
    }

    private func formIndicators(_ record: String) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(record.prefix(5)).indices, id: \.self) { idx in
                let char = Array(record.prefix(5))[idx]
                Text(formChinese(char))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(formTextColor(char))
                    .frame(width: 16, height: 14)
                    .background(formBgColor(char))
                    .cornerRadius(2)
            }
        }
    }

    private func formChinese(_ char: Character) -> String {
        switch char {
        case "W", "胜": return "胜"
        case "D", "平": return "平"
        case "L", "负": return "负"
        default: return "-"
        }
    }

    private func formTextColor(_ char: Character) -> Color {
        switch char {
        case "W", "胜": return .white
        case "D", "平": return .black
        case "L", "负": return .white
        default: return theme.textSecondary
        }
    }

    private func formBgColor(_ char: Character) -> Color {
        switch char {
        case "W", "胜": return theme.soccerFormWin
        case "D", "平": return theme.soccerFormDraw
        case "L", "负": return theme.soccerFormLoss
        default: return theme.cardBackground
        }
    }

    private var statusColor: Color {
        switch game.status {
        case "live": return theme.statusLive
        case "final": return theme.statusFinal
        default: return theme.textSecondary
        }
    }

    private var statusText: String {
        switch game.status {
        case "live": return "直播中 • \(game.time)"
        case "final": return "已结束"
        case "scheduled": return "未开始"
        default: return game.status
        }
    }

    private func venueText(_ venue: String) -> String {
        if let city = game.city {
            return "\(city) • \(venue)"
        }
        return venue
    }

    private var displayMatchDate: String {
        // 尝试格式化显示
        let rawDate = game.matchDate ?? game.time
        print("⚽ [概览浮窗] 原始日期数据: matchDate='\(game.matchDate ?? "nil")', time='\(game.time)'")
        let result = formatSoccerDate(rawDate)
        print("⚽ [概览浮窗] 最终显示日期: '\(result)'")
        return result
    }

    // 格式化足球日期，支持 ISO 格式和 ESPN 英文格式
    private func formatSoccerDate(_ dateString: String) -> String {
        print("⚽ [formatSoccerDate] 开始格式化: '\(dateString)'")

        // 如果已经是中文格式（包含"周"），直接返回
        if dateString.contains("周") {
            print("⚽ [formatSoccerDate] 已是中文格式，直接返回")
            return dateString
        }

        // 尝试解析标准 ISO8601 格式 (yyyy-MM-dd'T'HH:mm:ssZ)
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        if let date = isoFormatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "yyyy-MM-dd HH:mm E"
            displayFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            displayFormatter.locale = Locale(identifier: "zh_CN")
            let result = displayFormatter.string(from: date)
            print("⚽ [formatSoccerDate] ISO格式(withInternetDateTime)解析成功: \(date) -> '\(result)'")
            return result
        }
        print("⚽ [formatSoccerDate] ISO格式(withInternetDateTime)解析失败")

        // 尝试解析无秒的 ISO8601 格式 (yyyy-MM-dd'T'HH:mmZ) - 使用手动解析
        let isoFormatterNoSeconds = ISO8601DateFormatter()
        isoFormatterNoSeconds.formatOptions = [.withFullDate, .withTime, .withTimeZone]
        if let date = isoFormatterNoSeconds.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "yyyy-MM-dd HH:mm E"
            displayFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            displayFormatter.locale = Locale(identifier: "zh_CN")
            let result = displayFormatter.string(from: date)
            print("⚽ [formatSoccerDate] ISO格式(withFullDate+withTime+withTimeZone)解析成功: \(date) -> '\(result)'")
            return result
        }
        print("⚽ [formatSoccerDate] ISO格式(withFullDate+withTime+withTimeZone)解析失败")

        // 手动解析 yyyy-MM-dd'T'HH:mmZ 格式
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mmZ"
        if let date = dateFormatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "yyyy-MM-dd HH:mm E"
            displayFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            displayFormatter.locale = Locale(identifier: "zh_CN")
            let result = displayFormatter.string(from: date)
            print("⚽ [formatSoccerDate] 手动解析(yyyy-MM-dd'T'HH:mmZ)成功: \(date) -> '\(result)'")
            return result
        }
        print("⚽ [formatSoccerDate] 手动解析(yyyy-MM-dd'T'HH:mmZ)失败")

        // 尝试解析 yyyy-MM-dd'T'HH:mm:ssZ 格式
        let dateFormatterWithSeconds = DateFormatter()
        dateFormatterWithSeconds.locale = Locale(identifier: "en_US_POSIX")
        dateFormatterWithSeconds.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        if let date = dateFormatterWithSeconds.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "yyyy-MM-dd HH:mm E"
            displayFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            displayFormatter.locale = Locale(identifier: "zh_CN")
            let result = displayFormatter.string(from: date)
            print("⚽ [formatSoccerDate] 手动解析(yyyy-MM-dd'T'HH:mm:ssZ)成功: \(date) -> '\(result)'")
            return result
        }
        print("⚽ [formatSoccerDate] 手动解析(yyyy-MM-dd'T'HH:mm:ssZ)失败")

        // 尝试解析 ESPN 英文格式 "Thu, June 11th at 10:00 PM EDT"
        let englishFormatter = DateFormatter()
        let englishLocale = Locale(identifier: "en_US_POSIX")
        englishFormatter.locale = englishLocale
        // 解析格式: Weekday, Month Day Ordinal at Time Timezone
        englishFormatter.dateFormat = "EEEE, MMMM d 'at' h:mm a z"
        if let date = englishFormatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "yyyy-MM-dd HH:mm E"
            displayFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            displayFormatter.locale = Locale(identifier: "zh_CN")
            let result = displayFormatter.string(from: date)
            print("⚽ [formatSoccerDate] 英文格式(EEEE,MMMM d 'at' h:mm a z)解析成功: \(date) -> '\(result)'")
            return result
        }
        print("⚽ [formatSoccerDate] 英文格式(EEEE,MMMM d 'at' h:mm a z)解析失败")

        print("⚽ [formatSoccerDate] 所有格式都解析失败，返回原始字符串")
        return dateString
    }

    private var beijingTimeText: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: game.time) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "北京时间 MM-dd HH:mm"
            return displayFormatter.string(from: date)
        }
        // Fallback for scheduled games that might not have full ISO format
        return game.time
    }

    private var broadcastsText: String {
        if let broadcasts = game.broadcasts, !broadcasts.isEmpty {
            return broadcasts.joined(separator: ", ")
        }
        return "无转播信息"
    }

    private func formatOdds(_ odds: Double) -> String {
        if odds > 0 {
            return "+\(Int(odds))"
        } else {
            return "\(Int(odds))"
        }
    }
}

// MARK: - 足球比赛详细详情悬浮窗
struct SoccerMatchDetailPopover: View {
    let detail: SoccerDetailData
    var theme: AppTheme = ThemeManager.current

    // 统计名称翻译
    private let visibleStats = ["Possession", "Shots", "Shots On Target"]

    // MARK: - 按算法计算评分最高的球员
    private var topHomePlayers: [PlayerRatingCalculator.PlayerRating] {
        PlayerRatingCalculator.topPlayers(from: detail.homeTeam, count: 5)
    }

    private var topAwayPlayers: [PlayerRatingCalculator.PlayerRating] {
        PlayerRatingCalculator.topPlayers(from: detail.awayTeam, count: 5)
    }

    // 统一的主队列配置（基于主队第一个球员的位置）
    private var homeStatColumns: [PlayerStatRow.StatColumn] {
        if let first = topHomePlayers.first {
            return PlayerStatRow.columnsForCategory(first.category)
        }
        return PlayerStatRow.columnsForCategory(.unknown)
    }

    // 统一的客队列配置（基于客队第一个球员的位置）
    private var awayStatColumns: [PlayerStatRow.StatColumn] {
        if let first = topAwayPlayers.first {
            return PlayerStatRow.columnsForCategory(first.category)
        }
        return PlayerStatRow.columnsForCategory(.unknown)
    }

    // 格式化详情日期
    private func formatDetailMatchDate(_ dateString: String) -> String {
        print("⚽ [详情窗口] 原始日期数据: '\(dateString)'")

        // 如果已经是中文格式（包含"周"），直接返回
        if dateString.contains("周") {
            print("⚽ [详情窗口] 已是中文格式，直接返回")
            return dateString
        }

        // 尝试解析标准 ISO8601 格式 (yyyy-MM-dd'T'HH:mm:ssZ)
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        if let date = isoFormatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "yyyy-MM-dd HH:mm E"
            displayFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            displayFormatter.locale = Locale(identifier: "zh_CN")
            let result = displayFormatter.string(from: date)
            print("⚽ [详情窗口] ISO格式(withInternetDateTime)解析成功: \(date) -> '\(result)'")
            return result
        }
        print("⚽ [详情窗口] ISO格式(withInternetDateTime)解析失败")

        // 尝试解析无秒的 ISO8601 格式
        let isoFormatterNoSeconds = ISO8601DateFormatter()
        isoFormatterNoSeconds.formatOptions = [.withFullDate, .withTime, .withTimeZone]
        if let date = isoFormatterNoSeconds.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "yyyy-MM-dd HH:mm E"
            displayFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            displayFormatter.locale = Locale(identifier: "zh_CN")
            let result = displayFormatter.string(from: date)
            print("⚽ [详情窗口] ISO格式(withFullDate+withTime+withTimeZone)解析成功: \(date) -> '\(result)'")
            return result
        }
        print("⚽ [详情窗口] ISO格式(withFullDate+withTime+withTimeZone)解析失败")

        // 手动解析 yyyy-MM-dd'T'HH:mmZ 格式 (无秒)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mmZ"
        if let date = dateFormatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "yyyy-MM-dd HH:mm E"
            displayFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            displayFormatter.locale = Locale(identifier: "zh_CN")
            let result = displayFormatter.string(from: date)
            print("⚽ [详情窗口] 手动解析(yyyy-MM-dd'T'HH:mmZ)成功: \(date) -> '\(result)'")
            return result
        }
        print("⚽ [详情窗口] 手动解析(yyyy-MM-dd'T'HH:mmZ)失败")

        // 尝试解析 yyyy-MM-dd'T'HH:mm:ssZ 格式
        let dateFormatterWithSeconds = DateFormatter()
        dateFormatterWithSeconds.locale = Locale(identifier: "en_US_POSIX")
        dateFormatterWithSeconds.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        if let date = dateFormatterWithSeconds.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "yyyy-MM-dd HH:mm E"
            displayFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            displayFormatter.locale = Locale(identifier: "zh_CN")
            let result = displayFormatter.string(from: date)
            print("⚽ [详情窗口] 手动解析(yyyy-MM-dd'T'HH:mm:ssZ)成功: \(date) -> '\(result)'")
            return result
        }
        print("⚽ [详情窗口] 手动解析(yyyy-MM-dd'T'HH:mm:ssZ)失败")

        // 尝试解析 ESPN 英文格式 "Thu, June 11th at 10:00 PM EDT"
        let englishFormatter = DateFormatter()
        let englishLocale = Locale(identifier: "en_US_POSIX")
        englishFormatter.locale = englishLocale
        englishFormatter.dateFormat = "EEEE, MMMM d 'at' h:mm a z"
        if let date = englishFormatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "yyyy-MM-dd HH:mm E"
            displayFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            displayFormatter.locale = Locale(identifier: "zh_CN")
            let result = displayFormatter.string(from: date)
            print("⚽ [详情窗口] 英文格式(EEEE,MMMM d 'at' h:mm a z)解析成功: \(date) -> '\(result)'")
            return result
        }
        print("⚽ [详情窗口] 英文格式(EEEE,MMMM d 'at' h:mm a z)解析失败")

        print("⚽ [详情窗口] 所有格式都解析失败，返回原始字符串")
        return dateString
    }

    // 格式化状态详情（可能是 "FT", "HT", "45'" 或日期 "Thu, June 11th at 10:00 PM EDT"）
    private func formatStatusDetail(_ status: String, statusDetail: String) -> String {
        // 翻译足球状态缩写
        let statusTranslation: [String: String] = [
            "FT": "全场结束",
            "HT": "半场结束",
            "1H": "上半场",
            "2H": "下半场",
            "ET": "加时赛",
            "PEN": "点球",
            "POST": "加时赛"
        ]

        // 未开始比赛统一显示"未开始"
        if status == "pre" || status == "scheduled" {
            return "未开始"
        }

        // 如果是已知状态，翻译成中文
        if let translated = statusTranslation[statusDetail] {
            return translated
        }

        // 如果包含 "at" 和 "PM" 或 "AM"，说明是日期格式，需要格式化
        if statusDetail.contains(" at ") && (statusDetail.contains("PM") || statusDetail.contains("AM")) {
            // 移除序数后缀 (st, nd, rd, th) 如 "11th" -> "11"
            var cleanedString = statusDetail
            let ordinalPattern = try? NSRegularExpression(pattern: "(\\d+)(st|nd|rd|th)", options: [])
            if let regex = ordinalPattern {
                let range = NSRange(cleanedString.startIndex..., in: cleanedString)
                cleanedString = regex.stringByReplacingMatches(in: cleanedString, options: [], range: range, withTemplate: "$1") ?? statusDetail
            }

            // 尝试解析英文日期格式
            let englishFormatter = DateFormatter()
            let englishLocale = Locale(identifier: "en_US_POSIX")
            englishFormatter.locale = englishLocale
            // 格式: "Thu, June 11 at 10:00 PM EDT"
            englishFormatter.dateFormat = "EEEE, MMMM d 'at' h:mm a z"
            if let date = englishFormatter.date(from: cleanedString) {
                let displayFormatter = DateFormatter()
                displayFormatter.dateFormat = "yyyy-MM-dd HH:mm E"
                displayFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
                displayFormatter.locale = Locale(identifier: "zh_CN")
                return displayFormatter.string(from: date)
            }
            // 尝试其他可能的格式
            let altFormatter = DateFormatter()
            altFormatter.locale = englishLocale
            altFormatter.dateFormat = "EEE, MMM d 'at' h:mm a z"
            if let date = altFormatter.date(from: cleanedString) {
                let displayFormatter = DateFormatter()
                displayFormatter.dateFormat = "yyyy-MM-dd HH:mm E"
                displayFormatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
                displayFormatter.locale = Locale(identifier: "zh_CN")
                return displayFormatter.string(from: date)
            }
        }
        // 否则直接返回原值（45', 90' 等状态）
        return statusDetail
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header: Teams VS, Score, League, Date (压缩版)
                compactHeaderSection

                Divider().background(theme.dividerColor)

                // Stats Comparison (仅显示3项)
                let visibleStatsList = detail.statistics.filter { visibleStats.contains($0.name) }
                if !visibleStatsList.isEmpty {
                    statsSection
                    Divider().background(theme.dividerColor)
                }

                // 首发阵型 & 关键球员
                lineupSection
                Divider().background(theme.dividerColor)

                // 球员数据
                if hasPlayers {
                    playerStatsSection
                }
            }
            .frame(width: 420)
            .background(theme.soccerDetailBackground)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 4)
        }
    }

    // MARK: - Header Section (压缩版)
    private var compactHeaderSection: some View {
        VStack(spacing: 6) {
            // League & Date
            Text(detail.league)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(theme.accentColor)

            // Teams and Score (紧凑布局)
            HStack(spacing: 0) {
                // Home Team
                HStack(spacing: 6) {
                    TeamLogoManager.shared.logoView(tricode: detail.homeTeam.shortName, networkURL: detail.homeTeam.logo, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detail.homeTeam.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(theme.textPrimary)
                            .lineLimit(1)
                        if let formation = detail.homeTeam.formation {
                            Text(formation)
                                .font(.system(size: 9))
                                .foregroundColor(theme.textSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                // Score
                VStack(spacing: 2) {
                    HStack(spacing: 8) {
                        Text("\(detail.homeScore)")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(theme.textPrimary)
                        Text("-")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(theme.textSecondary)
                        Text("\(detail.awayScore)")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(theme.textPrimary)
                    }
                    Text(formatStatusDetail(detail.status, statusDetail: detail.statusDetail))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(theme.statusLive)
                }
                .padding(.horizontal, 12)

                // Away Team
                HStack(spacing: 6) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(detail.awayTeam.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(theme.textPrimary)
                            .lineLimit(1)
                        if let formation = detail.awayTeam.formation {
                            Text(formation)
                                .font(.system(size: 9))
                                .foregroundColor(theme.textSecondary)
                        }
                    }
                    TeamLogoManager.shared.logoView(tricode: detail.awayTeam.shortName, networkURL: detail.awayTeam.logo, size: 28)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Match Date
            Text(formatDetailMatchDate(detail.matchDate))
                .font(.system(size: 9))
                .foregroundColor(theme.textSecondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 16)
    }

    // MARK: - Stats Section (仅3项，无标题)
    private var statsSection: some View {
        VStack(spacing: 6) {
            ForEach(detail.statistics.filter { visibleStats.contains($0.name) }) { stat in
                StatComparisonRow(stat: stat, theme: theme)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - 首发阵型 & 关键球员 Section
    private var lineupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "person.3.fill").font(.system(size: 10)).foregroundColor(theme.accentColor)
                Text("首发阵型 & 关键球员").font(.system(size: 11, weight: .semibold)).foregroundColor(theme.textPrimary)
            }
            .padding(.top, 8)

            HStack(alignment: .top, spacing: 12) {
                // 主队首发阵容
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(detail.homeTeam.players.filter { $0.isStarter }.sorted { ($0.formationPlace ?? "0") < ($1.formationPlace ?? "0") }) { player in
                        LineupPlayerRow(player: player, theme: theme, isHome: true, keyEvents: detail.keyEvents)
                    }
                }
                .frame(maxWidth: .infinity)

                Divider().background(theme.dividerColor)

                // 客队首发阵容
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(detail.awayTeam.players.filter { $0.isStarter }.sorted { ($0.formationPlace ?? "0") < ($1.formationPlace ?? "0") }) { player in
                        LineupPlayerRow(player: player, theme: theme, isHome: false, keyEvents: detail.keyEvents)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - 球员数据 Section
    private var playerStatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet.clipboard.fill").font(.system(size: 10)).foregroundColor(theme.accentColor)
                Text("球员数据").font(.system(size: 11, weight: .semibold)).foregroundColor(theme.textPrimary)
            }
            .padding(.top, 8)

            // 主队球员数据
            VStack(alignment: .leading, spacing: 2) {
                // 统一表头
                statHeader(columns: homeStatColumns)

                ForEach(Array(topHomePlayers.enumerated()), id: \.element.id) { index, rating in
                    PlayerStatRow(player: rating.player, theme: theme, isHome: true, isAlternate: index % 2 == 1, rating: rating.totalScore, statColumns: homeStatColumns)
                }
            }

            // 分割线
            Divider().background(theme.dividerColor)
                .padding(.vertical, 4)

            // 客队球员数据
            VStack(alignment: .trailing, spacing: 2) {
                // 统一表头
                statHeader(columns: awayStatColumns)

                ForEach(Array(topAwayPlayers.enumerated()), id: \.element.id) { index, rating in
                    PlayerStatRow(player: rating.player, theme: theme, isHome: false, isAlternate: index % 2 == 1, rating: rating.totalScore, statColumns: awayStatColumns)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // 动态表头
    private func statHeader(columns: [PlayerStatRow.StatColumn]) -> some View {
        return HStack(spacing: 0) {
            Text("球员").font(.system(size: 9, weight: .medium)).foregroundColor(theme.textSecondary)
                .frame(width: 70, alignment: .leading)
            ForEach(columns, id: \.self) { col in
                Text(col.rawValue).font(.system(size: 9, weight: .medium)).foregroundColor(theme.textSecondary)
                    .frame(width: colWidth(for: col))
            }
        }
    }

    private func colWidth(for column: PlayerStatRow.StatColumn) -> CGFloat {
        switch column {
        case .goals, .assists, .shots, .shotsOnTarget, .saves, .goalsConceded, .fouls, .offsides, .foulsSuffered, .subIns, .ownGoals, .passes:
            return 28
        case .cards:
            return 36
        }
    }

    private var hasPlayers: Bool {
        !detail.homeTeam.players.isEmpty || !detail.awayTeam.players.isEmpty
    }
}

// MARK: - 阵容球员行
struct LineupPlayerRow: View {
    let player: SoccerPlayerStat
    var theme: AppTheme = ThemeManager.current
    let isHome: Bool
    var keyEvents: [SoccerKeyEvent] = []  // 关键事件（用于显示时间）

    // 根据球员名匹配所有事件时间
    private func eventTimes(for eventType: EventType) -> [String] {
        let playerNameToMatch = player.originalDisplayName ?? player.name
        // 匹配该球员的所有指定类型事件（type比较已经统一为.goal/.yellowCard/.redCard/.substitution）
        let matches = keyEvents.filter { event in
            event.type == eventType && (event.player == playerNameToMatch || event.player.contains(player.name))
        }
        return matches.compactMap { $0.minute }
    }

    // 所有进球时间
    private var goalTimes: [String] {
        eventTimes(for: .goal)
    }

    // 所有黄牌时间
    private var yellowCardTimes: [String] {
        eventTimes(for: .yellowCard)
    }

    // 所有红牌时间
    private var redCardTimes: [String] {
        eventTimes(for: .redCard)
    }

    var body: some View {
        HStack(spacing: 4) {
            // 球衣号
            Text("\(player.number ?? 0)")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(theme.textSecondary)
                .frame(width: 16, alignment: .center)

            // 球员名
            Text(player.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 80, alignment: .leading)

            Spacer()

            // 事件图标和时间（支持多次事件）
            HStack(spacing: 2) {
                // 进球（多次）
                ForEach(Array(goalTimes.enumerated()), id: \.offset) { index, time in
                    Text("⚽\(time)").font(.system(size: 9, weight: .medium))
                        .foregroundColor(.orange)
                }
                if player.hasGoal && goalTimes.isEmpty {
                    Text("⚽").font(.system(size: 9))
                }

                // 黄牌（多次）
                ForEach(Array(yellowCardTimes.enumerated()), id: \.offset) { index, time in
                    Text("🟡\(time)").font(.system(size: 8, weight: .medium))
                        .foregroundColor(.yellow)
                }
                if player.hasYellowCard && yellowCardTimes.isEmpty {
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: 8, height: 10)
                        .cornerRadius(1)
                }

                // 红牌（多次）
                ForEach(Array(redCardTimes.enumerated()), id: \.offset) { index, time in
                    Text("🟥\(time)").font(.system(size: 8, weight: .medium))
                        .foregroundColor(.red)
                }
                if player.hasRedCard && redCardTimes.isEmpty {
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 8, height: 10)
                        .cornerRadius(1)
                }
            }
        }
    }
}

// MARK: - 球员数据行
struct PlayerStatRow: View {
    let player: SoccerPlayerStat
    var theme: AppTheme = ThemeManager.current
    let isHome: Bool
    let isAlternate: Bool
    var rating: Double? = nil  // 贡献评分（可选）
    var statColumns: [StatColumn]  // 外部传入的统一列配置

    // 位置分类（用于决定显示哪些列）
    enum StatColumn: String, CaseIterable {
        case goals = "进球"
        case assists = "助攻"
        case shots = "射门"
        case shotsOnTarget = "射正"
        case saves = "扑救"
        case goalsConceded = "丢球"
        case fouls = "犯规"
        case offsides = "越位"
        case foulsSuffered = "被犯"
        case subIns = "替补"
        case ownGoals = "乌龙"
        case passes = "传球"
        case cards = "牌"
    }

    // 按优先级获取要显示的列（根据位置）
    static func columnsForPlayer(_ player: SoccerPlayerStat) -> [StatColumn] {
        let category = PlayerRatingCalculator.categorizePosition(player.positionDisplayName)
        return columnsForCategory(category)
    }

    static func columnsForCategory(_ category: PlayerRatingCalculator.PositionCategory) -> [StatColumn] {
        switch category {
        case .goalkeeper:
            return [.goals, .assists, .saves, .goalsConceded, .fouls, .cards]
        case .defender:
            return [.goals, .assists, .shots, .shotsOnTarget, .passes, .offsides, .fouls, .foulsSuffered, .cards]
        case .midfielder:
            return [.goals, .assists, .shots, .shotsOnTarget, .passes, .offsides, .fouls, .foulsSuffered, .cards]
        case .forward:
            return [.goals, .assists, .shots, .shotsOnTarget, .passes, .offsides, .foulsSuffered, .cards]
        case .unknown:
            return [.goals, .assists, .shots, .passes, .offsides, .fouls, .cards]
        }
    }

    private func getStat(_ key: String) -> String {
        let statKeyMap: [String: String] = [
            "goals": "totalGoals",
            "assists": "goalAssists",
            "shots": "totalShots",
            "shotsOnTarget": "shotsOnTarget",
            "saves": "saves",
            "goalsConceded": "goalsConceded",
            "fouls": "foulsCommitted",
            "offsides": "offsides",
            "foulsSuffered": "foulsSuffered",
            "subIns": "subIns",
            "ownGoals": "ownGoals",
            "passes": "accuratePasses"
        ]
        let actualKey = statKeyMap[key] ?? key
        return player.stats[actualKey] ?? "-"
    }

    // 评分颜色
    private func ratingColor(_ rating: Double) -> Color {
        if rating >= 9.0 { return Color.green }
        if rating >= 7.0 { return Color.blue }
        if rating >= 5.0 { return Color.orange }
        return Color.gray
    }

    private var playerCategory: PlayerRatingCalculator.PositionCategory {
        PlayerRatingCalculator.categorizePosition(player.positionDisplayName)
    }

    var body: some View {
        HStack(spacing: 0) {
            // 球员名 + 评分
            HStack(spacing: 3) {
                Text(player.name)
                    .font(.system(size: 10))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)
                if let rating = rating {
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(ratingColor(rating))
                        .cornerRadius(3)
                }
            }
            .frame(width: 112, alignment: .leading)

            // 动态显示统计列
            ForEach(statColumns, id: \.self) { col in
                statCell(for: col)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(isAlternate ? theme.listZebraStripe : Color.clear)
    }

    @ViewBuilder
    private func statCell(for column: StatColumn) -> some View {
        switch column {
        case .goals:
            Text(getStat("goals"))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(theme.soccerGoalColor)
                .frame(width: 28)
        case .assists:
            Text(getStat("assists"))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(theme.accentColor)
                .frame(width: 28)
        case .shots:
            Text(getStat("shots"))
                .font(.system(size: 10))
                .foregroundColor(theme.textPrimary)
                .frame(width: 28)
        case .shotsOnTarget:
            Text(getStat("shotsOnTarget"))
                .font(.system(size: 10))
                .foregroundColor(theme.textPrimary)
                .frame(width: 28)
        case .saves:
            Text(getStat("saves"))
                .font(.system(size: 10))
                .foregroundColor(theme.textPrimary)
                .frame(width: 28)
        case .goalsConceded:
            Text(getStat("goalsConceded"))
                .font(.system(size: 10))
                .foregroundColor(player.stats["goalsConceded"] == "0" ? theme.soccerGoalColor : theme.textPrimary)
                .frame(width: 28)
        case .fouls:
            Text(getStat("fouls"))
                .font(.system(size: 10))
                .foregroundColor(theme.textPrimary)
                .frame(width: 28)
        case .offsides:
            let val = getStat("offsides")
            Text(val)
                .font(.system(size: 10))
                .foregroundColor(val == "-" ? theme.textSecondary : (Int(val) ?? 0) > 0 ? Color.orange : theme.textSecondary)
                .frame(width: 28)
        case .foulsSuffered:
            Text(getStat("foulsSuffered"))
                .font(.system(size: 10))
                .foregroundColor(theme.textPrimary)
                .frame(width: 28)
        case .subIns:
            Text(getStat("subIns"))
                .font(.system(size: 10))
                .foregroundColor(theme.textSecondary)
                .frame(width: 28)
        case .ownGoals:
            Text(getStat("ownGoals"))
                .font(.system(size: 10))
                .foregroundColor(getStat("ownGoals") == "-" ? theme.textSecondary : Color.red)
                .frame(width: 28)
        case .passes:
            let passes = getStat("passes")
            Text(passes)
                .font(.system(size: 10))
                .foregroundColor(passes == "-" ? theme.textSecondary : theme.accentColor)
                .frame(width: 28)
        case .cards:
            HStack(spacing: 2) {
                if player.hasYellowCard {
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: 6, height: 8)
                        .cornerRadius(1)
                } else {
                    Text("-")
                        .font(.system(size: 9))
                        .foregroundColor(theme.textSecondary)
                }
                if player.hasRedCard {
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 6, height: 8)
                        .cornerRadius(1)
                }
            }
            .frame(width: 36, alignment: .trailing)
        }
    }
}

// MARK: - Stat Comparison Row
struct StatComparisonRow: View {
    let stat: SoccerTeamStatItem
    var theme: AppTheme = ThemeManager.current

    var body: some View {
        VStack(spacing: 4) {
            // Labels
            HStack {
                Text(stat.homeDisplay)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(theme.soccerStatBarHome)
                Spacer()
                Text(soccerStatTranslation[stat.label] ?? stat.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(theme.textSecondary)
                Spacer()
                Text(stat.awayDisplay)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(theme.soccerStatBarAway)
            }

            // Comparison Bar
            GeometryReader { geometry in
                let homeValue = parseStatValue(stat.homeValue)
                let awayValue = parseStatValue(stat.awayValue)
                let total = max(homeValue + awayValue, 1)
                let homeRatio = CGFloat(homeValue) / CGFloat(total)
                let barWidth = geometry.size.width

                HStack(spacing: 2) {
                    Rectangle()
                        .fill(theme.soccerStatBarHome)
                        .frame(width: barWidth * homeRatio * 0.48)
                    Spacer()
                    Rectangle()
                        .fill(theme.soccerStatBarAway)
                        .frame(width: barWidth * (1 - homeRatio) * 0.48)
                }
            }
            .frame(height: 4)
            .background(theme.soccerStatBarBackground)
            .cornerRadius(2)
        }
    }

    private func parseStatValue(_ value: String) -> Double {
        // Remove percentage sign if present
        let cleaned = value.replacingOccurrences(of: "%", with: "")
        // Try to parse as double
        if let doubleValue = Double(cleaned) {
            return doubleValue
        }
        // Try to parse as int
        if let intValue = Int(cleaned) {
            return Double(intValue)
        }
        return 0
    }
}

// MARK: - Key Event Row
struct KeyEventRow: View {
    let event: SoccerKeyEvent
    var theme: AppTheme = ThemeManager.current

    var body: some View {
        HStack(spacing: 8) {
            // Team abbreviation
            Text(event.team)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(theme.textSecondary)
                .frame(width: 30, alignment: .leading)

            // Event icon and player
            HStack(spacing: 4) {
                eventIcon
                Text(event.player)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            // Minute
            if let minute = event.minute {
                Text(minute)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(theme.soccerDetailCardBackground)
        .cornerRadius(4)
    }

    @ViewBuilder
    private var eventIcon: some View {
        switch event.type {
        case .goal:
            Text("⚽")
                .font(.system(size: 12))
        case .yellowCard, .yellowcard:
            Rectangle()
                .fill(theme.soccerYellowCardColor)
                .frame(width: 10, height: 12)
                .cornerRadius(2)
        case .redCard, .redcard:
            Rectangle()
                .fill(theme.soccerRedCardColor)
                .frame(width: 10, height: 12)
                .cornerRadius(2)
        case .substitution:
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 10))
                .foregroundColor(theme.textSecondary)
        }
    }
}

