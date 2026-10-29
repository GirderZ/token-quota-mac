import Cocoa
import SwiftUI
import ServiceManagement

// 参考 ChatGPT 的黑白灰层级；保持 macOS 原生系统字体与交互。
// 动态颜色随 macOS 外观切换；系统菜单继续使用原生外观。
enum Palette {
    static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    static func adaptiveNS(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            rgb(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        }
    }
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: adaptiveNS(light, dark))
    }
    static let accent = adaptive(0x0D0D0D, 0xFFFFFF)
    static let surface = adaptive(0xFFFFFF, 0x212121)
    static let card = adaptive(0xF7F7F8, 0x2F2F2F)
    static let ink = adaptive(0x0D0D0D, 0xECECEC)
    static let secondary = adaptive(0x676767, 0xB4B4B4)
    static let track = adaptive(0xE5E5E5, 0x484848)
    static let border = adaptive(0xE5E5E5, 0x424242)
    static let successNS = adaptiveNS(0x078565, 0x42C99A)
    static let warningNS = adaptiveNS(0x9A6B00, 0xF3C752)
    static let dangerNS = adaptiveNS(0xC83E3E, 0xF47C7C)
    static let success = Color(nsColor: successNS)
    static let active = Color(nsColor: rgb(0x10A37F))
    static let warning = Color(nsColor: warningNS)
    static let danger = Color(nsColor: dangerNS)
}

struct TokenSymbol: Shape {
    func path(in rect: CGRect) -> Path { Path(TokenGlyphGeometry.path(in: TokenGlyphGeometry.glyphRect(in: rect))) }
}
struct TokenMark: View {
    var body: some View {
        Circle().fill(Palette.ink)
            .overlay {
                TokenSymbol().fill(.black).blendMode(.destinationOut)
            }
            .compositingGroup()
            .frame(width: 30, height: 30).accessibilityHidden(true)
    }
}

func quotaNSColor(_ remaining: Double?) -> NSColor {
    switch QuotaLevel.classify(remaining) {
    case .critical: return Palette.dangerNS
    case .warning: return Palette.warningNS
    case .healthy: return Palette.successNS
    case .unknown: return Palette.adaptiveNS(0x676767, 0xB4B4B4)
    }
}
func quotaColor(_ remaining: Double?) -> Color { Color(nsColor: quotaNSColor(remaining)) }
final class BadgeModel: ObservableObject {
    @Published var showCredits = false
    @Published var loginStatus = SMAppService.mainApp.status
    @Published var loginBusy = false
    var loginEnabled: Bool { loginStatus == .enabled }
    var loginStatusText: String {
        switch loginStatus {
        case .enabled: return "已开启"
        case .notRegistered: return "已关闭"
        case .requiresApproval: return "待系统允许"
        case .notFound: return "当前不可用"
        @unknown default: return "状态未知"
        }
    }
    func refreshLoginStatus() {
        let actual = SMAppService.mainApp.status
        if loginStatus != actual { loginStatus = actual }
    }
    @Published var snapshot: Snapshot?
    @Published var error: String?
    @Published var loading = false
    @Published var now = Date()
    @Published var pinned = UserDefaults.standard.object(forKey: "pinned") as? Bool ?? true
    @Published var theme = UserDefaults.standard.string(forKey: "theme") ?? "system"
    @Published var floating = UserDefaults.standard.object(forKey: "floating") as? Bool ?? true
    @Published var followHost = UserDefaults.standard.bool(forKey: "followHost")
    let client = QuotaClient()
    let worker = DispatchQueue(label: "local.codexbadge.quota", qos: .utility)
    var onUpdate: (() -> Void)?
    var stale: Bool { error != nil || (snapshot.map { now.timeIntervalSince($0.fetchedAt) > 180 } ?? true) }
    var displayMain: QuotaWindow? { snapshot?.main }
    var status: String {
        if loading { return "正在同步" }
        if snapshot == nil { return "等待连接" }
        if stale { return "旧读数 · 待同步" }
        return "已同步"
    }
    func refresh() {
        guard !loading else { return }
        loading = true
        worker.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.client.fetch() }
            DispatchQueue.main.async {
                self.loading = false
                switch result {
                case .success(let snapshot): self.snapshot = snapshot; self.error = nil
                case .failure(let error): self.error = error.localizedDescription
                }
                self.now = Date(); self.onUpdate?()
            }
        }
    }
    func save() {
        let defaults = UserDefaults.standard
        defaults.set(pinned, forKey: "pinned"); defaults.set(theme, forKey: "theme")
        defaults.set(floating, forKey: "floating"); defaults.set(followHost, forKey: "followHost")
        onUpdate?()
    }
}

