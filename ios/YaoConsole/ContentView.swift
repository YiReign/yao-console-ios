import SwiftUI

// MARK: - 首页（液态玻璃卡片）

struct ContentView: View {
    @StateObject private var store = StatusStore()
    @State private var opened: Backend?
    @State private var loaded = false
    @State private var glowPoint: CGPoint = .init(x: 0.3, y: 0.12)

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        header
                        summaryGlass
                        sectionLabel("后台")
                        ForEach(Backends.userSide) { b in
                            Button { opened = b } label: {
                                GlassCard(backend: b, state: store.cards[b.id], glow: glowPoint)
                            }
                            .buttonStyle(PressScale())
                        }
                        sectionLabel("管理后台")
                        ForEach(Backends.adminSide) { b in
                            Button { opened = b } label: {
                                GlassCard(backend: b, state: store.cards[b.id], glow: glowPoint)
                            }
                            .buttonStyle(PressScale())
                        }
                        eventsGlass
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                let w = UIScreen.main.bounds.width
                                let h = UIScreen.main.bounds.height
                                glowPoint = CGPoint(x: min(max(v.location.x / w, 0), 1),
                                                    y: min(max(v.location.y / h, 0), 1))
                            }
                    )
                }
                .refreshable { await store.refreshAll() }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("后台")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(red: 0.14, green: 0.12, blue: 0.29))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refreshAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: 0.35, green: 0.33, blue: 0.62))
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(item: $opened) { b in
                BackendView(backend: b) { Task { await store.refreshAll() } }
            }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            await store.refreshAll()
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("YAO 控制台")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(Color(red: 0.13, green: 0.11, blue: 0.28))
                Text(store.lastRefresh.formatted(date: .omitted, time: .shortened) + " 更新")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(red: 0.44, green: 0.43, blue: 0.58))
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    // MARK: 概览玻璃条

    private var summaryGlass: some View {
        let online = Backends.all.filter { store.cards[$0.id]?.level == .ok }.count
        let issues = Backends.all.filter {
            let lv = store.cards[$0.id]?.level
            return lv == .down || lv == .warn
        }.count

        return HStack(spacing: 0) {
            statCell("\(Backends.userSide.count)", "后台", color: Color(red: 0.13, green: 0.11, blue: 0.28))
            sep()
            statCell("\(Backends.adminSide.count)", "管理", color: Color(red: 0.42, green: 0.25, blue: 0.85))
            sep()
            statCell("\(online)", "正常", color: Color(red: 0.05, green: 0.60, blue: 0.36))
            sep()
            statCell("\(issues)", "异常", color: issues > 0
                     ? Color(red: 0.85, green: 0.22, blue: 0.24)
                     : Color(red: 0.44, green: 0.43, blue: 0.58))
        }
        .padding(.vertical, 16)
        .liquidGlass(corner: 22, glow: glowPoint, intensity: 1.1)
    }

    private func sep: some View {
        Rectangle()
            .fill(Color.white.opacity(0.55))
            .frame(width: 1, height: 26)
            .shadow(color: Color(red: 0.5, green: 0.5, blue: 0.9).opacity(0.18), radius: 1)
    }

    /// 分组小标题
    private func sectionLabel(_ s: String) -> some View {
        HStack {
            Text(s)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.36, green: 0.34, blue: 0.55))
            Spacer()
        }
        .padding(.leading, 6)
        .padding(.top, 4)
    }

    private func statCell(_ num: String, _ label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(num)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color(red: 0.44, green: 0.43, blue: 0.58))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 事件玻璃卡

    private var eventsGlass: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("最近事件")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.35, green: 0.33, blue: 0.55))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if store.events.isEmpty {
                Text("暂无事件")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(red: 0.55, green: 0.54, blue: 0.66))
                    .padding(.horizontal, 16).padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(store.events.prefix(5).enumerated()), id: \.offset) { i, e in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(red: 0.60, green: 0.55, blue: 0.95).opacity(0.6))
                            .frame(width: 4, height: 4)
                        Text(e)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 0.33, green: 0.32, blue: 0.46))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    if i < min(store.events.count, 5) - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.45))
                            .frame(height: 0.5)
                            .padding(.leading, 28)
                    }
                }
                Color.clear.frame(height: 12)
            }
        }
        .liquidGlass(corner: 22, glow: glowPoint, intensity: 0.7)
    }
}

