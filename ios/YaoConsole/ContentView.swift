import SwiftUI
import WebKit

// MARK: - 后台定义

struct Backend: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let icon: String
    let tint: Color
    let urlString: String
    var url: URL { URL(string: urlString)! }
}

enum Backends {
    static let all: [Backend] = [
        Backend(id: "panel", name: "服务器面板", host: "status.yaoyc.fun",
                icon: "server.rack", tint: Color(red: 0.42, green: 0.36, blue: 0.91),
                urlString: "https://status.yaoyc.fun"),
        Backend(id: "clock", name: "时钟控制台", host: "pet.yaoyc.fun",
                icon: "clock.badge.checkmark", tint: Color(red: 0.31, green: 0.62, blue: 0.86),
                urlString: "https://pet.yaoyc.fun/control"),
        Backend(id: "pet", name: "Hermes 状态", host: "pet.yaoyc.fun",
                icon: "sparkles", tint: Color(red: 0.85, green: 0.45, blue: 0.55),
                urlString: "https://pet.yaoyc.fun"),
        Backend(id: "chat", name: "YAO AI", host: "chat.yaoyc.fun",
                icon: "bubble.left.and.bubble.right", tint: Color(red: 0.36, green: 0.72, blue: 0.55),
                urlString: "https://chat.yaoyc.fun"),
        Backend(id: "site", name: "个人站", host: "yaoyc.fun",
                icon: "square.grid.2x2", tint: Color(red: 0.55, green: 0.58, blue: 0.66),
                urlString: "https://yaoyc.fun")
    ]
}

// MARK: - 主题

enum Theme {
    static let bg     = Color(red: 0.972, green: 0.968, blue: 0.996)
    static let card   = Color.white
    static let ink    = Color(red: 0.110, green: 0.106, blue: 0.204)
    static let ink2   = Color(red: 0.439, green: 0.443, blue: 0.529)
    static let line   = Color(red: 0.906, green: 0.902, blue: 0.945)
    static let accent = Color(red: 0.451, green: 0.400, blue: 0.910)
    static let ok     = Color(red: 0.204, green: 0.780, blue: 0.478)
    static let warn   = Color(red: 0.965, green: 0.678, blue: 0.204)
    static let down   = Color(red: 0.898, green: 0.318, blue: 0.318)
}

// MARK: - 状态模型

struct CardState {
    var connected: Bool = false        // 是否拿到了数据
    var needsLogin: Bool = false       // 需要登录
    var level: Level = .unknown
    var headline: String = "—"
    var details: [String] = []
    var progress: Double? = nil        // 0..1，用于 CPU/内存条

    enum Level { case ok, warn, down, unknown }

    var dotColor: Color {
        switch level {
        case .ok:      return Theme.ok
        case .warn:    return Theme.warn
        case .down:    return Theme.down
        case .unknown: return Theme.line
        }
    }
}

// MARK: - 数据拉取

