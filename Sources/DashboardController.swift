import Cocoa
import SwiftUI

class DashboardPanel: NSPanel {

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func cancelOperation(_ sender: Any?) {
        DashboardController.shared.closeDashboard()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            DashboardController.shared.closeDashboard()
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
class DashboardController {

    static let shared = DashboardController()

    private var dashboardWindow: DashboardPanel?

    func toggleDashboard() {
        if let window = dashboardWindow, window.isVisible {
            hideDashboard()
        } else {
            showDashboard()
        }
    }
    func closeDashboard() {
        hideDashboard()
    }

    private func showDashboard() {
        guard let screen = NSScreen.main else { return }

        if dashboardWindow == nil {
            let panel = DashboardPanel(
                contentRect: screen.frame,
                styleMask: [
                    .borderless,
                    .fullSizeContentView,
                ],
                backing: .buffered,
                defer: false
            )

            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.becomesKeyOnlyIfNeeded = false

            // Dashboard层级
            panel.level = .floating
            // 透明窗口
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
            ]
            let hosting = NSHostingView(
                rootView:
                    DashboardMainView()
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
            )
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor =
                NSColor.clear.cgColor
            panel.contentView = hosting
            dashboardWindow = panel
        }
        guard let window = dashboardWindow else { return}
        window.setFrame(screen.frame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func hideDashboard() {
        dashboardWindow?.orderOut(nil)
    }
}