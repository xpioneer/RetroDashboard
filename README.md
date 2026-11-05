# RetroDashboard

macOS 全屏复古 Dashboard（旧款 macOS Dashboard 风格），Swift + AppKit/SwiftUI，不需要 Xcode。

- **背景**：`NSVisualEffectView(.hudWindow, .behindWindow)` 真毛玻璃，会模糊桌面和后面的窗口；不铺实心底色
- **布局**：顶部内凹玻璃搜索框、中部大图标 widget 网格、底部等宽状态栏、左下角 `+` 按钮（重新扫描应用）
- **交互**：`⌥ Space` 显示/隐藏，`↑↓` 选择，`⏎` 打开，`Esc` 关闭，点空白处关闭
- **搜索**：应用名（中英文）、全拼、拼音首字母，按匹配度排序。例如 `wx` → 微信，`wyy` → 网易云音乐，`vsc` → VS Code

## Run

改完代码**一定要先杀掉旧进程**再启动，否则跑的还是旧二进制：

```bash
killall -9 RetroDashboard 2>/dev/null || true
swift run
```

VS Code 里按 `F5` 也可以（`preLaunchTask` 会自动 kill + build）。

## 一个重要的坑：activationPolicy

SwiftUI `App` 只声明 `Settings` scene、且 `swift run` 产物没有 `Info.plist` 时，
`NSApplication.activationPolicy` 默认是 **`.prohibited`**。这种进程窗口能画出来，
但**永远不能成为 active app、窗口永远不是 key window，键盘事件根本不会投递进来** ——
搜索框无论用 SwiftUI `TextField`、`@FocusState`、还是 `NSTextField` + `makeFirstResponder`
都收不到任何字符。

修复在 `AppDelegate.applicationWillFinishLaunching`：

```swift
NSApp.setActivationPolicy(.accessory)   // 无 Dock 图标，但可激活、窗口可成为 key window
```

想让它在 Dock 里显示，改成 `.regular` 也可以（同样能收键盘输入），但会多一个菜单栏。

## 排查工具

```bash
# 模拟"从别的 App 用热键唤起"，打印焦点链路 + 合成一次 'a' 按键做端到端自检
RETRO_DASHBOARD_DIAG=1 ./.build/debug/RetroDashboard
```

正常输出应包含 `isActive=true`、`policy=1`、`keyWindow=DashboardPanel`、
`模拟按键 'a': '' -> 'a'  ✅ 输入链路已打通`。

```bash
# 启动即展开面板，方便调界面（不用按快捷键）
RETRO_DASHBOARD_AUTOSHOW=1 ./.build/debug/RetroDashboard
```

## 源码结构

| 文件 | 作用 |
|---|---|
| `RetroDashboardApp.swift` | 入口、全局热键、**activationPolicy 修复**、调试开关 |
| `DashboardController.swift` | 全屏 `NSPanel`、键盘事件、焦点诊断 |
| `DashboardMainView.swift` | 毛玻璃背景、全屏布局、widget 网格 |
| `SearchField.swift` | `NSTextField` 包装，每次显示强制夺回第一响应者 |
| `DashboardState.swift` | 应用扫描、拼音索引、搜索排序、启动应用 |
