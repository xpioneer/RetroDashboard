import Cocoa
import SwiftUI

extension Notification.Name {
    /// 面板每次显示时广播，用于让搜索框重新夺取键盘焦点
    static let dashboardDidShow = Notification.Name("RetroDashboard.didShow")
}

final class DashboardPanel: NSPanel {

    // 无边框窗口默认不能成为 key window，必须打开
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        DashboardController.shared.closeDashboard()
    }
}

@MainActor
final class DashboardController {

    static let shared = DashboardController()

    let state = DashboardState()

    private var dashboardWindow: DashboardPanel?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?

    var isVisible: Bool { dashboardWindow?.isVisible ?? false }

    // MARK: - 生命周期

    func toggleDashboard() {
        if isVisible {
            closeDashboard()
        } else {
            showDashboard()
        }
    }

    func closeDashboard() {
        closeDashboard(restoreFocus: true)
    }

    /// - Parameter restoreFocus: 启动 App 时传 false，避免把焦点抢回原来的程序
    func closeDashboard(restoreFocus: Bool) {
        guard let window = dashboardWindow, window.isVisible else { return }

        stopKeyMonitor()
        window.orderOut(nil)
        state.reset()

        if restoreFocus {
            previousApp?.activate()
        }
        previousApp = nil
    }

    func showDashboard() {
        guard let screen = NSScreen.main else { return }

        let window = dashboardWindow ?? makeWindow(screen: screen)
        dashboardWindow = window

        // 记录切换前的前台 App，关闭时还回去
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }

        window.setFrame(screen.frame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        startKeyMonitor()
        state.loadIfNeeded()

        // 关键：通知搜索框重新成为第一响应者（不能只靠 onAppear）
        NotificationCenter.default.post(name: .dashboardDidShow, object: nil)
    }

    /// 诊断：打印键盘焦点链路的真实状态
    func dumpDiagnostics() {
        guard let window = dashboardWindow else {
            print("[DIAG] dashboardWindow == nil")
            return
        }
        print("[DIAG] NSApp.isActive=\(NSApp.isActive) policy=\(NSApp.activationPolicy().rawValue)")
        print("[DIAG] NSApp.keyWindow=\(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "nil")")
        print("[DIAG] panel.isKeyWindow=\(window.isKeyWindow) canBecomeKey=\(window.canBecomeKey)")
        print("[DIAG] firstResponder=\(window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil")")
        print("[DIAG] apps=\(state.apps.count) text='\(state.searchText)'")

        let field = findSearchField(in: window.contentView)
        print("[DIAG] NSTextField in hierarchy = \(field != nil)")
        if let field {
            print("[DIAG] field.window=\(field.window != nil) acceptsFirstResponder=\(field.acceptsFirstResponder)")
            print("[DIAG] makeFirstResponder => \(window.makeFirstResponder(field))")
            print("[DIAG] after firstResponder=\(window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil")")
        }
        fflush(stdout)
    }

    /// 端到端自检：合成一个 'a' 键事件投递给 App，看能不能写进 searchText
    func selfTestInput() {
        guard let window = dashboardWindow else { return }
        let before = state.searchText

        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        )
        if let event { NSApp.sendEvent(event) }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let after = self.state.searchText
            let ok = after == before + "a"
            print("[DIAG] 模拟按键 'a': '\(before)' -> '\(after)'  \(ok ? "✅ 输入链路已打通" : "❌ 输入仍丢失")")
            fflush(stdout)
        }
    }

    private func findSearchField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField { return field }
        for sub in view.subviews {
            if let field = findSearchField(in: sub) { return field }
        }
        return nil
    }

    // MARK: - 窗口构建

    private func makeWindow(screen: NSScreen) -> DashboardPanel {
        let panel = DashboardPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none

        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
        ]

        let hosting = NSHostingView(
            rootView: DashboardMainView(state: state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting

        return panel
    }

    // MARK: - 键盘（↑↓ 选择 / ⏎ 打开 / esc 关闭）

    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated {
                DashboardController.shared.handleKeyDown(event)
            }
            return handled ? nil : event
        }
    }

    private func stopKeyMonitor() {
        guard let monitor = keyMonitor else { return }
        NSEvent.removeMonitor(monitor)
        keyMonitor = nil
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard isVisible else { return false }

        // 带 ⌘/⌥/⌃ 的组合键交还给系统（⌘A、⌘V 等仍可用）
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.command) || mods.contains(.option) || mods.contains(.control) {
            return false
        }

        switch event.keyCode {
        case 53:  // esc：中文输入法正在组词时不抢，先让输入法取消候选
            if isComposingText() { return false }
            closeDashboard()
            return true
        case 125:  // ↓
            state.moveSelection(by: 1)
            return true
        case 126:  // ↑
            state.moveSelection(by: -1)
            return true
        case 36, 76:  // return / enter
            state.launchSelected()
            return true
        default:
            return false
        }
    }

    private func isComposingText() -> Bool {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else {
            return false
        }
        return editor.markedRange().length > 0
    }
}