@MainActor
final class StatusStore: ObservableObject {
    @Published var cards: [String: CardState] = [:]
    @Published var lastRefresh = Date()

    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8
        cfg.httpCookieStorage = .shared
        cfg.httpShouldSetCookies = true
        session = URLSession(configuration: cfg)
    }

    func refreshAll() async {
        async let pet = fetchPet()
        async let clock = fetchClock()
        async let chat = fetchChat()
        async let panel = fetchPanel()
        async let site = fetchSite()
        let results = await (pet, clock, chat, panel, site)
        for (k, v) in [("pet", results.0), ("clock", results.1), ("chat", results.2),
                       ("panel", results.3), ("site", results.4)] {
            if let v { cards[k] = v }
        }
        lastRefresh = Date()
    }

    private func get(_ url: String, cookie: Bool = true) async -> (Data?, Int) {
        guard let u = URL(string: url) else { return (nil, 0) }
        var req = URLRequest(url: u)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        do {
            let (d, r) = try await session.data(for: req)
            return (d, (r as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            return (nil, 0)
        }
    }

    // Hermes Pet —— 无需登录
    private func fetchPet() async -> CardState? {
        var st = CardState()
        let (d, code) = await get("https://pet.yaoyc.fun/api/stats")
        guard code == 200, let d,
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            st.level = .down; st.headline = "离线"; return st
        }
        st.connected = true
        st.level = .ok
        let total = obj["total"] as? [String: Any] ?? [:]
        let calls = total["calls"] as? Int ?? 0
        let tin = total["in"] as? Int ?? 0
        st.headline = "今日 \(calls) 次调用"
        st.details = ["输入 \(fmt(tin)) tokens"]
        if let models = obj["models"] as? [[String: Any]], let first = models.first {
            let name = first["model"] as? String ?? ""
            let c = first["calls"] as? Int ?? 0
            st.details.append("\(name) · \(c) 次")
        }
        // AI 当前状态
        let (sd, sc) = await get("https://pet.yaoyc.fun/api/status")
        if sc == 200, let sd,
           let so = try? JSONSerialization.jsonObject(with: sd) as? [String: Any] {
            let state = so["state"] as? String ?? ""
            let text = so["text"] as? String ?? ""
            st.details.insert(state == "idle" ? "空闲" : "● \(text)", at: 0)
        }
        return st
    }

    // 时钟控制台 —— 需要配对码登录（cookie 由 WebView 共享）
    private func fetchClock() async -> CardState? {
        var st = CardState()
        let (d, code) = await get("https://pet.yaoyc.fun/api/clock/hub/status")
        if code == 401 {
            st.needsLogin = true; st.level = .unknown; st.headline = "未登录"
            st.details = ["点击进入并输入配对码"]; return st
        }
        guard code == 200, let d,
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            st.level = .down; st.headline = "无法连接"; return st
        }
        st.connected = true
        let online = obj["online"] as? Bool ?? false
        st.level = online ? .ok : .down
        st.headline = online ? "设备在线" : "设备离线"
        if let inner = obj["status"] as? [String: Any] {
            let fw = inner["firmware"] as? String ?? "—"
            st.details.append("固件 \(fw)")
            if let wifi = inner["connectedSsid"] as? String {
                st.details.append("WiFi \(wifi)")
            }
            if let fps = inner["fps"] as? Int { st.details.append("\(fps) fps") }
        }
        if let ts = obj["updatedAt"] as? Double, !online {
            let date = Date(timeIntervalSince1970: ts / 1000)
            let mins = Int(Date().timeIntervalSince(date) / 60)
            st.details.append(mins > 120 ? "已离线 \(mins/60) 小时" : "已离线 \(mins) 分钟")
        }
        return st
    }

    // WebChat —— 无需登录
    private func fetchChat() async -> CardState? {
        var st = CardState()
        let (d, code) = await get("https://chat.yaoyc.fun/api/models")
        guard code == 200, let d,
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            st.level = .down; st.headline = "离线"; return st
        }
        st.connected = true
        st.level = .ok
        let models = obj["models"] as? [[String: Any]] ?? []
        st.headline = "\(models.count) 个模型可用"
        let def = obj["default"] as? String ?? ""
        if let m = models.first(where: { ($0["key"] as? String) == def }) {
            st.details = ["默认 \(m["name"] as? String ?? def)"]
        }
        return st
    }

    // 服务器面板 —— 需要账号密码登录
    private func fetchPanel() async -> CardState? {
        var st = CardState()
        let (d, code) = await get("https://status.yaoyc.fun/api/status")
        if code == 401 || code == 302 {
            st.needsLogin = true; st.level = .unknown; st.headline = "未登录"
            st.details = ["点击进入面板登录"]; return st
        }
        guard code == 200, let d,
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let servers = obj["servers"] as? [[String: Any]] else {
            st.level = .down; st.headline = "无法连接"; return st
        }
        st.connected = true
        let okOnes = servers.filter { ($0["ok"] as? Bool) == true }
        st.level = okOnes.isEmpty ? .down : (okOnes.count < servers.count ? .warn : .ok)
        st.headline = "\(okOnes.count)/\(servers.count) 台在线"
        if let first = okOnes.first {
            let cpu = first["cpu"] as? Double ?? 0
            let mem = first["mem_pct"] as? Double ?? 0
            st.progress = cpu / 100
            st.details = ["CPU \(Int(cpu))%", "内存 \(Int(mem))%"]
        }
        return st
    }

    // 个人站 —— 只看可达性
    private func fetchSite() async -> CardState? {
        var st = CardState()
        let (_, code) = await get("https://yaoyc.fun")
        st.connected = code == 200
        st.level = code == 200 ? .ok : .down
        st.headline = code == 200 ? "正常访问" : "无法访问"
        if code == 200 { st.details = ["YAO Tools 在线工具箱"] }
        return st
    }

    private func fmt(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - 首页（后台总览）

struct ContentView: View {
    @StateObject private var store = StatusStore()
    @State private var opened: Backend?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        header
                        ForEach(Backends.all) { b in
                            Button { opened = b } label: {
                                BackendCard(backend: b, state: store.cards[b.id])
                            }
                            .buttonStyle(.plain)
                        }
                        footer
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .refreshable { await store.refreshAll() }
            }
            .navigationBarHidden(true)
            .fullScreenCover(item: $opened) { b in
                BackendView(backend: b) {
                    Task { await store.refreshAll() }
                }
            }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            await store.refreshAll()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("后台总览")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(store.lastRefresh.formatted(date: .omitted, time: .shortened) + " 更新")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.ink2)
            }
            Spacer()
            Button {
                Task { await store.refreshAll() }
            } label: {
                Image(systemName: "arrow.trianglehead.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 38, height: 38)
                    .background(Theme.card, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.ok).frame(width: 6, height: 6)
            Text("下拉刷新 · 点卡片进入后台")
                .font(.system(size: 11))
                .foregroundStyle(Theme.ink2)
        }
        .padding(.top, 8)
    }
}

