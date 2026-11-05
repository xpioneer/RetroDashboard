import Cocoa
import SwiftUI
import Carbon.HIToolbox

@main
struct RetroDashboardApp: App {
    // 绑定 AppDelegate
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // macOS 需要至少有一个 Scene（哪怕是 Settings），否则 App 会直接退出
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeyRef: EventHotKeyRef?

    /// 这是"搜索框打不了字"的真正根因。
    ///
    /// SwiftUI App 只声明了 Settings scene、且 swift run 产物没有 Info.plist 时，
    /// NSApplication 会把 activationPolicy 判定为 .prohibited（后台进程）。
    /// 这种进程永远不能成为 active app，窗口永远拿不到 keyWindow 状态，
    /// 键盘事件不会被投递进来 —— 无论用 SwiftUI TextField、NSTextField、
    /// @FocusState 还是 makeFirstResponder 都收不到任何字符。
    ///
    /// 设成 .accessory：无 Dock 图标/菜单栏，但可以激活、窗口可以成为 key window，
    /// 正是 Spotlight / Dashboard 这类热键唤起工具该用的策略。
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 兜底：SwiftUI 在 finishLaunching 之后有可能重设策略
        NSApp.setActivationPolicy(.accessory)
        print(">>> App 启动成功，正在注册全局快捷键 (Option + Space) <<<")
        registerGlobalHotKey()

        // 调试用：设置 RETRO_DASHBOARD_AUTOSHOW=1 时启动即展开面板，方便调界面
        if ProcessInfo.processInfo.environment["RETRO_DASHBOARD_AUTOSHOW"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                DashboardController.shared.showDashboard()
            }
        }

        // 调试用：RETRO_DASHBOARD_DIAG=1 模拟"从别的 App 用热键唤起"，打印焦点链路
        if ProcessInfo.processInfo.environment["RETRO_DASHBOARD_DIAG"] == "1" {
            NSWorkspace.shared.runningApplications
                .first { $0.bundleIdentifier == "com.apple.finder" }?
                .activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                DashboardController.shared.showDashboard()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    DashboardController.shared.dumpDiagnostics()
                    DashboardController.shared.selfTestInput()
                }
            }
        }
    }

    private func registerGlobalHotKey() {
        var gMyHotKeyID = EventHotKeyID()
        gMyHotKeyID.signature = 0x5244484B  // "RDHK" 的十六进制 ASCII 码
        gMyHotKeyID.id = 1

        // Option 键对应的 Carbon 掩码是 optionKey (1 << 11)
        // Space 键的 KeyCode 是 49
        let err = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            gMyHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if err == noErr {
            print(">>> 全局快捷键注册成功！请直接按下 Option + Space <<<")
        } else {
            print(">>> 注册全局快捷键失败，错误码: \(err) <<<")
        }

        // 安装事件处理回调
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                Task { @MainActor in
                    // DashboardController.shared.toggleDashboard()
                    NSApp.activate(ignoringOtherApps: true)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        DashboardController.shared.toggleDashboard()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }
}