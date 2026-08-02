import SwiftUI
import AppKit

// 定义一个应用的数据模型
struct AppItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let bundleURL: URL
    let icon: NSImage
}
@MainActor
class DashboardAppsViewModel: ObservableObject {
    @Published var apps: [AppItem] = []

    init() {
        loadInstalledApps()
    }

    func loadInstalledApps() {
        // 在后台线程加载应用，避免卡顿
        Task.detached(priority: .userInitiated) {
            var loadedApps: [AppItem] = []

            let searchPaths = [
                "/Applications",
                "/System/Applications",
                // NSSearchPathForDirectoriesInDomains(.applicationDirectory, .userDomainMask, true)
                //     .first ?? "",
            ]

            let fileManager = FileManager.default
            for path in searchPaths where !path.isEmpty {
                guard
                    let urls = try? fileManager.contentsOfDirectory(
                        at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles])
                else {
                    continue
                }

                for url in urls {
                    if url.pathExtension == "app" {
                        let name = url.deletingPathExtension().lastPathComponent
                        let icon = NSWorkspace.shared.icon(forFile: url.path)
                        loadedApps.append(AppItem(name: name, bundleURL: url, icon: icon))
                    }
                }
            }

            let sortedApps = loadedApps.sorted { $0.name < $1.name }

            // 回到主线程更新 UI 状态
            await MainActor.run {
                self.apps = sortedApps
            }
        }
    }

    func launchApp(url: URL) {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        { _, error in
            if let error = error {
                print("打开应用失败: \(error)")
            } else {
                Task { @MainActor in
                    DashboardController.shared.toggleDashboard()
                }
            }
        }
    }
}

struct DashboardMainView: View {
    @StateObject private var viewModel = DashboardAppsViewModel()
    @State private var searchText = ""
    @FocusState private var isSearchFieldFocused: Bool  // 1. 定义焦点状态

    // 根据搜索框内容实时过滤应用
    var filteredApps: [AppItem] {
        if searchText.isEmpty {
            return viewModel.apps
        } else {
            return viewModel.apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        ZStack {
            // 点击背景空白处收起
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    DashboardController.shared.toggleDashboard()
                }

            VStack(spacing: 20) {
                // 顶部：搜索栏
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                        .font(.system(size: 20))
                    
                    TextField("搜索应用...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .focused($isSearchFieldFocused)  // 2. 绑定焦点
                }
                .padding(15)
                .frame(width: 500)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                .contentShape(Rectangle())
                .onTapGesture {
                    // 这里什么都不做，空实现即可阻止点击关闭
                }

                // 中部：应用网格展示区
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum:  100), spacing: 40)], spacing: 40) {
                        ForEach(filteredApps) { app in
                            Button(action: {
                                viewModel.launchApp(url: app.bundleURL)
                            }) {
                                VStack(spacing: 8) {
                                    Image(nsImage: app.icon)
                                        .resizable()
                                        .frame(width: 80, height: 80)
                                        .shadow(radius: 4)

                                    Text(app.name)
                                        .font(.system(size: 13))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .frame(width: 100, height: 100)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 40)
                }
                .frame(width: 1200, height: 600)
            }

            // // 隐藏的 Esc 响应按钮
            // Button("") {
            //     DashboardController.shared.toggleDashboard()
            // }
            // .keyboardShortcut(.escape, modifiers: [])  // 绑定 Esc 键
            // .opacity(0)  // 完全隐藏，只留快捷键响应
            // .frame(width: 0, height: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 关键补丁 1：监听 macOS 系统级 Esc / Exit 动作
        .onExitCommand {
            DashboardController.shared.toggleDashboard()
        }
        // 关键补丁 2：面板一呼出，自动聚焦搜索框
        .onAppear {
            isSearchFieldFocused = true
        }
    }
}