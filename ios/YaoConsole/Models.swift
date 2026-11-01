import SwiftUI

// MARK: - 后台定义

struct Backend: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let icon: String
    let urlString: String
    let group: String          // 「后台」= 用户侧页面，「管理」= 站长管理后台
    var url: URL { URL(string: urlString)! }

    init(id: String, name: String, host: String, icon: String, urlString: String,
         group: String = "管理") {
        self.id = id; self.name = name; self.host = host
        self.icon = icon; self.urlString = urlString; self.group = group
    }
}

enum Backends {
    static let all: [Backend] = [
        // ===== 用户侧 =====
        Backend(id: "panel", name: "服务器面板", host: "status.yaoyc.fun",
                icon: "server.rack", urlString: "https://status.yaoyc.fun", group: "后台"),
        Backend(id: "clock", name: "时钟控制台", host: "pet.yaoyc.fun/control",
                icon: "clock", urlString: "https://pet.yaoyc.fun/control", group: "后台"),
        Backend(id: "pet", name: "Hermes 状态", host: "pet.yaoyc.fun",
                icon: "sparkles", urlString: "https://pet.yaoyc.fun", group: "后台"),
        Backend(id: "chat", name: "YAO AI", host: "chat.yaoyc.fun",
                icon: "bubble.left.and.bubble.right", urlString: "https://chat.yaoyc.fun", group: "后台"),
        Backend(id: "site", name: "个人站", host: "yaoyc.fun",
                icon: "square.grid.2x2", urlString: "https://yaoyc.fun", group: "后台"),

        // ===== 管理后台 =====
        Backend(id: "chat_admin", name: "YAO AI 管理", host: "chat.yaoyc.fun/admin",
                icon: "person.2.badge.gearshape", urlString: "https://chat.yaoyc.fun/admin"),
        Backend(id: "panel_admin", name: "服务器面板管理", host: "status.yaoyc.fun/admin",
                icon: "server.rack", urlString: "https://status.yaoyc.fun/admin"),
        Backend(id: "panel_super", name: "超管设置", host: "status.yaoyc.fun/super",
                icon: "key.horizontal", urlString: "https://status.yaoyc.fun/super"),
        Backend(id: "server_ssh", name: "远程终端", host: "ssh.yaoyc.fun",
                icon: "terminal", urlString: "https://ssh.yaoyc.fun"),
    ]

    static var userSide: [Backend] { all.filter { $0.group == "后台" } }
    static var adminSide: [Backend] { all.filter { $0.group == "管理" } }
}

// MARK: - 状态模型

struct CardState {
    var connected: Bool = false
    var needsLogin: Bool = false
    var level: Level = .unknown
    var headline: String = "—"
    var rows: [(String, String)] = []
    var progress: Double? = nil

    enum Level { case ok, warn, down, unknown }

    var dotColor: Color {
        switch level {
        case .ok:      return Color(red: 0.05, green: 0.66, blue: 0.40)
        case .warn:    return Color(red: 0.95, green: 0.63, blue: 0.15)
        case .down:    return Color(red: 0.87, green: 0.26, blue: 0.26)
        case .unknown: return Color(red: 0.72, green: 0.71, blue: 0.80)
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

// MARK: - 数据拉取

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
        // 管理后台可达性（页面能打开 = 可达；登录态由 WebView 自己带）
        async let adminGroup = probeAdmins()
        let admins = await adminGroup
        for (k, v) in admins { cards[k] = v }
        if !pendingEvents.isEmpty { events = pendingEvents; pendingEvents = [] }
        lastRefresh = Date()
    }

    /// 浅探每个管理后台页面能否打开（只发 HEAD/GET，不提交任何东西）
    private func probeAdmins() async -> [(String, CardState)] {
        let targets = Backends.adminSide
        var out: [(String, CardState)] = []
        await withTaskGroup(of: (String, CardState).self) { group in
            for b in targets {
                group.addTask { [weak self] in
                    guard let self else { return (b.id, CardState()) }
                    var st = CardState()
                    let (_, code) = await self.get(b.urlString)
                    switch code {
                    case 200:
                        st.level = .ok; st.headline = "页面可访问"
                    case 401, 403:
                        st.needsLogin = true; st.headline = "需要登录"
                    case 302, 301:
                        st.needsLogin = true; st.headline = "跳转登录"
                    case 0:
                        st.level = .down; st.headline = "无法连接"
                    default:
                        st.level = .warn; st.headline = "HTTP \(code)"
                    }
                    if st.headline == "页面可访问" {
                        st.rows = [("地址", b.host)]
                    }
                    return (b.id, st)
                }
            }
            for await item in group { out.append(item) }
        }
        return out
    }

    private func get(_ s: String) async -> (Data?, Int) {
        guard let u = URL(string: s) else { return (nil, 0) }
        var req = URLRequest(url: u)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)",
                     forHTTPHeaderField: "User-Agent")
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
                    let tm = e["time"] as? String ?? ""
                    let x = e["text"] as? String ?? ""
                    if !x.isEmpty { out.append(tm.isEmpty ? x : "\(tm)  \(x)") }
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
