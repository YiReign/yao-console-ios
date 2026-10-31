import SwiftUI

// MARK: - 主视图

struct ContentView: View {
    @State private var selection: String = ConsoleSites.all[0].id
    @StateObject private var engine = WebEngine()
    @State private var coordinator: NavigationCoordinator?
    @State private var showSiteSheet = false

    private var currentSite: ConsoleSite {
        ConsoleSites.all.first { $0.id == selection } ?? ConsoleSites.all[0]
    }

    var body: some View {
        ZStack {
            Theme.backdrop.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                LoadingBar(progress: engine.progress, visible: engine.loading || engine.progress > 0)
                content
                homeBar
            }
        }
        .onAppear {
            let c = NavigationCoordinator()
            c.engine = engine
            engine.webView.navigationDelegate = c
            engine.webView.uiDelegate = c
            coordinator = c
            engine.load(currentSite.url)
        }
        .sheet(isPresented: $showSiteSheet) {
            SitePicker(selection: $selection) { site in
                selection = site.id
                showSiteSheet = false
                engine.beginLoading()
                engine.load(site.url)
            }
            .presentationDetents([.fraction(0.55)])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                showSiteSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: currentSite.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(currentSite.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(engine.currentTitle.isEmpty ? currentSite.subtitle : engine.currentTitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.inkSoft)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.inkSoft)
                }
                .padding(.leading, 6).padding(.trailing, 10).padding(.vertical, 5)
                .background(Color.white.opacity(0.75), in: Capsule())
                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            if engine.loading {
                Text("\(Int(engine.progress * 100))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.10), in: Capsule())
            }

            Button { engine.reload() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.75), in: Circle())
                    .overlay(Circle().stroke(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(engine.loading)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        if engine.failed {
            ErrorView(message: engine.failedMessage, site: currentSite) {
                engine.reload()
            }
        } else {
            ZStack {
                WebViewContainer(webView: engine.webView)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Theme.line, lineWidth: 1)
                    )
                    .padding(.horizontal, 10)

                // 首次加载时的中央进度卡（还没渲染任何内容时显示）
                if engine.loading && engine.progress < 0.35 {
                    LoadingOverlay(site: currentSite, progress: engine.progress)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: engine.loading)
        }
    }

    // MARK: 底部导航

    private var homeBar: some View {
        HStack(spacing: 6) {
            ForEach(ConsoleSites.all) { site in
                Button {
                    guard selection != site.id else { return }
                    selection = site.id
                    engine.beginLoading()
                    engine.load(site.url)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: site.systemImage)
                            .font(.system(size: 16, weight: selection == site.id ? .semibold : .regular))
                        Text(site.title)
                            .font(.system(size: 9.5, weight: selection == site.id ? .semibold : .regular))
                    }
                    .foregroundStyle(selection == site.id ? Theme.accent : Theme.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selection == site.id ? Theme.accent.opacity(0.10) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .background(Color.white.opacity(0.6))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

// MARK: - 加载浮层

struct LoadingOverlay: View {
    let site: ConsoleSite
    let progress: Double
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Theme.line, lineWidth: 5)
                    .frame(width: 52, height: 52)
                Circle()
                    .trim(from: 0, to: max(0.04, progress))
                    .stroke(
                        AngularGradient(colors: [Theme.accent, Theme.accent2, Theme.accent],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: progress)
            }
            Text(site.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(progress > 0 ? "正在加载 \(Int(progress * 100))%" : "正在连接")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkSoft)
                .monospacedDigit()
        }
        .padding(.horizontal, 34).padding(.vertical, 26)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: Theme.ink.opacity(0.06), radius: 24, y: 10)
    }
}

// MARK: - 错误页

struct ErrorView: View {
    let message: String
    let site: ConsoleSite
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("暂时打不开")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(message.isEmpty ? "请检查网络后重试。" : message)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .padding(.horizontal, 12)
            Button(action: retry) {
                Text("重新加载")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26).padding(.vertical, 11)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)

            Text("需要登录时，先在页面里完成登录，登录状态会保留。")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.inkSoft.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.line, lineWidth: 1)
        )
        .padding(.horizontal, 10)
    }
}

// MARK: - 站点选择

struct SitePicker: View {
    @Binding var selection: String
    let onPick: (ConsoleSite) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backdrop.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(ConsoleSites.all) { site in
                            Button { onPick(site) } label: {
                                HStack(spacing: 13) {
                                    Image(systemName: site.systemImage)
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundStyle(selection == site.id ? .white : Theme.accent)
                                        .frame(width: 40, height: 40)
                                        .background(
                                            selection == site.id
                                            ? AnyShapeStyle(Theme.accent)
                                            : AnyShapeStyle(Theme.accent.opacity(0.12)),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(site.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(Theme.ink)
                                        Text(site.urlString.replacingOccurrences(of: "https://", with: ""))
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.inkSoft)
                                    }
                                    Spacer()
                                    if selection == site.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                                .padding(.horizontal, 14).padding(.vertical, 11)
                                .background(Color.white.opacity(0.8),
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(selection == site.id ? Theme.accent.opacity(0.4) : Theme.line,
                                                lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 8)
                }
            }
            .navigationTitle("切换后台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }
}
