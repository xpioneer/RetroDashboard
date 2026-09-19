import SwiftUI
import AppKit

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(frame: .zero)
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.backgroundColor =
            NSColor.clear.cgColor
        return view
    }

    func updateNSView(
        _ nsView: NSVisualEffectView,
        context: Context
    ) {}

}

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
        Task.detached {
            var result: [AppItem] = []

            let paths = [
                "/Applications",
                "/System/Applications",
            ]

            for path in paths {
                guard
                    let urls =
                        try? FileManager.default.contentsOfDirectory(
                            at: URL(fileURLWithPath: path),
                            includingPropertiesForKeys: nil
                        )

                else {
                    continue
                }

                for url in urls {
                    if url.pathExtension == "app" {
                        result.append(
                            AppItem(
                                name:
                                    url.deletingPathExtension()
                                    .lastPathComponent,
                                bundleURL: url,
                                icon:
                                    NSWorkspace.shared
                                    .icon(forFile: url.path)
                            )

                        )
                    }
                }
            }

            let sorted = result.sorted { $0.name < $1.name }

            await MainActor.run {
                self.apps = sorted
            }
        }
    }

    func launchApp(url: URL) {
        NSWorkspace.shared.openApplication(
            at: url,
            configuration:
                NSWorkspace.OpenConfiguration()
        ) { _, _ in
            Task { @MainActor in
                DashboardController.shared.closeDashboard()
            }
        }
    }
}

struct DashboardMainView: View {
    @StateObject private var viewModel =
        DashboardAppsViewModel()
    @State private var searchText = ""
    @FocusState private var focused: Bool

    var filteredApps: [AppItem] {
        if searchText.isEmpty {
            return viewModel.apps
        }
        return viewModel.apps.filter {
            $0.name.localizedCaseInsensitiveContains(
                searchText
            )
        }
    }

    var body: some View {
        ZStack {

            // 玻璃背景
            VisualEffectView()
                .ignoresSafeArea()
            // 空白关闭层
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { DashboardController.shared.closeDashboard() }

            VStack(spacing: 20) {
                HStack {
                    Image(
                        systemName:
                            "magnifyingglass"
                    )
                    .foregroundColor(.white.opacity(0.8))

                    TextField(
                        "搜索应用...",
                        text: $searchText
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .focused($focused)
                }
                .padding(12)

                .frame(width: 420)

                .background(
                    VisualEffectView(
                        material: .hudWindow
                    )
                    .allowsHitTesting(false)
                )
                .cornerRadius(14)
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(
                                    minimum: 100
                                ),
                                spacing: 36
                            )
                        ],
                        spacing: 36
                    ) {
                        ForEach(filteredApps) { app in
                            Button {
                                viewModel.launchApp(
                                    url: app.bundleURL
                                )
                            } label: {
                                VStack(spacing: 8) {
                                    Image(
                                        nsImage: app.icon
                                    )
                                    .resizable()
                                    .frame(
                                        width: 80,
                                        height: 80
                                    )

                                    Text(app.name)

                                        .foregroundColor(.white)

                                        .font(.system(size: 13))

                                        .lineLimit(1)
                                }
                                .frame(
                                    width: 100,
                                    height: 110
                                )
                                .background(
                                    VisualEffectView(
                                        material: .popover
                                    )
                                    .allowsHitTesting(false)
                                )
                                .cornerRadius(14)

                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(40)
                }
            }
            .padding(.vertical, 80)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }

        .onAppear {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.2
            ) {
                focused = true
            }
        }
    }
}