import SwiftUI
import WebKit

// MARK: - 后台定义

struct Backend: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let icon: String
    let urlString: String
    var url: URL { URL(string: urlString)! }
}

enum Backends {
    static let all: [Backend] = [
        Backend(id: "panel", name: "服务器面板", host: "status.yaoyc.fun",
                icon: "server.rack", urlString: "https://status.yaoyc.fun"),
        Backend(id: "clock", name: "时钟控制台", host: "pet.yaoyc.fun/control",
                icon: "clock", urlString: "https://pet.yaoyc.fun/control"),
        Backend(id: "pet", name: "Hermes 状态", host: "pet.yaoyc.fun",
                icon: "sparkles", urlString: "https://pet.yaoyc.fun"),
        Backend(id: "chat", name: "YAO AI", host: "chat.yaoyc.fun",
                icon: "bubble.left.and.bubble.right", urlString: "https://chat.yaoyc.fun"),
        Backend(id: "site", name: "个人站", host: "yaoyc.fun",
                icon: "square.grid.2x2", urlString: "https://yaoyc.fun")
    ]
}

// MARK: - 主题（白底、细线、克制）

enum Theme {
    static let bg     = Color(red: 0.980, green: 0.980, blue: 0.984)   // #FAFAFB
    static let card   = Color.white
    static let ink    = Color(red: 0.098, green: 0.098, blue: 0.118)   // #19191E
    static let ink2   = Color(red: 0.478, green: 0.478, blue: 0.510)   // #7A7A82
    static let ink3   = Color(red: 0.702, green: 0.702, blue: 0.729)   // #B3B3BA
    static let line   = Color(red: 0.902, green: 0.902, blue: 0.918)   // #E6E6EA
    static let accent = Color(red: 0.098, green: 0.098, blue: 0.118)   // 主色=近黑，图标用
    static let accent2 = Color(red: 0.616, green: 0.549, blue: 0.965)
    static let ok     = Color(red: 0.180, green: 0.702, blue: 0.443)
    static let warn   = Color(red: 0.949, green: 0.639, blue: 0.145)
    static let down   = Color(red: 0.878, green: 0.286, blue: 0.286)
}

// MARK: - 状态模型

struct CardState {
    var connected: Bool = false
    var needsLogin: Bool = false
    var level: Level = .unknown
    var headline: String = "—"
    var rows: [(String, String)] = []     // 左侧标签 / 右侧值
    var progress: Double? = nil

    enum Level { case ok, warn, down, unknown }

    var dotColor: Color {
        switch level {
        case .ok: return Theme.ok
        case .warn: return Theme.warn
        case .down: return Theme.down
        case .unknown: return Theme.ink3
        }
    }

    var levelText: String {
        switch level {
        case .ok: return "正常"
        case .warn: return "异常"
        case .down: return "离线"
        case .unknown: return "未连接"
        }
    }
}

// MARK: - 数据

