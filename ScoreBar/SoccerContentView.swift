import SwiftUI
import AppKit

// MARK: - 鼠标跟踪容器视图
// 监听 mouseEntered/mouseExited,用于在鼠标进入 detail 时阻止关闭,
// 鼠标离开 detail 时启动关闭
private final class MouseTrackingContainerView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        // NSPanel 是 nonactivatingPanel, 永远不会成为 key window,
        // 所以必须用 .activeInActiveApp 才能激活 tracking area
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}

// MARK: - 鼠标跟随悬浮窗管理器
class SoccerFloatingPopoverManager: ObservableObject {
    static let shared = SoccerFloatingPopoverManager()

    @Published var currentGame: SoccerGame?
    @Published var currentTheme: AppTheme = .purpleNight
    @Published var currentDetail: SoccerDetailData?

    private var panel: NSPanel?
    private var detailPanel: NSPanel?
    private var hideTimer: DispatchWorkItem?
    private var hideDetailTimer: DispatchWorkItem?
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
            guard let self = self else { return }
            // 关闭 preview panel
            self.panel?.orderOut(nil)
            self.currentGame = nil
            // 启动 detail 关闭 timer,鼠标不在 detail 内的 0.3s 后关闭
            // 用户从行移到 detail 的短暂窗口,鼠标进入 detail 时会被 cancel
            // 鼠标不在 detail 内时正常关闭
            self.scheduleHideDetail(after: 0.3)
        }
        hideTimer = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
    }

    /// 安排延迟关闭 detail panel(被 Soccer 行 hover-out 触发,或 detail 自身 mouseExited 触发)
    private func scheduleHideDetail(after delay: TimeInterval) {
        hideDetailTimer?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            // 关键检查:鼠标是否在 detail 面板内?
            // 如果是,即使定时器到点也不关闭,让用户继续看 detail
            // (detail 自身的 mouseExited 会处理关闭)
            let mouseLocation = NSEvent.mouseLocation
            if let panel = self.detailPanel, panel.frame.contains(mouseLocation) {
                return
            }
            self.detailPanel?.orderOut(nil)
            self.currentDetail = nil
        }
        hideDetailTimer = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    /// 取消待执行的 detail 关闭(detail mouseEntered 时调用)
    private func cancelHideDetail() {
        hideDetailTimer?.cancel()
        hideDetailTimer = nil
    }

    /// 显式关闭详情窗口（由详情面板内的关闭按钮触发）
    func hideDetail() {
        cancelHideDetail()
        detailPanel?.orderOut(nil)
        currentDetail = nil
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

        // 容器 view: 监听 mouseEntered/mouseExited
        // mouseEntered → 取消 Soccer 行 hover-out 触发的关闭 timer (保持 detail)
        // mouseExited → 启动新 timer 关闭 detail
        let container = MouseTrackingContainerView(frame: NSRect(x: 0, y: 0, width: 420, height: 610))
        container.autoresizingMask = [.width, .height]
        container.onMouseEntered = { [weak self] in
            self?.cancelHideDetail()
        }
        container.onMouseExited = { [weak self] in
            self?.scheduleHideDetail(after: 0.3)
        }

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)

        panel.contentView = container
        panel.setContentSize(CGSize(width: 420, height: 610))
        panel.setFrameOrigin(position)
        panel.alphaValue = 0

        cancelHideDetail()
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
                        Text(formatScore(home: game.homeTeam.score, away: game.awayTeam.score, homeShootout: game.homeTeam.shootoutScore, awayShootout: game.awayTeam.shootoutScore))
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(theme.textPrimary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
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

    // 格式化带点球的比分，如 1(4):1(3)
    private func formatScore(home: String, away: String, homeShootout: Int?, awayShootout: Int?) -> String {
        if let hShootout = homeShootout, let aShootout = awayShootout {
            return "\(home)(\(hShootout)):\(away)(\(aShootout))"
        }
        return "\(home)-\(away)"
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
                    Text(game.homeTeam.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                }

                Text(":").font(.system(size: 10, weight: .black)).foregroundColor(theme.textSecondary.opacity(0.5))

                HStack(spacing: 3) {
                    TeamLogoManager.shared.logoView(tricode: game.awayTeam.countryCode, networkURL: game.awayTeam.logo, size: 16)
                    Text(game.awayTeam.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            HStack(spacing: 6) {
                if game.status == "live" { Circle().fill(theme.statusLive).frame(width: 6, height: 6) }
                Text(statusText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(game.status == "live" ? theme.statusLive : theme.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var statusText: String {
        if game.status == "live" { return "直播中 • \(game.time)" }
        if game.status == "final" { return "已结束" }
        return formatScheduledTime(game.time)
    }

    private var scoreAndPinView: some View {
        HStack(spacing: 4) {
            if game.status == "scheduled" {
                Text("-- : --")
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(theme.textScoreDim)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            } else {
                Text(formatScoreWithShootout(home: game.homeTeam.score, away: game.awayTeam.score, homeShootout: game.homeTeam.shootoutScore, awayShootout: game.awayTeam.shootoutScore))
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(theme.scoreText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
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

    // 格式化带点球的比分，如 1(4):1(3)，用于 SoccerGameRowView
    private func formatScoreWithShootout(home: String, away: String, homeShootout: Int?, awayShootout: Int?) -> String {
        if let hShootout = homeShootout, let aShootout = awayShootout {
            return "\(home)(\(hShootout)):\(away)(\(aShootout))"
        }
        return "\(home)-\(away)"
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

    // 统计名称翻译（匹配图片中的6项）
    private let visibleStats = ["possessionPct", "shotsOnTarget", "totalShots", "yellowCards", "wonCorners", "saves"]
    private let visibleStatLabels = ["控球率", "射正", "射门", "黄牌", "角球", "扑救"]

    // 时间线选中的事件组（用于弹窗，按"同分钟同类型"合并）
    @State private var selectedTimelineGroup: TimelineEventGroup?

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

    // MARK: - 时间线辅助方法

    /// 过滤出需要展示的事件（进球/换人/黄牌/红牌），按时间升序
    private var timelineEvents: [SoccerKeyEvent] {
        detail.keyEvents
            .filter { e in
                switch e.type {
                case .goal, .yellowCard, .redCard, .substitution:
                    return true
                default:
                    return false
                }
            }
            .sorted {
                (totalMinutes(from: $0.minute ?? "0")) < (totalMinutes(from: $1.minute ?? "0"))
            }
    }

    /// 把 "45'+7'"、"6'"、"118"、"45+2" 等时间字符串转换为总分钟数
    /// ESPN API 实际格式示例:
    ///   - "6'"        → 6
    ///   - "45'+7'"    → 52 (45 + 7 伤停补时)
    ///   - "118'"      → 118
    ///   - ""          → 0 (KO 等)
    private func totalMinutes(from minute: String) -> Int {
        // 先去掉所有单引号: "45'+7'" → "45+7", "6'" → "6"
        let cleaned = minute.replacingOccurrences(of: "'", with: "")
        if cleaned.contains("+") {
            let parts = cleaned.split(separator: "+")
            return (Int(parts[0]) ?? 0) + (Int(parts[1]) ?? 0)
        }
        return Int(cleaned) ?? 0
    }

    /// 决定时间轴的总刻度（根据事件最远时间动态）
    private var timelineMaxMinute: Int {
        let maxEventMinute = timelineEvents.map { totalMinutes(from: $0.minute ?? "0") }.max() ?? 0
        if maxEventMinute > 120 { return max(maxEventMinute + 5, 130) }   // AET
        if maxEventMinute > 95  { return max(maxEventMinute + 5, 120) }   // 加时
        return max(maxEventMinute + 5, 90)                                // 常规
    }

    /// 当前进度分钟（比赛进行中用最后事件，结束用 max，赛前为 nil）
    private var currentProgressMinute: Int? {
        switch detail.status {
        case "in":
            // 进行中:用最后一个事件代表当前时间
            return timelineEvents.last.map { totalMinutes(from: $0.minute ?? "0") }
        case "post":
            return timelineMaxMinute
        default:
            return nil  // pre
        }
    }

    /// 解析换人事件的 "On" / "Off" 球员
    private func parseSubstitution(_ event: SoccerKeyEvent) -> (on: String, off: String)? {
        guard let info = event.additionalInfo else { return nil }
        let pattern = "Substitution, .+?\\. (.+?) replaces (.+)\\.?$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: info, options: [], range: NSRange(info.startIndex..., in: info)),
              let inRange = Range(match.range(at: 1), in: info),
              let outRange = Range(match.range(at: 2), in: info) else {
            return nil
        }
        var onPlayer = String(info[inRange]).trimmingCharacters(in: .whitespaces)
        var offPlayer = String(info[outRange]).trimmingCharacters(in: .whitespaces)
        if onPlayer.hasSuffix(".") { onPlayer = String(onPlayer.dropLast()) }
        if offPlayer.hasSuffix(".") { offPlayer = String(offPlayer.dropLast()) }
        return (onPlayer, offPlayer)
    }

    /// 判断事件是否属于主队
    /// 直接用 event.isHome 字段(SoccerKeyEvent 创建时已标记,基于 teamId 比较)
    private func isHomeEvent(_ event: SoccerKeyEvent) -> Bool {
        return event.isHome
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header: Teams VS, Score, League, Date (压缩版)
                compactHeaderSection

                Divider().background(theme.dividerColor)

                // 比赛时间线(暂时隐藏,代码保留)
                // timelineSection

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

                // MARK: - 球员数据模块（暂时隐藏，后续启用）
                // if hasPlayers {
                //     playerStatsSection
                // }
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

                // Score (固定最小宽度,防止 "1(4) - 1(3)" 被换行)
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        if let penaltyScore = detail.homePenaltyScore {
                            Text("\(detail.homeScore)(\(penaltyScore))")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(theme.textPrimary)
                                .lineLimit(1)
                                .fixedSize()
                        } else {
                            Text("\(detail.homeScore)")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(theme.textPrimary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        Text("-")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(theme.textSecondary)
                            .lineLimit(1)
                            .fixedSize()
                        if let penaltyScore = detail.awayPenaltyScore {
                            Text("\(detail.awayScore)(\(penaltyScore))")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(theme.textPrimary)
                                .lineLimit(1)
                                .fixedSize()
                        } else {
                            Text("\(detail.awayScore)")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(theme.textPrimary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .fixedSize()
                    Text(formatStatusDetail(detail.status, statusDetail: detail.statusDetail))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(theme.statusLive)
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.horizontal, 10)
                .frame(minWidth: 130)

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
    // MARK: - 比赛时间线 Section
    private var timelineSection: some View {
        TimelineBarView(
            events: timelineEvents,
            maxMinute: timelineMaxMinute,
            progressMinute: currentProgressMinute,
            homeTeamName: detail.homeTeam.name,
            awayTeamName: detail.awayTeam.name,
            isHomeEvent: isHomeEvent,
            theme: theme,
            selectedTimelineGroup: $selectedTimelineGroup
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var statsSection: some View {
        VStack(spacing: 6) {
            ForEach(detail.statistics.filter { visibleStats.contains($0.name) }) { stat in
                // 获取中文标签
                let label = visibleStatLabels[visibleStats.firstIndex(of: stat.name) ?? 0]
                StatComparisonRow(stat: stat, theme: theme, customLabel: label)
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
                Text("球员").font(.system(size: 11, weight: .semibold)).foregroundColor(theme.textPrimary)
            }
            .padding(.top, 8)

            // 构建换人映射: 球员名 -> (下场时间, 上场时间)
            let subMap = buildSubstitutionMap()

            // 所有球员列表（首发+替补，按换人排序）
            HStack(alignment: .top, spacing: 12) {
                // 主队所有球员
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sortedPlayersWithSubstitutions(detail.homeTeam.players, subMap: subMap), id: \.id) { player in
                        LineupPlayerRow(player: player, theme: theme, isHome: true, keyEvents: detail.keyEvents, substitutionMap: subMap)
                    }
                }
                .frame(maxWidth: .infinity)

                Divider().background(theme.dividerColor)

                // 客队所有球员
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(sortedPlayersWithSubstitutions(detail.awayTeam.players, subMap: subMap), id: \.id) { player in
                        LineupPlayerRow(player: player, theme: theme, isHome: false, keyEvents: detail.keyEvents, substitutionMap: subMap)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // 构建换人时间映射: 球员名 -> (下场时间, 上场时间)
    private func buildSubstitutionMap() -> [String: (outTime: String?, inTime: String?, replacedName: String?)] {
        var map: [String: (outTime: String?, inTime: String?, replacedName: String?)] = [:]

        for event in detail.keyEvents where event.type == .substitution {
            guard let info = event.additionalInfo else { continue }

            // 格式: "Substitution, Arsenal. Jurriën Timber replaces Cristhian Mosquera."
            let pattern = "Substitution, .+?\\. (.+?) replaces (.+)\\.?$"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: info, options: [], range: NSRange(info.startIndex..., in: info)) {
                if let inRange = Range(match.range(at: 1), in: info),
                   let outRange = Range(match.range(at: 2), in: info) {
                    // 去掉末尾的句号和空格
                    var inPlayer = String(info[inRange]).trimmingCharacters(in: .whitespaces)
                    var outPlayer = String(info[outRange]).trimmingCharacters(in: .whitespaces)
                    if inPlayer.hasSuffix(".") { inPlayer = String(inPlayer.dropLast()) }
                    if outPlayer.hasSuffix(".") { outPlayer = String(outPlayer.dropLast()) }

                    let time = event.minute

                    // 记录上场时间
                    map[inPlayer] = (outTime: nil, inTime: time, replacedName: outPlayer)
                    // 记录下场时间
                    map[outPlayer] = (outTime: time, inTime: nil, replacedName: nil)
                }
            }
        }
        return map
    }

    // 按换人关系排序球员列表，被换上者排在被换下者下方
    private func sortedPlayersWithSubstitutions(_ players: [SoccerPlayerStat], subMap: [String: (outTime: String?, inTime: String?, replacedName: String?)]) -> [SoccerPlayerStat] {
        // 过滤：只保留有参与比赛的球员
        let filteredPlayers = players.filter { player in
            if player.isStarter { return true }
            // 替补：检查是否被换上（使用模糊匹配，同时尝试中文 name 和英文 originalDisplayName）
            let wasBroughtIn = findInTimeInMap(playerName: player.name, originalDisplayName: player.originalDisplayName, subMap: subMap) != nil
            // 替补：检查是否有事件
            let hasEvents = player.hasGoal || player.hasYellowCard || player.hasRedCard
            let keep = wasBroughtIn || hasEvents
            if !keep {
                let inT = findInTimeInMap(playerName: player.name, originalDisplayName: player.originalDisplayName, subMap: subMap) ?? "nil"
                print("🔍 [过滤] 替补 #\(player.number ?? 0) \(player.name) (orig=\(player.originalDisplayName ?? "nil")) 被过滤: inTime=\(inT), hasGoal=\(player.hasGoal), hasYellow=\(player.hasYellowCard), hasRed=\(player.hasRedCard)")
            }
            return keep
        }

        print("🔍 [subMap] 换人映射(\(subMap.count) 条):")
        for (k, v) in subMap {
            print("    '\(k)' → inTime=\(v.inTime ?? "nil"), outTime=\(v.outTime ?? "nil"), replaced=\(v.replacedName ?? "nil")")
        }
        print("🔍 [过滤前] 球员数: \(players.count), 过滤后: \(filteredPlayers.count)")

        // 分离首发和替补
        let starters = filteredPlayers.filter { $0.isStarter }
        let substitutes = filteredPlayers.filter { !$0.isStarter }

        // 按 formationPlace 排序首发
        let sortedStarters = starters.sorted {
            let place1 = Int($0.formationPlace ?? "0") ?? 0
            let place2 = Int($1.formationPlace ?? "0") ?? 0
            return place1 < place2
        }

        // 构建最终结果：首发按顺序排列，替补插入到被替换者后面
        var result: [SoccerPlayerStat] = []
        var usedSubstitutes: Set<String> = []

        for starter in sortedStarters {
            result.append(starter)

            // 候选名字: 中文 player.name + 英文 originalDisplayName
            let starterNames = namesForLookup(player: starter)

            // 查找替换此首发球员的替补（通过换人映射）
            for substitute in substitutes {
                guard !usedSubstitutes.contains(substitute.name) else { continue }
                if let replacedName = findReplacedNameInMap(for: substitute.name, originalDisplayName: substitute.originalDisplayName, subMap: subMap) {
                    let cleanReplaced = replacedName.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
                    // 比较 replacedName 和 starter 的所有候选名（中文 + 英文）
                    let isMatch = starterNames.contains { cleanName in
                        cleanReplaced == cleanName
                            || cleanReplaced.contains(cleanName)
                            || cleanName.contains(cleanReplaced)
                    }
                    if isMatch {
                        result.append(substitute)
                        usedSubstitutes.insert(substitute.name)
                        break
                    }
                }
            }
        }

        // 添加未被使用的替补（按 formationPlace 排序）
        let unusedSubstitutes = substitutes.filter { !usedSubstitutes.contains($0.name) }
            .sorted {
                let place1 = Int($0.formationPlace ?? "0") ?? 0
                let place2 = Int($1.formationPlace ?? "0") ?? 0
                return place1 < place2
            }
        result.append(contentsOf: unusedSubstitutes)

        // 调试: 打印最终顺序
        print("🔍 [最终顺序] \(result.count) 人:")
        for (idx, p) in result.enumerated() {
            let marker: String = p.isStarter ? "★" : "↳"
            let subInfo = lookupSubInfo(for: p, subMap: subMap)
            let inT = subInfo?.inTime ?? ""
            let outT = subInfo?.outTime ?? ""
            var timeStr = ""
            if !outT.isEmpty { timeStr += " ⬇️\(outT)" }
            if !inT.isEmpty { timeStr += " ⬆️\(inT)" }
            print("    [\(idx)] \(marker) #\(p.number ?? 0) \(p.name) (orig=\(p.originalDisplayName ?? "nil"))\(timeStr)")
        }

        return result
    }

    // 收集球员的候选匹配名: 中文 name + 英文 originalDisplayName (去重 + 去空白)
    private func namesForLookup(player: SoccerPlayerStat) -> [String] {
        var names: [String] = []
        let cleaned = player.name.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
        if !cleaned.isEmpty { names.append(cleaned) }
        if let orig = player.originalDisplayName?.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased(), !orig.isEmpty, !names.contains(orig) {
            names.append(orig)
        }
        return names
    }

    // 在 subMap 中查找球员的换人信息(同时尝试中文 name 和英文 originalDisplayName)
    private func lookupSubInfo(for player: SoccerPlayerStat, subMap: [String: (outTime: String?, inTime: String?, replacedName: String?)]) -> (outTime: String?, inTime: String?, replacedName: String?)? {
        let names = namesForLookup(player: player)
        // 精确匹配
        for n in names {
            if let info = subMap[n] { return info }
        }
        // 模糊匹配: 任一候选名与任一 key 双向 contains
        for n in names {
            for (key, value) in subMap {
                if key.lowercased().contains(n) || n.contains(key.lowercased()) {
                    return value
                }
            }
        }
        return nil
    }

    // 在subMap中模糊查找被替换者名字（同时尝试中文名和英文名）
    private func findReplacedNameInMap(for substituteName: String, originalDisplayName: String?, subMap: [String: (outTime: String?, inTime: String?, replacedName: String?)]) -> String? {
        let names = [substituteName, originalDisplayName].compactMap { $0?.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }.filter { !$0.isEmpty }
        // 精确匹配
        for n in names {
            if let info = subMap[n], let replacedName = info.replacedName {
                return replacedName
            }
        }
        // 模糊匹配
        for n in names {
            for (key, value) in subMap {
                guard let replacedName = value.replacedName else { continue }
                if key.lowercased().contains(n.lowercased()) || n.lowercased().contains(key.lowercased()) {
                    return replacedName
                }
            }
        }
        return nil
    }

    // 在subMap中模糊查找inTime（同时尝试中文名和英文名）
    private func findInTimeInMap(playerName: String, originalDisplayName: String?, subMap: [String: (outTime: String?, inTime: String?, replacedName: String?)]) -> String? {
        let names = [playerName, originalDisplayName].compactMap { $0?.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }.filter { !$0.isEmpty }
        for n in names {
            if let info = subMap[n], let inTime = info.inTime {
                return inTime
            }
        }
        for n in names {
            for (key, value) in subMap {
                guard let inTime = value.inTime else { continue }
                if key.lowercased().contains(n.lowercased()) || n.lowercased().contains(key.lowercased()) {
                    return inTime
                }
            }
        }
        return nil
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

// MARK: - 比赛时间线视图组件 (仿 ESPN 风格)

/// 时间线主条:绿色胶囊 bar + 标签(KO/HT/FT/AET + 时间数字) + 事件图标(主队上/客队下)
/// 模仿 ESPN 网页时间线:整条绿色,标签直接贴在条上,事件图标分布于条上下
private struct TimelineBarView: View {
    let events: [SoccerKeyEvent]
    let maxMinute: Int
    let progressMinute: Int?
    let homeTeamName: String
    let awayTeamName: String
    let isHomeEvent: (SoccerKeyEvent) -> Bool
    let theme: AppTheme
    @Binding var selectedTimelineGroup: TimelineEventGroup?

    // 布局参数
    private let barHeight: CGFloat = 24       // bar 高度
    private let iconSize: CGFloat = 14        // 事件图标大小
    private let iconGap: CGFloat = 0          // bar 和图标的间距(0=紧贴)

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let barY = height / 2

            // 计算事件位置 + 同分钟分组
            let positionedEvents = computePositionedEvents(width: width)
            let groups = computeEventGroups(positionedEvents: positionedEvents)
            // 静态标签 x(用 ftX 公式,和事件位置一致)
            let ftX = computeFtX(width: width)
            // group 数字 x(贪心避让,跳过静态标签)
            let groupLabelData = computeGroupLabelData(groups: groups, width: width, ftX: ftX)

            ZStack(alignment: .topLeading) {
                // 1) Bar - 用 HStack 画,保证从 x=0 开始
                if maxMinute > 105 {
                    // 绿色段:0-90
                    let greenWidth = CGFloat(90) / CGFloat(maxMinute) * width
                    // 灰色段:90-maxMinute
                    let grayWidth = width - greenWidth
                    HStack(spacing: 0) {
                        Capsule()
                            .fill(theme.statusLive)
                            .frame(width: greenWidth, height: barHeight)
                        Capsule()
                            .fill(Color.gray.opacity(0.35))
                            .frame(width: grayWidth, height: barHeight)
                    }
                    .frame(width: width, height: barHeight, alignment: .leading)
                    .position(x: width / 2, y: barY)
                } else {
                    // 常规:整条绿色
                    Capsule()
                        .fill(theme.statusLive)
                        .frame(width: width, height: barHeight)
                        .position(x: width / 2, y: barY)
                }

                // 2) KO/HT/FT/AET 文字标签(用 ftX 公式,和事件位置一致)
                let labelEdgePad: CGFloat = 6
                BarTextLabel(text: "KO", x: labelEdgePad, barY: barY, alignment: .leading)
                BarTextLabel(text: "HT", x: 45.0 / 90.0 * ftX, barY: barY, alignment: .center)
                if maxMinute >= 90 {
                    BarTextLabel(text: "FT", x: ftX, barY: barY, alignment: .center)
                }
                if maxMinute > 105 {
                    BarTextLabel(text: "AET", x: width - labelEdgePad, barY: barY, alignment: .trailing)
                }

                // 3) 事件时间数字 - 只对 group 显示(同分钟同类型合并),激进避让
                ForEach(Array(groupLabelData.enumerated()), id: \.offset) { _, data in
                    if data.visible, let x = data.x {
                        Text(data.text)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white)
                            .position(x: x, y: barY)
                    }
                }

                // 4) 事件图标 - 直接放在父坐标系 (避免嵌套 ZStack 引起的 y 偏移 bug)
                //    TOP y=7  → 图标占 y=0~14,正好压在 bar top 上
                //    BOT y=45 → 图标占 y=38~52,正好压在 bar bottom 上
                //    点击事件直接挂在 icon 上 (14x14 精确区域),避免大透明矩形互相覆盖导致错位点击
                ForEach(groups) { group in
                    let positions = computeIconPositions(for: group, barY: barY, barHeight: barHeight, iconSize: iconSize)
                    ForEach(Array(positions.enumerated()), id: \.offset) { _, pos in
                        SingleEventIcon(event: pos.event, theme: theme)
                            .frame(width: iconSize, height: iconSize)
                            .position(x: group.x + pos.x + iconSize / 2, y: pos.y)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedTimelineGroup = group
                            }
                    }
                }

                // 5) 自定义事件详情弹窗 - 固定锚定到选中 icon 的位置(可以超出详情窗口)
                //    TOP icon → 弹窗在 icon 上方(向上延伸)
                //    BOT icon → 弹窗在 icon 下方(向下延伸)
                //    弹窗 z-order 在 icon 之下,这样点其他 icon 还能切换
                if let selected = selectedTimelineGroup,
                   let group = groups.first(where: { $0.id == selected.id }),
                   let firstEvent = group.events.first {
                    let isHome = isHomeEvent(firstEvent)
                    let iconCenterX = group.x + iconSize / 2
                    // 弹窗中心 x: 夹在 [140, width-140] 之间(避免完全超出窗口)
                    let popoverX = max(140, min(iconCenterX, width - 140))
                    // 弹窗中心 y: TOP 弹窗在 timeline 上方(y=-60 中心, 范围 -120~0)
                    //              BOT 弹窗在 timeline 下方(y=112 中心, 范围 52~172)
                    let popoverY: CGFloat = isHome ? -60 : (height + 60)
                    // 弹窗尺寸: 单事件 260x100, 多事件 +30pt/事件
                    let popoverHeight: CGFloat = 80 + CGFloat(group.events.count) * 36

                    VStack(alignment: .leading, spacing: 8) {
                        // Header
                        HStack(spacing: 6) {
                            Text("\(firstEvent.minute ?? "")'")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(theme.textPrimary)
                            if group.events.count > 1 {
                                Text("(\(group.events.count) 项)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(theme.textSecondary)
                            }
                            Spacer()
                            // 关闭按钮
                            Button(action: { selectedTimelineGroup = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(theme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        Divider()
                        // 事件列表
                        ForEach(Array(group.events.enumerated()), id: \.offset) { idx, ev in
                            HStack(spacing: 8) {
                                // 类型小图标
                                typeIconSmall(for: ev.type)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ev.player)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(theme.textPrimary)
                                        .lineLimit(1)
                                    Text(ev.team)
                                        .font(.system(size: 10))
                                        .foregroundColor(theme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            if idx < group.events.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(12)
                    .frame(width: 260)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.soccerPopoverBackground)
                            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)
                    )
                    .position(x: popoverX, y: popoverY)
                    .allowsHitTesting(true)  // 弹窗本身可以点击(关闭按钮)
                }
            }
        }
        .frame(height: 52)  // 24 bar + 14*2 icons(上 14pt + bar 24pt + 下 14pt = 52pt 紧贴)
    }

    /// 计算最大同分钟事件数,用于决定 frame 高度(目前固定 70,留作扩展)
    private func maxStackHeight(groups: [TimelineEventGroup]) -> Int {
        groups.map { $0.events.count }.max() ?? 1
    }

    /// 计算 FT 锚点 x(regulation 段右边界)
    private func computeFtX(width: CGFloat) -> CGFloat {
        if maxMinute > 105 {
            // 让 regulation 段占 0~70%,留 30% 给 AET
            return width * 0.7
        }
        return width
    }

    /// 把所有事件转换为带 x 坐标的 PositionedEvent
    private func computePositionedEvents(width: CGFloat) -> [PositionedEvent] {
        let sorted = events.sorted { parseMinute($0.minute ?? "0") < parseMinute($1.minute ?? "0") }

        // 收集 AET 段事件(只算 X 格式,X>90),用于均匀分布
        let aetMinutes = sorted
            .compactMap { $0.minute }
            .filter { isAetFormat($0) }
            .map { Int($0.replacingOccurrences(of: "'", with: "")) ?? 0 }
            .filter { $0 > 90 }
        let uniqueAet = Array(NSOrderedSet(array: aetMinutes)) as! [Int]
        let aetSorted = uniqueAet.sorted()

        let ftX = computeFtX(width: width)

        return sorted.compactMap { event in
            guard let minuteStr = event.minute, !minuteStr.isEmpty else { return nil }

            let x: CGFloat
            if isStoppageTimeFormat(minuteStr) {
                // 补时(X+Y):用 base-1 算位置(避开 FT 文字)
                let base = baseMinute(of: minuteStr)
                x = (CGFloat(base) - 1.0) / 90.0 * ftX
            } else if let m = Int(minuteStr.replacingOccurrences(of: "'", with: "")), m > 90 {
                // AET 段(X 格式,X>90):均匀分布,起点 ftX+8 终点 width-12
                let n = aetSorted.count
                if n == 0 {
                    x = ftX + 8
                } else {
                    let startX = ftX + 8
                    let endX = width - 12
                    let step = (endX - startX) / CGFloat(n + 1)
                    let idx = aetSorted.firstIndex(of: m) ?? 0
                    x = startX + step * CGFloat(idx + 1)
                }
            } else {
                // 常规 regulation:strict scaling
                let m = Int(minuteStr.replacingOccurrences(of: "'", with: "")) ?? 0
                if m == 90 {
                    // 90 严格:略偏左避开 FT 文字
                    x = ftX - 4
                } else {
                    x = CGFloat(m) / 90.0 * ftX
                }
            }

            let clampedX = max(iconSize / 2 + 2, min(width - iconSize / 2 - 2, x))
            let totalMinute = parseMinute(minuteStr)
            return PositionedEvent(event: event, xPosition: clampedX, minute: totalMinute)
        }
    }

    /// 按"同分钟 + 同类型"分组(popover 合并粒度)
    private func computeEventGroups(positionedEvents: [PositionedEvent]) -> [TimelineEventGroup] {
        // 先按 minute 分,再按 type 分子组
        let byMinute = Dictionary(grouping: positionedEvents) { $0.minute }
        var groups: [TimelineEventGroup] = []
        for (minute, eventsInMinute) in byMinute {
            let byType = Dictionary(grouping: eventsInMinute) { $0.event.type.rawValue }
            for (_, sameTypeEvents) in byType {
                let sorted = sameTypeEvents.sorted { $0.xPosition < $1.xPosition }
                let x = sorted.first?.xPosition ?? 0
                groups.append(TimelineEventGroup(minute: minute, x: x, events: sorted.map { $0.event }))
            }
        }
        return groups.sorted { $0.minute < $1.minute }
    }

    /// group 数字排布(贪心避让,跳过静态标签位置)
    /// 返回 [(text, x, visible)] - visible=false 表示该数字不渲染(避让失败)
    private func computeGroupLabelData(groups: [TimelineEventGroup], width: CGFloat, ftX: CGFloat) -> [(text: String, x: CGFloat?, visible: Bool)] {
        let charWidth: CGFloat = 5.5
        let minLabelWidth: CGFloat = 12
        let extraGap: CGFloat = 1   // 紧一点,gap 大小决定阈值松紧

        // 1) 静态标签占位区间(中心 x,半宽)
        var staticReservations: [(center: CGFloat, halfWidth: CGFloat)] = [
            (center: 6,  halfWidth: 10),  // KO(左对齐,实际左边缘在 x=0)
            (center: 45.0 / 90.0 * ftX, halfWidth: 8),  // HT
        ]
        if maxMinute >= 90 {
            staticReservations.append((center: ftX, halfWidth: 8))  // FT
        }
        if maxMinute > 105 {
            staticReservations.append((center: width - 6, halfWidth: 12))  // AET
        }

        // 2) 给每个 group 算 label 区间
        struct Slot { let text: String; let naturalX: CGFloat; let halfWidth: CGFloat }
        let slots: [Slot] = groups.map { group in
            let firstEvent = group.events.first
            let rawMinute = firstEvent?.minute ?? ""
            // 优先显示原始字符串("90+6" 而不是 "96"),这样视觉上更准
            let text = rawMinute.isEmpty ? "\(group.minute)" : rawMinute
                .replacingOccurrences(of: "'", with: "")
            let halfWidth = max(minLabelWidth / 2, CGFloat(text.count) * charWidth / 2)
            return Slot(text: text, naturalX: group.x, halfWidth: halfWidth)
        }

        // 3) 贪心避让:从左到右,跳过静态标签,冲突就隐藏
        var result: [(text: String, x: CGFloat?, visible: Bool)] = []
        var lastRightEdge: CGFloat = 0

        for (idx, slot) in slots.enumerated() {
            var x = slot.naturalX

            // 检查是否和静态标签冲突(无法通过避让解决,直接隐藏)
            var conflictsStatic = false
            for res in staticReservations {
                let leftDist = abs(x - res.center)
                if leftDist < slot.halfWidth + res.halfWidth + extraGap {
                    conflictsStatic = true
                    break
                }
            }
            if conflictsStatic {
                result.append((text: slot.text, x: nil, visible: false))
                continue
            }

            // 检查是否和前面已显示数字冲突
            let labelLeft = x - slot.halfWidth
            if idx > 0 && labelLeft < lastRightEdge + extraGap {
                // 尝试右移
                let newLeft = lastRightEdge + extraGap
                let newX = newLeft + slot.halfWidth
                // 右移后是否还在 bar 内、是否撞到静态标签
                if newX + slot.halfWidth > width - 4 {
                    result.append((text: slot.text, x: nil, visible: false))
                    continue
                }
                var hitStatic = false
                for res in staticReservations {
                    if abs(newX - res.center) < slot.halfWidth + res.halfWidth + extraGap {
                        hitStatic = true
                        break
                    }
                }
                if hitStatic {
                    result.append((text: slot.text, x: nil, visible: false))
                    continue
                }
                x = newX
            }

            // clamp 到 bar 内
            x = max(slot.halfWidth + 2, min(width - slot.halfWidth - 2, x))

            result.append((text: slot.text, x: x, visible: true))
            lastRightEdge = x + slot.halfWidth
        }

        return result
    }

    /// 判断 minute 字符串是否是 "X+Y" 补时格式
    private func isStoppageTimeFormat(_ minute: String) -> Bool {
        minute.replacingOccurrences(of: "'", with: "").contains("+")
    }

    /// 判断 minute 字符串是否是纯 "X" 格式(无 +)
    private func isAetFormat(_ minute: String) -> Bool {
        !isStoppageTimeFormat(minute)
    }

    /// "90+6" -> 90
    private func baseMinute(of minute: String) -> Int {
        let cleaned = minute.replacingOccurrences(of: "'", with: "")
        if let plusIdx = cleaned.firstIndex(of: "+") {
            return Int(cleaned[..<plusIdx]) ?? 0
        }
        return Int(cleaned) ?? 0
    }

    private func cleanMinuteForDisplay(_ minute: String) -> String {
        minute.replacingOccurrences(of: "'", with: "")
    }

    private func parseMinute(_ minute: String) -> Int {
        let cleaned = minute.replacingOccurrences(of: "'", with: "")
        if cleaned.contains("+") {
            let parts = cleaned.split(separator: "+")
            return (Int(parts[0]) ?? 0) + (Int(parts[1]) ?? 0)
        }
        return Int(cleaned) ?? 0
    }

    fileprivate struct PositionedEvent {
        let event: SoccerKeyEvent
        let xPosition: CGFloat
        let minute: Int
    }

    /// 计算组内每个事件的图标位置
    /// - 1 个事件:home 在条上,away 在条下(紧贴 bar 边缘)
    /// - 2+ 个事件:home 横向并排在条上,away 横向并排在条下
    ///   (不再纵向堆叠,保持 frame 高度固定 = bar + 1 行图标)
    private func computeIconPositions(
        for group: TimelineEventGroup,
        barY: CGFloat,
        barHeight: CGFloat,
        iconSize: CGFloat
    ) -> [IconPosition] {
        // 紧贴 bar 上下边缘(0 gap),让事件图标和时间线看起来是一体的
        let topEdgeY = barY - barHeight / 2 - iconSize / 2
        let bottomEdgeY = barY + barHeight / 2 + iconSize / 2
        let xSpacing: CGFloat = iconSize + 1  // 横向并排间距

        if group.events.count == 1 {
            let e = group.events[0]
            let y = isHomeEvent(e) ? topEdgeY : bottomEdgeY
            return [IconPosition(event: e, x: 0, y: y)]
        }

        // 2+ 事件:home 横向并排在条上,away 横向并排在条下
        let homeEvents = group.events.filter { isHomeEvent($0) }
        let awayEvents = group.events.filter { !isHomeEvent($0) }

        var positions: [IconPosition] = []
        // home 横向居中并排
        for (i, e) in homeEvents.enumerated() {
            let offsetX = (CGFloat(i) - CGFloat(homeEvents.count - 1) / 2) * xSpacing
            positions.append(IconPosition(event: e, x: offsetX, y: topEdgeY))
        }
        // away 横向居中并排
        for (i, e) in awayEvents.enumerated() {
            let offsetX = (CGFloat(i) - CGFloat(awayEvents.count - 1) / 2) * xSpacing
            positions.append(IconPosition(event: e, x: offsetX, y: bottomEdgeY))
        }
        return positions
    }

    private struct IconPosition {
        let event: SoccerKeyEvent
        let x: CGFloat  // 相对 group.x 的横向偏移
        let y: CGFloat
    }

    /// 弹窗内事件类型小图标(足球/换人/黄红牌)
    @ViewBuilder
    private func typeIconSmall(for type: EventType) -> some View {
        switch type {
        case .goal:
            Image(systemName: "soccerball")
                .font(.system(size: 12))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.green))
        case .substitution:
            VStack(spacing: -3) {
                Image(systemName: "arrow.up").font(.system(size: 7, weight: .bold))
                Image(systemName: "arrow.down").font(.system(size: 7, weight: .bold))
            }
            .foregroundColor(theme.textPrimary)
            .frame(width: 20, height: 20)
        case .yellowCard:
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.yellow)
                .frame(width: 8, height: 12)
                .frame(width: 20, height: 20)
        case .redCard:
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.red)
                .frame(width: 8, height: 12)
                .frame(width: 20, height: 20)
        default:
            EmptyView()
        }
    }
}

/// 时间线"同分钟同类型"事件分组(用于堆叠图标 + 合并 popover)
struct TimelineEventGroup: Identifiable {
    let minute: Int
    let x: CGFloat
    let events: [SoccerKeyEvent]
    var id: String { "\(minute)-\(events.first?.type.rawValue ?? "")-\(events.count)" }
}

/// 条内普通文字标签 (KO/FT/AET 风格:白字直接贴绿条)
/// x 是中心位置,alignment 决定 x 的偏移方式
private struct BarTextLabel: View {
    let text: String
    let x: CGFloat  // 中心位置(由调用方用 ftX 公式算出,和事件位置一致)
    let barY: CGFloat
    enum Alignment { case leading, center, trailing }
    let alignment: Alignment

    /// 估算标签宽度(粗略,9pt 字号 + 3pt*2 padding)
    private var labelWidth: CGFloat {
        CGFloat(text.count) * 5.5 + 6
    }

    var body: some View {
        let centerX: CGFloat = {
            switch alignment {
            case .leading:  return x + labelWidth / 2
            case .center:   return x
            case .trailing: return x - labelWidth / 2
            }
        }()
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 3)
            .position(x: centerX, y: barY)
    }
}

/// 时间线事件图标(ESPN 风格:小、扁平)
private struct SingleEventIcon: View {
    let event: SoccerKeyEvent
    let theme: AppTheme

    var body: some View {
        iconView
    }

    @ViewBuilder
    private var iconView: some View {
        switch event.type {
        case .goal:
            // 进球:⚽ 黑白足球
            Image(systemName: "soccerball")
                .font(.system(size: 12))
                .foregroundColor(.black)
        case .substitution:
            // 换人:↑↓ 并排(细箭头)
            HStack(spacing: 1) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 7, weight: .bold))
                Image(systemName: "arrow.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundColor(theme.textPrimary)
        case .yellowCard:
            // 黄牌:小黄方块
            RoundedRectangle(cornerRadius: 1)
                .fill(Color(red: 1.0, green: 0.85, blue: 0.2))
                .frame(width: 6, height: 9)
        case .redCard:
            // 红牌:小红方块
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.red)
                .frame(width: 6, height: 9)
        default:
            EmptyView()
        }
    }
}

/// 时间线事件详情弹窗(支持同分钟同类型的多个事件,divider 分隔)
private struct TimelineEventDetailPopover: View {
    let group: TimelineEventGroup
    let theme: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header:用第一个事件的分钟/类型作总体标识
            if let first = group.events.first {
                HStack(spacing: 6) {
                    headerIcon(for: first.type)
                    Text("\(first.minute ?? "")'")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(theme.textPrimary)
                    if group.events.count > 1 {
                        Text("(\(group.events.count) 项)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(theme.textSecondary)
                    }
                }
            }

            Divider()

            // Details:每个事件一张卡
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(group.events.enumerated()), id: \.offset) { idx, event in
                    EventCard(event: event, theme: theme)
                    if idx < group.events.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func headerIcon(for type: EventType) -> some View {
        switch type {
        case .goal:
            Image(systemName: "soccerball")
                .font(.system(size: 14))
                .foregroundColor(.white)
                .padding(3)
                .background(Circle().fill(Color.green))
        case .substitution:
            VStack(spacing: -2) {
                Image(systemName: "arrow.up").font(.system(size: 8, weight: .bold))
                Image(systemName: "arrow.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(theme.textPrimary)
        case .yellowCard:
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.yellow)
                .frame(width: 8, height: 12)
        case .redCard:
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.red)
                .frame(width: 8, height: 12)
        default:
            EmptyView()
        }
    }
}

/// 单个事件的卡(被 TimelineEventDetailPopover 用 ForEach 渲染)
private struct EventCard: View {
    let event: SoccerKeyEvent
    let theme: AppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 队名行
            HStack(spacing: 4) {
                Text(event.team)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)
            }

            switch event.type {
            case .goal:
                HStack(spacing: 4) {
                    Text("⚽")
                        .font(.system(size: 11))
                    Text("进球")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.textSecondary)
                    Text(event.player)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                }
            case .substitution:
                if let parsed = parseSubstitution(event) {
                    HStack(spacing: 4) {
                        Text("⬆")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                        Text(parsed.on)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(theme.textPrimary)
                    }
                    HStack(spacing: 4) {
                        Text("⬇")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                        Text(parsed.off)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(theme.textPrimary)
                    }
                } else if !event.player.isEmpty {
                    Text(event.player)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                } else {
                    Text("换人")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textPrimary)
                }
            case .yellowCard:
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.yellow)
                        .frame(width: 7, height: 10)
                    Text("黄牌")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.textSecondary)
                    Text(event.player)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                }
            case .redCard:
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.red)
                        .frame(width: 7, height: 10)
                    Text("红牌")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.textSecondary)
                    Text(event.player)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                }
            default:
                Text(event.player)
                    .font(.system(size: 12))
                    .foregroundColor(theme.textPrimary)
            }
        }
    }

    private func parseSubstitution(_ event: SoccerKeyEvent) -> (on: String, off: String)? {
        guard let info = event.additionalInfo else { return nil }
        let pattern = "Substitution, .+?\\. (.+?) replaces (.+)\\.?$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: info, options: [], range: NSRange(info.startIndex..., in: info)),
              let inRange = Range(match.range(at: 1), in: info),
              let outRange = Range(match.range(at: 2), in: info) else {
            return nil
        }
        var onPlayer = String(info[inRange]).trimmingCharacters(in: .whitespaces)
        var offPlayer = String(info[outRange]).trimmingCharacters(in: .whitespaces)
        if onPlayer.hasSuffix(".") { onPlayer = String(onPlayer.dropLast()) }
        if offPlayer.hasSuffix(".") { offPlayer = String(offPlayer.dropLast()) }
        return (onPlayer, offPlayer)
    }
}

// MARK: - 阵容球员行
struct LineupPlayerRow: View {
    let player: SoccerPlayerStat
    var theme: AppTheme = ThemeManager.current
    let isHome: Bool
    var keyEvents: [SoccerKeyEvent] = []  // 关键事件（用于显示时间）
    var substitutionMap: [String: (outTime: String?, inTime: String?, replacedName: String?)] = [:]  // 换人时间映射

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

    // 是否被换下（首发球员且在换人事件中被替换）
    private var isSubstitutedOut: Bool {
        guard player.isStarter else { return false }
        return findSubstitutionInfo(for: player.name)?.outTime != nil
    }

    // 下场时间（如果被换下）
    private var outTime: String? {
        findSubstitutionInfo(for: player.name)?.outTime
    }

    // 上场时间（如果是替补）
    private var inTime: String? {
        guard !player.isStarter else { return nil }
        return findSubstitutionInfo(for: player.name)?.inTime
    }

    // 查找球员的换人信息（使用模糊匹配，同时尝试中文名和英文名）
    private func findSubstitutionInfo(for playerName: String) -> (outTime: String?, inTime: String?, replacedName: String?)? {
        let names = [playerName, player.originalDisplayName].compactMap { $0?.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }.filter { !$0.isEmpty }
        // 精确匹配
        for n in names {
            if let info = substitutionMap[n] { return info }
        }
        // 模糊匹配
        for n in names {
            for (key, value) in substitutionMap {
                if key.lowercased().contains(n.lowercased()) || n.lowercased().contains(key.lowercased()) {
                    return value
                }
            }
        }
        return nil
    }

    var body: some View {
        // 调试: 追踪 1号/3号/12号 渲染时的状态
        let n = player.number ?? 0
        let isRayaOrMosquera = (n == 1 || n == 3 || n == 12) && (player.name.contains("Raya") || player.name.contains("Mosquera") || player.name.contains("Timber"))
        if isRayaOrMosquera {
            print("🎨 [LineupPlayerRow] #\(n) \(player.name) | isStarter=\(player.isStarter) | hasGoal=\(player.hasGoal) goalTimes=\(goalTimes) | hasYellow=\(player.hasYellowCard) yellowTimes=\(yellowCardTimes) | hasRed=\(player.hasRedCard) redTimes=\(redCardTimes) | isSubOut=\(isSubstitutedOut) outTime=\(outTime ?? "nil") inTime=\(inTime ?? "nil")")
        }
        return HStack(spacing: 4) {
            // 球衣号
            Text("\(player.number ?? 0)")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(theme.textSecondary)
                .frame(width: 16, alignment: .center)

            // 球员名和箭头（箭头在名字后边）
            HStack(spacing: 2) {
                Text(player.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(player.isStarter ? theme.textPrimary : theme.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 80, alignment: .leading)

                // 被换下的首发显示⬇️ + 下场时间（时间不为"0"才显示）
                if isSubstitutedOut, let time = outTime, time != "0" {
                    Text("⬇️\(time)")
                        .font(.system(size: 8, weight: .medium))
                }
                // 替补显示⬆️ + 上场时间（时间不为"0"才显示）
                else if !player.isStarter, let time = inTime, time != "0" {
                    Text("⬆️\(time)")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(theme.accentColor)
                }
            }

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

// MARK: - 事件时间线行（统一展示所有事件）
struct EventTimelineRow: View {
    let event: SoccerKeyEvent
    var theme: AppTheme = ThemeManager.current

    var body: some View {
        HStack(spacing: 8) {
            // 时间
            Text(event.minute ?? "")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(theme.accentColor)
                .frame(width: 40, alignment: .leading)

            // 事件图标
            eventIcon
                .frame(width: 20)

            // 球员名和事件描述
            VStack(alignment: .leading, spacing: 1) {
                Text(event.player)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(theme.textPrimary)

                if let info = event.additionalInfo, !info.isEmpty {
                    Text(info)
                        .font(.system(size: 8))
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 球队标识
            Text(event.team)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(theme.textSecondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(theme.cardBackground)
                .cornerRadius(3)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(eventBackgroundColor.opacity(0.3))
        .cornerRadius(4)
    }

    @ViewBuilder
    private var eventIcon: some View {
        switch event.type {
        case .goal:
            Image(systemName: "soccerball")
                .font(.system(size: 10))
                .foregroundColor(.orange)
        case .yellowCard, .yellowcard:
            Rectangle()
                .fill(Color.yellow)
                .frame(width: 8, height: 10)
                .cornerRadius(1)
        case .redCard, .redcard:
            Rectangle()
                .fill(Color.red)
                .frame(width: 8, height: 10)
                .cornerRadius(1)
        case .substitution:
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 10))
                .foregroundColor(theme.accentColor)
        }
    }

    private var eventBackgroundColor: Color {
        switch event.type {
        case .goal: return .orange
        case .yellowCard, .yellowcard: return .yellow
        case .redCard, .redcard: return .red
        case .substitution: return theme.accentColor
        }
    }
}

// MARK: - 换人事件行（已废弃，用 EventTimelineRow 代替）
struct SubstitutionRow: View {
    let event: SoccerKeyEvent
    var theme: AppTheme = ThemeManager.current

    var body: some View {
        HStack(spacing: 8) {
            Text(event.minute ?? "")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(theme.accentColor)
                .frame(width: 35, alignment: .leading)

            Text(event.team)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(theme.textSecondary)
                .frame(width: 30, alignment: .center)

            if let text = event.additionalInfo {
                Text(text)
                    .font(.system(size: 9))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(2)
            } else {
                Text(event.player)
                    .font(.system(size: 9))
                    .foregroundColor(theme.textPrimary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 进球事件行（已废弃，用 EventTimelineRow 代替）
struct GoalRow: View {
    let event: SoccerKeyEvent
    var theme: AppTheme = ThemeManager.current

    var body: some View {
        HStack(spacing: 8) {
            Text(event.minute ?? "")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.orange)
                .frame(width: 35, alignment: .leading)

            Text(event.team)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(theme.textSecondary)
                .frame(width: 30, alignment: .center)

            Text(event.player)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(theme.textPrimary)

            Spacer()

            if let info = event.additionalInfo, info.contains("Penalty") {
                Text("点球")
                    .font(.system(size: 8))
                    .foregroundColor(theme.textSecondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(theme.cardBackground)
                    .cornerRadius(3)
            }
        }
        .padding(.vertical, 2)
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
    var customLabel: String? = nil  // 可选的自定义标签

    var body: some View {
        VStack(spacing: 4) {
            // Labels
            HStack {
                Text(stat.homeDisplay)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(theme.soccerStatBarHome)
                Spacer()
                Text(customLabel ?? soccerStatTranslation[stat.label] ?? stat.label)
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