// MARK: - 后台卡片

struct BackendCard: View {
    let backend: Backend
    let state: CardState?

    var body: some View {
        HStack(spacing: 13) {
            // 图标
            Image(systemName: backend.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(backend.tint)
                .frame(width: 42, height: 42)
                .background(backend.tint.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(backend.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    if let s = state {
                        Circle().fill(s.dotColor).frame(width: 7, height: 7)
                    }
                }
                if let s = state {
                    Text(s.headline)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(s.level == .down ? Theme.down : Theme.ink2)
                    if !s.details.isEmpty {
                        Text(s.details.joined(separator: "  ·  "))
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.ink2.opacity(0.75))
                            .lineLimit(1)
                    }
                    if let p = s.progress {
                        ProgressView(value: p)
                            .tint(p > 0.8 ? Theme.warn : Theme.accent)
                            .scaleEffect(x: 1, y: 0.7, anchor: .center)
                            .padding(.top, 1)
                    }
                } else {
                    Text("读取中…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink2.opacity(0.6))
                }
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink2.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
    }
}

// MARK: - 后台详情（WebView + 进度条）

struct BackendView: View {
    let backend: Backend
    let onClose: () -> Void

    @StateObject private var engine = WebEngine()
    @State private var coordinator: NavigationCoordinator?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            LoadingBar(progress: engine.progress, visible: engine.loading || engine.progress > 0)
            if engine.failed {
                ErrorPane(message: engine.failedMessage) { engine.reload() }
            } else {
                WebViewContainer(webView: engine.webView)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            let c = NavigationCoordinator()
            c.engine = engine
            engine.webView.navigationDelegate = c
            engine.webView.uiDelegate = c
            coordinator = c
            engine.load(backend.url)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                    Text("总览").font(.system(size: 14))
                }
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 1) {
                Text(backend.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(backend.host)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.ink2.opacity(0.7))
            }

            Spacer()

            HStack(spacing: 14) {
                Button { engine.goBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(engine.webView.canGoBack ? Theme.ink : Theme.ink2.opacity(0.25))
                }.disabled(!engine.webView.canGoBack).buttonStyle(.plain)

                Button { engine.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.card)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
    }
}

struct ErrorPane: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("打不开这个后台")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            if !message.isEmpty {
                Text(message).font(.system(size: 12))
                    .foregroundStyle(Theme.ink2).multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            Button(action: retry) {
                Text("重试").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28).padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
            }.buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