// MARK: - 玻璃卡片（一个后台）

struct GlassCard: View {
    let backend: Backend
    let state: CardState?
    let glow: CGPoint

    private var titleColor: Color { Color(red: 0.13, green: 0.11, blue: 0.28) }
    private var subColor: Color { Color(red: 0.44, green: 0.43, blue: 0.58) }
    private var faintColor: Color { Color(red: 0.58, green: 0.57, blue: 0.68) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 玻璃图标块
            Image(systemName: backend.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(red: 0.33, green: 0.31, blue: 0.62))
                .frame(width: 36, height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.85), lineWidth: 0.8)
                        }
                }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(backend.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(titleColor)
                    if let s = state {
                        HStack(spacing: 4) {
                            Circle().fill(s.dotColor).frame(width: 5.5, height: 5.5)
                            Text(s.levelText)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(s.level == .down
                                                 ? Color(red: 0.85, green: 0.22, blue: 0.24)
                                                 : faintColor)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(faintColor.opacity(0.75))
                }

                if let s = state {
                    if s.rows.isEmpty {
                        Text(s.headline)
                            .font(.system(size: 12.5))
                            .foregroundStyle(subColor)
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(s.rows.prefix(3).enumerated()), id: \.offset) { _, pair in
                                HStack(spacing: 6) {
                                    Text(pair.0)
                                        .font(.system(size: 11))
                                        .foregroundStyle(faintColor)
                                        .frame(width: 32, alignment: .leading)
                                    Text(pair.1)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(subColor)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    if let p = s.progress {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.5)).frame(height: 4)
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [Color(red: 0.55, green: 0.48, blue: 0.98),
                                                 Color(red: 0.72, green: 0.62, blue: 1.0)],
                                        startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(4, g.size.width * p), height: 4)
                            }
                        }
                        .frame(height: 4)
                        .padding(.top, 3)
                    }
                } else {
                    Text("读取中")
                        .font(.system(size: 12))
                        .foregroundStyle(faintColor)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .liquidGlass(corner: 22, glow: glow, intensity: 0.85)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - 按压回弹

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.972 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 详情

struct BackendView: View {
    let backend: Backend
    let onClose: () -> Void

    @StateObject private var engine = WebEngine()
    @State private var coordinator: NavigationCoordinator?

    var body: some View {
        ZStack {
            Color(red: 0.972, green: 0.965, blue: 1.0).ignoresSafeArea()
            VStack(spacing: 0) {
                LoadingBar(progress: engine.progress, visible: engine.loading || engine.progress > 0)
                if engine.failed {
                    ErrorPane(message: engine.failedMessage) { engine.reload() }
                } else {
                    WebViewContainer(webView: engine.webView)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                        }
                        .shadow(color: Color(red: 0.4, green: 0.4, blue: 0.9).opacity(0.10),
                                radius: 24, y: 8)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                }
            }
        }
        .navigationTitle(backend.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button { engine.goBack() } label: {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(engine.webView.canGoBack
                                             ? Color(red: 0.33, green: 0.31, blue: 0.62)
                                             : Color(red: 0.75, green: 0.74, blue: 0.82))
                    }
                    .disabled(!engine.webView.canGoBack)

                    Button { engine.reload() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: 0.33, green: 0.31, blue: 0.62))
                    }
                }
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            let c = NavigationCoordinator()
            c.engine = engine
            engine.webView.navigationDelegate = c
            engine.webView.uiDelegate = c
            coordinator = c
            engine.load(backend.url)
        }
    }
}

struct ErrorPane: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color(red: 0.45, green: 0.43, blue: 0.65))
            Text("打不开这个后台")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.13, green: 0.11, blue: 0.28))
            if !message.isEmpty {
                Text(message).font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.44, green: 0.43, blue: 0.58))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            Button(action: retry) {
                Text("重试")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color(red: 0.33, green: 0.31, blue: 0.62))
                    .padding(.horizontal, 26).padding(.vertical, 10)
                    .background(Color.white.opacity(0.65), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