struct PanelBackground: View {
    var body: some View {
        Palette.surface
    }
}
struct CapsuleView: View {
    @ObservedObject var model: BadgeModel
    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().stroke(Palette.track, lineWidth: 3)
                Circle().trim(from: 0, to: (model.displayMain?.remaining ?? 0) / 100)
                    .stroke(quotaColor(model.displayMain?.remaining), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }.frame(width: 19, height: 19)
            Text(model.displayMain?.percent ?? "—%")
                .font(.system(size: 17, weight: .semibold)).monospacedDigit()
                .foregroundStyle(quotaColor(model.displayMain?.remaining))
            if model.stale {
                Circle().fill(Palette.warning).frame(width: 5, height: 5).accessibilityLabel("尚未同步")
            }
        }
        .foregroundStyle(Palette.ink)
        .tint(Palette.active)
        .frame(width: 126, height: 42)
        .background(PanelBackground()).clipShape(Capsule())
        .overlay(Capsule().stroke(Palette.border.opacity(0.8), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codex \(model.displayMain?.label ?? "额度")剩余 \(model.displayMain?.percent ?? "未知")，\(model.status)")
        .help("悬停查看详情 · 拖动调整位置 · 右键设置")
    }
}
struct WindowRow: View {
    let window: QuotaWindow
    let now: Date
    var resetText: String {
        guard let date = window.resetsAt else { return "重置时间暂不可用" }
        if date <= now { return "已到重置时间，等待同步" }
        let delta = Int(date.timeIntervalSince(now))
        let relative: String
        if delta >= 86400 { relative = "\(delta / 86400) 天 \((delta % 86400) / 3600) 小时后" }
        else if delta >= 3600 { relative = "\(delta / 3600) 小时 \((delta % 3600) / 60) 分钟后" }
        else { relative = "\(max(1, delta / 60)) 分钟后" }
        return relative + "重置"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label + "剩余").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.secondary)
                Spacer()
                Text(window.percent).font(.system(size: 31, weight: .semibold)).monospacedDigit().foregroundStyle(quotaColor(window.remaining))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.track)
                    Capsule().fill(quotaColor(window.remaining)).frame(width: max(0, geo.size.width * window.remaining / 100))
                }
            }.frame(height: 6).accessibilityLabel("剩余 \(window.percent)")
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "clock").font(.system(size: 10))
                    Text(resetText).font(.system(size: 11))
                }
                if let date = window.resetsAt {
                    Text(window.minutes == 300 ? QuotaDates.shortReset(date, relativeTo: now) : QuotaDates.timestamp(date))
                        .font(.system(size: 10)).monospacedDigit()
                }
            }.foregroundStyle(Palette.secondary)
        }.padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }
}
struct DetailView: View {
    @ObservedObject var model: BadgeModel
    let delegate: AppDelegate
    private func badgeWidth(_ plan: String) -> CGFloat {
        let measured = (plan as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 8, weight: .semibold), .kern: 0.5
        ]).width
        return min(80, ceil(measured) + 16)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 8) {
                TokenMark()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Token额度").font(.system(size: 17, weight: .semibold)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    Text("ChatGPT用量").font(.system(size: 10)).foregroundStyle(Palette.secondary).lineLimit(1)
                }.frame(width: 102, alignment: .leading)
                Spacer(minLength: 0)
                if let plan = model.snapshot?.planLabel {
                    Text(plan).font(.system(size: 8, weight: .semibold)).tracking(0.5)
                        .lineLimit(1).truncationMode(.middle).help(plan)
                        .foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Palette.card, in: Capsule()).frame(width: badgeWidth(plan))
                }
                Button { model.pinned.toggle(); model.save() } label: {
                    Image(systemName: model.pinned ? "pin.fill" : "pin").foregroundStyle(model.pinned ? Palette.success : Palette.secondary)
                }.buttonStyle(.plain).frame(width: 26, height: 28).help("窗口置顶").accessibilityLabel("窗口置顶").accessibilityValue(model.pinned ? "已开启" : "已关闭")
                Menu {
                    Button("立即刷新") { model.refresh() }
                    Toggle("显示悬浮胶囊", isOn: Binding(get: { model.floating }, set: { model.floating = $0; model.save() }))
                    Toggle("仅在 Codex / ChatGPT 运行时显示", isOn: Binding(get: { model.followHost }, set: { model.followHost = $0; model.save() }))
                    Divider()
                    ForEach([("system", "跟随系统"), ("light", "浅色"), ("dark", "深色")], id: \.0) { theme in
                        Button((model.theme == theme.0 ? "✓ " : "") + theme.1) { model.theme = theme.0; model.save() }
                    }
                    Divider()
                    Toggle("登录时启动 · " + model.loginStatusText, isOn: Binding(
                        get: { model.loginEnabled }, set: { delegate.setLoginEnabled($0) }
                    )).disabled(model.loginBusy || model.loginStatus == .notFound)
                    if model.loginStatus == .requiresApproval {
                        Button("前往系统设置允许…") { SMAppService.openSystemSettingsLoginItems() }
                        Button("取消登录启动申请") { delegate.setLoginEnabled(false) }
                    }
                    Button("恢复默认位置") { delegate.resetPosition() }
                    Button("关于Token额度") { delegate.showAbout() }
                    Divider()
                    Button("退出Token额度") { NSApp.terminate(nil) }
                } label: { Image(systemName: "ellipsis").frame(width: 20, height: 26) }
                .menuStyle(.borderlessButton).fixedSize().help("设置")
            }
            if let snapshot = model.snapshot, !snapshot.windows.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { _, window in
                        WindowRow(window: window, now: model.now)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: model.loading ? "arrow.triangle.2.circlepath" : "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 28)).foregroundStyle(Palette.secondary)
                    Text(model.loading ? "正在连接 Codex" : "暂无可显示的额度").font(.system(size: 14, weight: .medium))
                    Text("打开已登录的 Codex 或 ChatGPT，\n然后刷新额度。")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                    Button("打开 Codex / ChatGPT") { delegate.openHost() }.buttonStyle(.bordered)
                }.frame(maxWidth: .infinity).padding(.vertical, 22)
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(Palette.warning).fixedSize(horizontal: false, vertical: true)
            }
            if model.error != nil && model.snapshot != nil {
                Text("当前显示上次成功同步的读数").font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("重置机会", systemImage: "arrow.counterclockwise").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    Spacer()
                    Text(model.snapshot?.resetCount.map { "\($0) 次" } ?? "未知").font(.system(size: 12, weight: .medium))
                        .foregroundStyle((model.snapshot?.resetCount ?? 0) > 0 ? Palette.success : Palette.ink)
                    if !(model.snapshot?.expiries.isEmpty ?? true) {
                        Button { model.showCredits.toggle(); delegate.resizeDetails(); delegate.positionDetails() } label: { Image(systemName: model.showCredits ? "chevron.up" : "chevron.down") }
                            .buttonStyle(.plain).accessibilityLabel("查看重置机会到期时间")
                    }
                }.padding(.horizontal, 3)
                Text("可提前恢复额度次数")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 3)
            }
            if model.showCredits, let snapshot = model.snapshot {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(snapshot.expiries.enumerated()), id: \.offset) { index, date in
                        Text("第 \(index + 1) 次 · \(QuotaDates.timestamp(date, includeYear: true)) 到期")
                    }
                }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Circle().fill(model.loading ? Palette.secondary : model.stale ? Palette.warning : Palette.success).frame(width: 5, height: 5)
                    Text(model.status).font(.system(size: 10)).foregroundStyle(model.loading ? Palette.secondary : model.stale ? Palette.warning : Palette.success)
                    Spacer()
                    Button { model.refresh() } label: {
                        Label("刷新", systemImage: "arrow.clockwise").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.secondary)
                    }.buttonStyle(.plain).disabled(model.loading).keyboardShortcut("r")
                }
                Text(QuotaDates.lastSync(model.snapshot?.fetchedAt, relativeTo: model.now))
                    .font(.system(size: 10)).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }.foregroundStyle(Palette.secondary)
        }
        .foregroundStyle(Palette.ink)
        .tint(Palette.active)
        .padding(20).frame(width: 342)
        .background(PanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.border.opacity(0.8), lineWidth: 1))
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
final class CapsuleHost: NSHostingView<CapsuleView> {
    weak var controller: AppDelegate?
    private var tracking: NSTrackingArea?
    private var dragOrigin: NSPoint?
    private var originalOrigin: NSPoint?
    private var dragged = false
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { controller?.hoverCapsule() }
    override func mouseExited(with event: NSEvent) { controller?.scheduleHide() }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { controller?.resetPosition(); return }
        dragOrigin = NSEvent.mouseLocation; originalOrigin = window?.frame.origin; dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragOrigin, let origin = originalOrigin else { return }
        let current = NSEvent.mouseLocation
        let delta = NSPoint(x: current.x - start.x, y: current.y - start.y)
        if abs(delta.x) + abs(delta.y) > 3 {
            dragged = true; controller?.hideDetails()
            window?.setFrameOrigin(NSPoint(x: origin.x + delta.x, y: origin.y + delta.y))
        }
    }
    override func mouseUp(with event: NSEvent) {
        if dragged { controller?.savePosition() }
        else if event.clickCount == 1 { controller?.toggleDetailsFromCapsule() }
        dragOrigin = nil
    }
    override func rightMouseDown(with event: NSEvent) {
        guard let controller else { return }
        NSMenu.popUpContextMenu(controller.contextMenu(), with: event, for: self)
    }
    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > 1 else { return }
        controller?.cycleTheme()
    }
    override func accessibilityPerformPress() -> Bool { controller?.toggleDetailsFromCapsule(); return true }
}
final class DetailHost: NSHostingView<DetailView> {
    weak var controller: AppDelegate?
    var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { controller?.cancelHide() }
    override func mouseExited(with event: NSEvent) { controller?.scheduleHide() }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = BadgeModel()
    var statusItem: NSStatusItem!
    var capsule: FloatingPanel!
    var details: FloatingPanel!
    var detailHost: DetailHost!
    var holdDetails = false
    var detailsFromMenu = false
    var hideWork: DispatchWorkItem?
    var lastThemeChange = Date.distantPast
    var timer: Timer?
    var tick: Timer?
    var eventMonitor: Any?
    var localMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.henry.CodexBadge")
        if others.count > 1 {
            others.first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })?.activate()
            NSApp.terminate(nil); return
        }
        NSApp.setActivationPolicy(.accessory)
        let mainMenu = NSMenu()
        let applicationMenu = NSMenu()
        let applicationItem = NSMenuItem()
        applicationItem.submenu = applicationMenu
        let quitItem = NSMenuItem(title: "退出Token额度", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self; applicationMenu.addItem(quitItem)
        mainMenu.addItem(applicationItem); NSApp.mainMenu = mainMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self; statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        capsule = makePanel(size: NSSize(width: 126, height: 42))
        let host = CapsuleHost(rootView: CapsuleView(model: model)); host.controller = self
        capsule.contentView = host
        details = makePanel(size: NSSize(width: 342, height: 390))
        detailHost = DetailHost(rootView: DetailView(model: model, delegate: self)); detailHost.controller = self
        details.contentView = detailHost
        if let saved = UserDefaults.standard.string(forKey: "position") {
            capsule.setFrameOrigin(NSPointFromString(saved)); clampPosition()
        } else { resetPosition() }
        model.onUpdate = { [weak self] in self?.update() }
        if CommandLine.arguments.contains("--light") { model.theme = "light" }
        if CommandLine.arguments.contains("--dark") { model.theme = "dark" }
        update(); model.refresh()
        if CommandLine.arguments.contains("--show-details") {
            DispatchQueue.main.async { self.showDetails(fromMenu: false, hold: true) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.model.refresh() }
        tick = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.model.now = Date(); self?.model.refreshLoginStatus(); self?.update()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(activated), name: NSApplication.didBecomeActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            if !self.details.frame.contains(NSEvent.mouseLocation) && !self.capsule.frame.contains(NSEvent.mouseLocation) { self.hideDetails() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.hideDetails(); return nil }; return event
        }
    }
    func makePanel(size: NSSize) -> FloatingPanel {
        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = .floating
        return panel
    }
    func menuSymbol() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            TokenGlyphGeometry.drawBadge(in: context, rect: rect.insetBy(dx: 0.5, dy: 0.5), color: NSColor.black.cgColor)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Token额度"
        return image
    }
    func update() {
        guard capsule != nil else { return }
        let theme = model.theme == "dark" ? NSAppearance(named: .darkAqua) : model.theme == "light" ? NSAppearance(named: .aqua) : nil
        capsule.appearance = theme; details.appearance = theme
        capsule.level = model.pinned ? .floating : .normal; details.level = model.pinned ? .floating : .normal
        let hostRunning = NSWorkspace.shared.runningApplications.contains { app in
            let name = app.localizedName ?? ""
            return name == "Codex" || name == "ChatGPT"
        }
        if model.floating && (!model.followHost || hostRunning) { capsule.orderFrontRegardless() }
        else { capsule.orderOut(nil); if !detailsFromMenu { hideDetails() } }
        let prefix = model.stale ? "◦ " : ""
        // 原生标题自动随菜单栏外观反白；用四分字空格给图标和数字保留适量间距。
        statusItem.button?.title = "\u{2005}" + prefix + (model.displayMain?.percent ?? "—%") + "\u{2005}"
        statusItem.button?.image = menuSymbol()
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.toolTip = "Token额度 · \(model.displayMain?.label ?? "Codex")剩余 · \(model.status)"
        if details.isVisible { resizeDetails(); positionDetails() }
    }
    func resizeDetails() {
        let fitting = detailHost.fittingSize
        details.setContentSize(NSSize(width: 342, height: max(240, fitting.height)))
    }
    func positionDetails() {
        let anchor = detailsFromMenu ? statusAnchor() : capsule.frame
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var x = anchor.maxX - details.frame.width
        x = min(max(x, visible.minX + 8), visible.maxX - details.frame.width - 8)
        var y = anchor.minY - details.frame.height - 9
        if !detailsFromMenu && y < visible.minY + 8 { y = anchor.maxY + 9 }
        y = min(max(y, visible.minY + 8), visible.maxY - details.frame.height - 8)
        details.setFrameOrigin(NSPoint(x: x, y: y))
    }
    func statusAnchor() -> NSRect {
        guard let button = statusItem.button, let window = button.window else { return capsule.frame }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
    func showDetails(fromMenu: Bool, hold: Bool) {
        model.refreshLoginStatus()
        cancelHide(); detailsFromMenu = fromMenu; holdDetails = hold
        resizeDetails(); positionDetails(); details.orderFrontRegardless()
        if hold { details.makeKey() }
        if model.snapshot == nil || model.stale { model.refresh() }
    }
    func hoverCapsule() { if !holdDetails { showDetails(fromMenu: false, hold: false) } }
    func toggleDetailsFromCapsule() {
        if details.isVisible && holdDetails && !detailsFromMenu { hideDetails() }
        else { showDetails(fromMenu: false, hold: true) }
    }
    func hideDetails() { cancelHide(); holdDetails = false; details.orderOut(nil) }
    func cancelHide() { hideWork?.cancel(); hideWork = nil }
    func scheduleHide() {
        guard !holdDetails else { return }
        cancelHide()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.holdDetails else { return }
            let p = NSEvent.mouseLocation
            if !self.details.frame.insetBy(dx: -4, dy: -4).contains(p) && !self.capsule.frame.contains(p) { self.hideDetails() }
        }
        hideWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    func resetPosition() {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        capsule.setFrameOrigin(NSPoint(x: visible.maxX - 150, y: visible.maxY - 100)); savePosition()
    }
    func clampPosition() {
        let frame = capsule.frame
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        capsule.setFrameOrigin(NSPoint(x: min(max(frame.minX, visible.minX + 6), visible.maxX - frame.width - 6),
                                      y: min(max(frame.minY, visible.minY + 6), visible.maxY - frame.height - 6)))
    }
    func savePosition() { clampPosition(); UserDefaults.standard.set(NSStringFromPoint(capsule.frame.origin), forKey: "position") }
    func cycleTheme() {
        guard Date().timeIntervalSince(lastThemeChange) > 0.4 else { return }
        lastThemeChange = Date()
        let themes = ["system", "light", "dark"]
        model.theme = themes[((themes.firstIndex(of: model.theme) ?? 0) + 1) % themes.count]; model.save()
    }
    @objc func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = contextMenu(); statusItem.button?.performClick(nil); statusItem.menu = nil
        } else if details.isVisible && detailsFromMenu { hideDetails() }
        else { showDetails(fromMenu: true, hold: true) }
    }
    func contextMenu() -> NSMenu {
        model.refreshLoginStatus()
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector, checked: Bool? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self
            if let checked { item.state = checked ? .on : .off }; menu.addItem(item)
        }
        item("刷新额度", #selector(refreshAction)); item("查看详情", #selector(detailAction))
        menu.addItem(.separator())
        item("显示悬浮胶囊", #selector(toggleFloating), checked: model.floating)
        item("窗口置顶", #selector(togglePinned), checked: model.pinned)
        item("仅在 Codex / ChatGPT 运行时显示", #selector(toggleFollow), checked: model.followHost)
        item("切换外观（系统 / 浅色 / 深色）", #selector(themeAction))
        item("恢复默认位置", #selector(resetAction))
        item("登录时启动 · " + model.loginStatusText, #selector(toggleLogin), checked: model.loginEnabled)
        menu.addItem(.separator()); item("打开 Codex / ChatGPT", #selector(openHost))
        item("关于Token额度", #selector(showAbout)); item("退出Token额度", #selector(quit))
        return menu
    }
    @objc func toggleLogin() { setLoginEnabled(SMAppService.mainApp.status != .enabled) }
    func setLoginEnabled(_ enabled: Bool) {
        guard !model.loginBusy else { return }
        model.loginBusy = true
        defer { model.refreshLoginStatus(); model.loginBusy = false }
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems(); return }
                if service.status != .enabled { try service.register() }
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
        } catch {
            let alert = NSAlert(); alert.messageText = "登录启动设置未完成"
            alert.informativeText = "请将应用保留在固定位置，再到系统设置 → 通用 → 登录项中检查「Token额度」。\n\n系统信息：" + error.localizedDescription
            alert.runModal()
        }
    }
    @objc func activated() { model.refreshLoginStatus() }
    @objc func showAbout() {
        let alert = NSAlert(); alert.messageText = "Token额度 · Codex Badge for Mac"
        alert.informativeText = "1.5.1 · 原生 macOS 版本\n\n灵感与协议参考：returnk/codex-usage-badge（MIT）\nhttps://github.com/returnk/codex-usage-badge\n\n通过本机 Codex CLI 只读获取额度，每 60 秒同步。\n不发送模型请求，不收集登录凭据。\n第三方工具，非 OpenAI 官方产品。"
        alert.runModal()
    }
    @objc func openHost() {
        let fm = FileManager.default
        if let path = ["/Applications/Codex.app", "/Applications/ChatGPT.app"].first(where: { fm.fileExists(atPath: $0) }) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
        }
    }
    @objc func wake() { model.refresh() }
    @objc func screenChanged() { clampPosition(); if details.isVisible { positionDetails() } }
    @objc func refreshAction() { model.refresh() }
    @objc func detailAction() { showDetails(fromMenu: true, hold: true) }
    @objc func toggleFloating() { model.floating.toggle(); model.save() }
    @objc func togglePinned() { model.pinned.toggle(); model.save() }
    @objc func toggleFollow() { model.followHost.toggle(); model.save() }
    @objc func themeAction() { cycleTheme() }
    @objc func resetAction() { resetPosition() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showDetails(fromMenu: true, hold: true); return true }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); tick?.invalidate(); model.client.stop() }
}
