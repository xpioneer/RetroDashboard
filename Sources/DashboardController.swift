import Cocoa
import SwiftUI

@MainActor
class DashboardController {
    static let shared = DashboardController()
    private var dashboardWindow: NSPanel?

    func toggleDashboard() {
        if let window = dashboardWindow, window.isVisible {
            hideDashboard()
        } else {
            showDashboard()
        }
    }

    private func showDashboard() {
        guard let screen = NSScreen.main else { return }
        
        if dashboardWindow == nil {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            
            // 必须配置这几行，才能接收键盘打字和鼠标点击：
            panel.isFloatingPanel = true
            panel.level = .floating  // 不要用 .mainMenu 或 .screenSaver，用 .floating 即可
            // panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            // 允许该面板成为 key window 接收键盘输入
            panel.becomesKeyOnlyIfNeeded = false

            // panel.level = .screenSaver
            panel.backgroundColor = NSColor.black.withAlphaComponent(0.5)
            panel.isOpaque = false
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            // 载入 SwiftUI 界面
            panel.contentView = NSHostingView(rootView: DashboardMainView())
            dashboardWindow = panel
        }

        dashboardWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideDashboard() {
        dashboardWindow?.orderOut(nil)
    }
}