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

    func applicationDidFinishLaunching(_ notification: Notification) {
        print(">>> App 启动成功，正在注册全局快捷键 (Option + Space) <<<")
        registerGlobalHotKey()
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
                    DashboardController.shared.toggleDashboard()
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