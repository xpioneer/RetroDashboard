import AppKit
import SwiftUI

/// 用 NSTextField 包一层，而不是 SwiftUI 的 TextField。
/// 原因：SwiftUI 的 @FocusState 在"窗口被 orderOut 后重新显示"时无法可靠地重新夺回焦点，
/// 而这里可以直接调用 window.makeFirstResponder(_:) 强制拿焦点。
struct SearchField: NSViewRepresentable {

    @Binding var text: String
    var placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 21, weight: .regular)
        field.textColor = .white
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.35),
                .font: NSFont.systemFont(ofSize: 21, weight: .regular),
            ]
        )

        context.coordinator.field = field
        context.coordinator.startObserving()
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.text = $text
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {

        var text: Binding<String>
        weak var field: NSTextField?
        private var showObserver: NSObjectProtocol?

        init(text: Binding<String>) {
            self.text = text
        }

        func startObserving() {
            showObserver = NotificationCenter.default.addObserver(
                forName: .dashboardDidShow,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.grabFocus()
                }
            }
        }

        func stopObserving() {
            if let observer = showObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            showObserver = nil
        }

        /// 面板刚显示时窗口可能还没成为 key window，这里做一次兜底重试
        func grabFocus() {
            Task { @MainActor in
                for delay in [0, 40, 120] {
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
                    }
                    guard let field, let window = field.window else { continue }
                    if window.firstResponder === field.currentEditor() { return }
                    window.makeFirstResponder(field)
                }
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            if text.wrappedValue != field.stringValue {
                text.wrappedValue = field.stringValue
            }
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                DashboardController.shared.closeDashboard()
                return true
            }
            return false
        }
    }
}