@MainActor
final class StatusStore: ObservableObject {
    @Published var cards: [String: CardState] = [:]
    @Published var lastRefresh = Date()
    @Published var events: [String] = []
    var pendingEvents: [String] = []

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
        let r = await (pet, clock, chat, panel, site)
        for (k, v) in [("pet", r.0), ("clock", r.1), ("chat", r.2), ("panel", r.3), ("site", r.4)] {
            if let v { cards[k] = v }
        }
        if !pendingEvents.isEmpty { events = pendingEvents; pendingEvents = [] }
        lastRefresh = Date()
    }

    private func get(_ s: String) async -> (Data?, Int) {
        guard let u = URL(string: s) else { return (nil, 0) }
        var req = URLRequest(url: u)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        do {
            let (d, resp) = try await session.data(for: req)
            return (d, (resp as? HTTPURLResponse)?.statusCode ?? 0)
        } catch { return (nil, 0) }
    }

    private func fetchPet() async -> CardState? {
        var st = CardState()
        let (d, code) = await get("https://pet.yaoyc.fun/api/stats")
        guard code == 200, let d,
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            st.level = .down; st.headline = "无法连接"; return st
        }
        st.connected = true
        st.level = .ok
        let t = o["total"] as? [String: Any] ?? [:]
        let calls = t["calls"] as? Int ?? 0
        st.headline = "\(calls) 次调用"
        st.rows.append(("输入", fmt(t["in"] as? Int ?? 0)))
        st.rows.append(("输出", fmt(t["out"] as? Int ?? 0)))
        if let ms = o["models"] as? [[String: Any]], let f = ms.first {
            st.rows.append(("主力", f["model"] as? String ?? "—"))
        }
        let (sd, sc) = await get("https://pet.yaoyc.fun/api/status")
        if sc == 200, let sd,
           let so = try? JSONSerialization.jsonObject(with: sd) as? [String: Any] {
            let state = so["state"] as? String ?? ""
            let text = so["text"] as? String ?? ""
            st.rows.insert(("状态", state == "idle" ? "空闲" : text), at: 0)
            if let evs = so["events"] as? [[String: Any]] {
                var out: [String] = []
                for e in evs.prefix(6) {
                    let t = e["time"] as? String ?? ""
                    let x = e["text"] as? String ?? ""
                    if !x.isEmpty { out.append("\(t)  \(x)") }
                }
                pendingEvents = out
            }
        }
        return st
    }

    private func fetchClock() async -> CardState? {
        var st = CardState()
        let (d, code) = await get("https://pet.yaoyc.fun/api/clock/hub/status")
        if code == 401 {
            st.needsLogin = true; st.headline = "未登录"
            st.rows = [("提示", "进入后输入配对码")]
            return st
        }
        guard code == 200, let d,
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            st.level = .down; st.headline = "无法连接"; return st
        }
        st.connected = true
        let online = o["online"] as? Bool ?? false
        st.level = online ? .ok : .down
        st.headline = online ? "设备在线" : "设备离线"
        if let inner = o["status"] as? [String: Any] {
            st.rows.append(("固件", inner["firmware"] as? String ?? "—"))
            st.rows.append(("WiFi", inner["connectedSsid"] as? String ?? "—"))
            if let fps = inner["fps"] as? Int { st.rows.append(("帧率", "\(fps) fps")) }
        }
        if let ts = o["updatedAt"] as? Double, !online {
            let mins = Int(Date().timeIntervalSince1970 - ts / 1000) / 60
            st.rows.append(("离线", mins > 120 ? "\(mins / 60) 小时" : "\(mins) 分钟"))
        }
        return st
    }

    private func fetchChat() async -> CardState? {
        var st = CardState()
        let (d, code) = await get("https://chat.yaoyc.fun/api/models")
        guard code == 200, let d,
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            st.level = .down; st.headline = "无法连接"; return st
        }
        st.connected = true; st.level = .ok
        let ms = o["models"] as? [[String: Any]] ?? []
        st.headline = "\(ms.count) 个模型"
        let def = o["default"] as? String ?? ""
        if let m = ms.first(where: { ($0["key"] as? String) == def }) {
            st.rows.append(("默认", m["name"] as? String ?? def))
        }
        if ms.count > 1, let second = ms[1]["name"] as? String {
            st.rows.append(("其他", second))
        }
        return st
    }

    private func fetchPanel() async -> CardState? {
        var st = CardState()
        let (d, code) = await get("https://status.yaoyc.fun/api/status")
        if code == 401 || code == 302 || code == 0 {
            st.needsLogin = true; st.headline = "未登录"
            st.rows = [("提示", "进入面板登录后显示")]
            return st
        }
        guard code == 200, let d,
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let sv = o["servers"] as? [[String: Any]] else {
            st.level = .down; st.headline = "无法连接"; return st
        }
        st.connected = true
        let okOnes = sv.filter { ($0["ok"] as? Bool) == true }
        st.level = okOnes.isEmpty ? .down : (okOnes.count < sv.count ? .warn : .ok)
        st.headline = "\(okOnes.count)/\(sv.count) 台在线"
        if let f = okOnes.first {
            let cpu = f["cpu"] as? Double ?? 0
            st.progress = cpu / 100
            st.rows.append(("CPU", "\(Int(cpu))%"))
            st.rows.append(("内存", "\(Int(f["mem_pct"] as? Double ?? 0))%"))
            if let n = f["name"] as? String { st.rows.append(("主机", n)) }
        }
        return st
    }

    private func fetchSite() async -> CardState? {
        var st = CardState()
        let (_, code) = await get("https://yaoyc.fun")
        st.connected = code == 200
        st.level = code == 200 ? .ok : .down
        st.headline = code == 200 ? "正常" : "无法访问"
        if code == 200 { st.rows = [("站点", "YAO Tools 工具箱")] }
        return st
    }

    private func fmt(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - 首页

struct ContentView: View {
    @StateObject private var store = StatusStore()
    @State private var opened: Backend?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        summaryBar
                        sectionTitle("后台")
                        cardSection
                        sectionTitle("最近事件")
                        eventBlock
                        Spacer(minLength: 30)
                    }
                }
                .refreshable { await store.refreshAll() }
            }
            .navigationTitle("后台总览")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refreshAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
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

    // 顶部概览：三格数字
    private var summaryBar: some View {
        let total = Backends.all.count
        let online = Backends.all.filter { store.cards[$0.id]?.level == .ok }.count
        let issues = Backends.all.filter {
            let lv = store.cards[$0.id]?.level
            return lv == .down || lv == .warn
        }.count
        return HStack(spacing: 0) {
            summaryCell("\(total)", "个后台")
            divider
            summaryCell("\(online)", "正常", color: Theme.ok)
            divider
            summaryCell("\(issues)", "异常", color: issues > 0 ? Theme.down : Theme.ink)
        }
        .padding(.vertical, 14)
        .background(Theme.card)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
        .padding(.bottom, 20)
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(width: 0.5, height: 26)
    }

    private func summaryCell(_ num: String, _ label: String, color: Color = Theme.ink) -> some View {
        VStack(spacing: 3) {
            Text(num)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.ink2)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.ink2)
            .textCase(.uppercase)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cardSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(Backends.all.enumerated()), id: \.element.id) { idx, b in
                Button { opened = b } label: {
                    BackendRow(backend: b, state: store.cards[b.id])
                }
                .buttonStyle(.plain)
                if idx < Backends.all.count - 1 {
                    Rectangle().fill(Theme.line).frame(height: 0.5).padding(.leading, 56)
                }
            }
        }
        .background(Theme.card)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
        .padding(.bottom, 20)
    }

    private var eventBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.events.isEmpty {
                Text("暂无事件")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, 20).padding(.vertical, 16)
            } else {
                ForEach(Array(store.events.prefix(6).enumerated()), id: \.offset) { i, e in
                    Text(e)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.ink2)
                        .padding(.horizontal, 20).padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if i < min(store.events.count, 6) - 1 {
                        Rectangle().fill(Theme.line).frame(height: 0.5).padding(.leading, 20)
                    }
                }
            }
        }
        .background(Theme.card)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
    }
}

