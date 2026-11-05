import AppKit
import SwiftUI

// MARK: - 真正的毛玻璃（behindWindow 才会模糊窗口后面的桌面/窗口）

struct GlassView: NSViewRepresentable {
    // 沿用原项目的 .hudWindow 深玻璃，保持原来的背景质感
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(frame: .zero)
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = true
        view.autoresizingMask = [.width, .height]
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

// MARK: - 主界面：全屏复古 Dashboard

struct DashboardMainView: View {

    @ObservedObject var state: DashboardState
    @State private var hoveredID: String?

    private let ink = Color(red: 0.96, green: 0.95, blue: 0.90)  // 暖白，偏老系统
    private let aqua = Color(red: 0.55, green: 0.82, blue: 0.92)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ① 玻璃底 —— 不再铺任何实心底色
                GlassView()
                    .ignoresSafeArea()

                // ② 极淡的复古暗角 / 顶部柔光，只加氛围不盖住玻璃
                vintageLighting
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // ③ 细网格纹理（老 Dashboard 的布面质感，透明度极低）
                gridTexture
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // ④ 点空白处关闭（在内容下层，内容空白区可穿透）
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { DashboardController.shared.closeDashboard() }

                // ⑤ 内容：搜索框在上，widget 网格居中铺开，状态栏在下
                VStack(spacing: 0) {
                    searchBar
                        .padding(.top, max(56, geo.size.height * 0.10))

                    Spacer(minLength: 30)

                    resultGrid(maxHeight: max(240, geo.size.height - 340))

                    Spacer(minLength: 30)

                    bottomBar
                        .padding(.bottom, 34)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // ⑥ 左下角 "+" —— 还原旧 Dashboard 的 widget 添加按钮（这里用来刷新应用列表）
                VStack {
                    Spacer()
                    HStack {
                        addButton
                        Spacer()
                    }
                    .padding(.leading, 34)
                    .padding(.bottom, 30)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { state.loadIfNeeded() }
    }

    // MARK: 复古光效

    private var vintageLighting: some View {
        ZStack {
            // 顶部一道极淡的高光（中性白，不给玻璃染色）
            LinearGradient(
                colors: [
                    .white.opacity(0.045),
                    Color.clear,
                ],
                startPoint: .top,
                endPoint: .init(x: 0.5, y: 0.42)
            )

            // 四周暗角，只加层次不遮玻璃
            RadialGradient(
                colors: [
                    Color.clear,
                    Color.clear,
                    Color.black.opacity(0.12),
                ],
                center: .center,
                startRadius: 180,
                endRadius: 900
            )
        }
    }

    private var gridTexture: some View {
        // 22pt 极淡网格，模拟老系统 Dashboard 的亚麻/布面底纹
        Canvas { context, size in
            let step: CGFloat = 22
            context.stroke(
                Path { path in
                    var x: CGFloat = 0
                    while x < size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        x += step
                    }
                    var y: CGFloat = 0
                    while y < size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        y += step
                    }
                },
                with: .color(.white.opacity(0.012)),
                lineWidth: 0.5
            )
        }
    }

    // MARK: 搜索框（内凹玻璃）

    private var searchBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(ink.opacity(0.55))

            SearchField(text: $state.searchText, placeholder: "搜索应用…")
                .frame(height: 32)

            if !state.searchText.isEmpty {
                Button {
                    state.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(ink.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .frame(width: 540, height: 60)
        .background(
            GlassView(material: .hudWindow, blending: .withinWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.30), .white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.10))
                .frame(height: 1)
                .padding(.horizontal, 18)
                .padding(.top, 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    // MARK: Widget 网格

    private func resultGrid(maxHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                let results = state.results

                if results.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140), spacing: 24)],
                        spacing: 24
                    ) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, app in
                            AppTile(
                                app: app,
                                ink: ink,
                                isSelected: index == state.selectedIndex,
                                isHovered: hoveredID == app.id
                            )
                            .id(app.id)
                            .onHover { inside in
                                if inside {
                                    hoveredID = app.id
                                } else if hoveredID == app.id {
                                    hoveredID = nil
                                }
                            }
                            .onTapGesture { state.launch(app) }
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: 1220, maxHeight: maxHeight)
            .onChange(of: state.selectedIndex) { _, _ in
                let results = state.results
                guard results.indices.contains(state.selectedIndex) else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(results[state.selectedIndex].id, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: state.isLoading ? "clock.arrow.circlepath" : "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(ink.opacity(0.25))
            Text(state.isLoading ? "正在索引应用…" : "没有找到匹配的应用")
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(ink.opacity(0.45))
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    // MARK: 底部状态栏

    private var bottomBar: some View {
        HStack(spacing: 18) {
            Text("⌥ SPACE")
                .foregroundStyle(aqua.opacity(0.5))

            Rectangle()
                .fill(ink.opacity(0.12))
                .frame(width: 1, height: 12)

            Text("\(state.results.count) WIDGETS")
                .foregroundStyle(ink.opacity(0.35))

            Spacer()

            Text("↑↓ SELECT")
                .foregroundStyle(ink.opacity(0.30))
            Text("⏎ OPEN")
                .foregroundStyle(ink.opacity(0.30))
            Text("ESC CLOSE")
                .foregroundStyle(ink.opacity(0.30))
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .frame(width: 1220)
    }

    private var addButton: some View {
        Button {
            state.reload()
        } label: {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.10))
                    .background(
                        GlassView(material: .hudWindow, blending: .withinWindow)
                            .clipShape(Circle())
                    )
                Circle()
                    .strokeBorder(.white.opacity(0.28), lineWidth: 1)
                Text("+")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(ink.opacity(0.8))
            }
            .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .help("重新扫描已安装的应用")
    }
}

// MARK: - 单个 widget 图标

struct AppTile: View {

    let app: AppItem
    let ink: Color
    let isSelected: Bool
    let isHovered: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 88, height: 88)
                .shadow(color: .black.opacity(0.45), radius: 10, y: 6)

            Text(app.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ink.opacity(isSelected || isHovered ? 0.95 : 0.72))
                .lineLimit(1)
                .truncationMode(.middle)
                .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
        }
        .frame(width: 140, height: 138)
        .background(
            shape.fill(
                LinearGradient(
                    colors: [
                        .white.opacity(isSelected ? 0.18 : (isHovered ? 0.12 : 0.0)),
                        .white.opacity(isSelected ? 0.06 : 0.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        )
        .overlay(
            shape.strokeBorder(
                .white.opacity(isSelected ? 0.32 : (isHovered ? 0.14 : 0.0)),
                lineWidth: 1
            )
        )
        .contentShape(shape)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .animation(.easeOut(duration: 0.14), value: isHovered)
    }
}
