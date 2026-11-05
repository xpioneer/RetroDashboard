import Cocoa
import Foundation

// MARK: - 单条应用数据

struct AppItem: Identifiable, Hashable {

    let id: String  // 用 bundle 路径做稳定 id，避免每次加载都换 UUID
    let name: String
    let bundleURL: URL
    let icon: NSImage

    /// 预先算好的小写名 / 全拼 / 拼音首字母，避免每次敲键都重算
    let searchName: String
    let pinyinFull: String
    let pinyinInitials: String

    init(url: URL) {
        let displayName = url.deletingPathExtension().lastPathComponent
        self.id = url.standardizedFileURL.path
        self.name = displayName
        self.bundleURL = url
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
        self.searchName = displayName.lowercased()

        let pinyin = Pinyin.convert(displayName)
        self.pinyinFull = pinyin.full
        self.pinyinInitials = pinyin.initials
    }

    /// 匹配优先级：数字越小越靠前
    func matchScore(_ query: String) -> Int? {
        guard !query.isEmpty else { return 0 }

        if searchName == query { return 0 }
        if searchName.hasPrefix(query) { return 1 }
        if searchName.contains(query) { return 2 }

        if !pinyinInitials.isEmpty, pinyinInitials == query { return 3 }
        if !pinyinInitials.isEmpty, pinyinInitials.hasPrefix(query) { return 4 }
        if !pinyinFull.isEmpty, pinyinFull.hasPrefix(query) { return 5 }
        if !pinyinFull.isEmpty, pinyinFull.contains(query) { return 6 }

        return nil
    }

    static func == (lhs: AppItem, rhs: AppItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - 汉字转拼音

enum Pinyin {

    /// 返回全拼（小写、无空格）与首字母缩写
    /// "微信" -> ("weixin", "wx")；"Safari" -> ("safari", "s")
    static func convert(_ text: String) -> (full: String, initials: String) {
        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)

        let latin = mutable as String
        let syllables = latin.split(separator: " ").map(String.init)

        let full = syllables.joined().lowercased()
        let initials = syllables
            .compactMap { $0.first.map(String.init) }
            .joined()
            .lowercased()

        return (full, initials)
    }
}

// MARK: - 应用扫描

enum AppCatalog {

    /// 只做文件系统遍历，不碰 AppKit，可安全放到后台线程
    nonisolated static func scan() -> [URL] {
        let fm = FileManager.default

        var roots = [
            "/Applications",
            "/System/Applications",
        ]
        let userApps = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications").path
        if fm.fileExists(atPath: userApps) {
            roots.append(userApps)
        }

        var seen = Set<String>()
        var found: [URL] = []

        func walk(_ directory: URL, depth: Int) {
            guard depth <= 2 else { return }

            let entries = (try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for entry in entries {
                if entry.pathExtension == "app" {
                    let key = entry.standardizedFileURL.path
                    if seen.insert(key).inserted {
                        found.append(entry)
                    }
                    continue
                }

                let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?
                    .isDirectory ?? false
                if isDirectory {
                    walk(entry, depth: depth + 1)
                }
            }
        }

        for root in roots where fm.fileExists(atPath: root) {
            walk(URL(fileURLWithPath: root), depth: 0)
        }

        return found
    }
}

// MARK: - 界面状态

@MainActor
final class DashboardState: ObservableObject {

    @Published var searchText: String = "" {
        didSet {
            if searchText != oldValue { selectedIndex = 0 }
        }
    }

    @Published private(set) var apps: [AppItem] = []
    @Published private(set) var isLoading = false
    @Published var selectedIndex: Int = 0

    private var didLoad = false

    var results: [AppItem] {
        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !query.isEmpty else { return apps }

        var scored: [(app: AppItem, score: Int)] = []
        scored.reserveCapacity(apps.count)

        for app in apps {
            if let score = app.matchScore(query) {
                scored.append((app, score))
            }
        }

        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.app.name.localizedStandardCompare(rhs.app.name) == .orderedAscending
        }

        return scored.map(\.app)
    }

    // MARK: 加载

    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        isLoading = true

        Task { @MainActor in
            // 文件遍历放后台，图标必须在主线程生成（NSWorkspace / NSImage 不是线程安全的）
            let urls = await Task.detached(priority: .userInitiated) {
                AppCatalog.scan()
            }.value

            var items: [AppItem] = []
            items.reserveCapacity(urls.count)

            for (index, url) in urls.enumerated() {
                items.append(AppItem(url: url))
                // 分批让出主线程，避免首次打开卡一下
                if index % 20 == 19 {
                    await Task.yield()
                }
            }

            apps = items
            isLoading = false
        }
    }

    /// 左下角 "+" 按钮：重新扫描已安装的应用
    func reload() {
        didLoad = false
        apps = []
        isLoading = true
        loadIfNeeded()
    }

    // MARK: 交互

    func reset() {
        searchText = ""
        selectedIndex = 0
    }

    func moveSelection(by delta: Int) {
        let count = results.count
        guard count > 0 else { return }

        let next = selectedIndex + delta
        if next < 0 {
            selectedIndex = count - 1
        } else if next >= count {
            selectedIndex = 0
        } else {
            selectedIndex = next
        }
    }

    func launchSelected() {
        let list = results
        guard list.indices.contains(selectedIndex) else {
            if let first = list.first { launch(first) }
            return
        }
        launch(list[selectedIndex])
    }

    func launch(_ app: AppItem) {
        NSWorkspace.shared.openApplication(
            at: app.bundleURL,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
        // 不要抢回原 App 的焦点，否则刚启动的程序会被压在下面
        DashboardController.shared.closeDashboard(restoreFocus: false)
    }
}