// MARK: - 一行后台

struct BackendRow: View {
    let backend: Backend
    let state: CardState?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: backend.icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.ink)
                .frame(width: 28, height: 28)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(backend.name)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    if let s = state {
                        HStack(spacing: 4) {
                            Circle().fill(s.dotColor).frame(width: 5, height: 5)
                            Text(s.levelText)
                                .font(.system(size: 10.5))
                                .foregroundStyle(s.level == .down ? Theme.down : Theme.ink3)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(backend.host)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                }

                if let s = state {
                    if s.rows.isEmpty {
                        Text(s.headline)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.ink2)
                    } else {
                        // 指标行：两列对齐
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(s.rows.prefix(3).enumerated()), id: \.offset) { _, pair in
                                HStack(spacing: 6) {
                                    Text(pair.0)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Theme.ink3)
                                        .frame(width: 34, alignment: .leading)
                                    Text(pair.1)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(Theme.ink2)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    if let p = s.progress {
                        ProgressView(value: p)
                            .tint(p > 0.8 ? Theme.warn : Theme.ink2)
                            .scaleEffect(x: 1, y: 0.55, anchor: .center)
                            .padding(.top, 2)
                    }
                } else {
                    Text("读取中")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink3)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ink3)
                .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

// MARK: - 详情：WebView + 进度

struct BackendView: View {
    let backend: Backend
    let onClose: () -> Void

    @StateObject private var engine = WebEngine()
    @State private var coordinator: NavigationCoordinator?

    var body: some View {
        VStack(spacing: 0) {
            LoadingBar(progress: engine.progress, visible: engine.loading || engine.progress > 0)
            if engine.failed {
                ErrorPane(message: engine.failedMessage) { engine.reload() }
            } else {
                WebViewContainer(webView: engine.webView)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(backend.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button { engine.goBack() } label: {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(engine.webView.canGoBack ? Theme.ink : Theme.ink3)
                    }
                    .disabled(!engine.webView.canGoBack)

                    Button { engine.reload() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
        }
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
                .foregroundStyle(Theme.ink2)
            Text("打不开这个后台")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.ink)
            if !message.isEmpty {
                Text(message).font(.system(size: 12))
                    .foregroundStyle(Theme.ink2).multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            Button(action: retry) {
                Text("重试")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 9)
                    .background(Theme.ink, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
