import SwiftUI
import WebKit

// MARK: - 站点定义

struct ConsoleSite: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let urlString: String
    var url: URL { URL(string: urlString)! }
    /// 该站点需要登录（决定首次打开时是否显示登录提示）
    let needsAuth: Bool
}

enum ConsoleSites {
    static let all: [ConsoleSite] = [
        ConsoleSite(id: "panel", title: "服务器面板", subtitle: "监控 · 模型 · 状态",
                    systemImage: "server.rack", urlString: "https://status.yaoyc.fun",
                    needsAuth: true),
        ConsoleSite(id: "clock", title: "时钟控制台", subtitle: "ESP32 · 宠物 · 任务",
                    systemImage: "clock.badge.checkmark", urlString: "https://pet.yaoyc.fun/control",
                    needsAuth: true),
        ConsoleSite(id: "chat", title: "YAO AI", subtitle: "在线对话",
                    systemImage: "bubble.left.and.bubble.right", urlString: "https://chat.yaoyc.fun",
                    needsAuth: false),
        ConsoleSite(id: "site", title: "个人站", subtitle: "YAO Tools 工具箱",
                    systemImage: "square.grid.2x2", urlString: "https://yaoyc.fun",
                    needsAuth: false)
    ]
}

// MARK: - 进度条

/// 顶部加载进度条：真实 estimatedProgress + 平滑动画 + 缓爬到 90% 的兜底。
struct LoadingBar: View {
    var progress: Double
    var visible: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.clear
                LinearGradient(colors: [Theme.ink, Theme.accent2],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
                    .animation(.easeOut(duration: 0.28), value: progress)
            }
        }
        .frame(height: 3)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.22), value: visible)
        .allowsHitTesting(false)
    }
}

// MARK: - 网页引擎（把 WKWebView 的进度桥接给 SwiftUI）

@MainActor
final class WebEngine: ObservableObject {
    @Published var progress: Double = 0
    @Published var loading: Bool = false
    @Published var currentTitle: String = ""
    @Published var currentURL: URL?
    @Published var failed: Bool = false
    @Published var failedMessage: String = ""
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    let webView: WKWebView
    private var progressObserver: NSKeyValueObservation?
    private var fakeCrawl: Timer?
    private var fakeValue: Double = 0
    private var hasFinishedOnce = false

    init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()    // 登录态、Cookie 跨标签共用
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let view = WKWebView(frame: .zero, configuration: config)
        view.allowsBackForwardNavigationGestures = true
        view.allowsLinkPreview = true
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.isOpaque = false
        view.backgroundColor = UIColor(Theme.bg)
        view.scrollView.backgroundColor = UIColor(Theme.bg)
        // 让页面认为自己是 Safari，避免部分站点降级或拦截内嵌浏览器
        view.customUserAgent = nil
        self.webView = view
        observeProgress()
    }

    private func observeProgress() {
        progressObserver = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            let value = webView.estimatedProgress
            Task { @MainActor in
                guard let self else { return }
                // 真实进度只往前推，避免动画回跳
                if value > self.progress { self.progress = value }
                if value >= 1.0 {
                    self.finishLoading()
                }
            }
        }
    }

    private func startFakeCrawl() {
        stopFakeCrawl()
        fakeValue = max(progress, 0.08)
        fakeCrawl = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // 缓爬到 90%，越接近越慢；真实进度更快时以真实为准
                guard self.fakeValue < 0.9 else { return }
                let remaining = 0.9 - self.fakeValue
                self.fakeValue += remaining * 0.10 + 0.002
                if self.fakeValue > self.progress { self.progress = self.fakeValue }
            }
        }
    }

    private func stopFakeCrawl() {
        fakeCrawl?.invalidate()
        fakeCrawl = nil
    }

    func beginLoading() {
        failed = false
        failedMessage = ""
        loading = true
        progress = 0
        startFakeCrawl()
    }

    func finishLoading() {
        stopFakeCrawl()
        progress = 1.0
        loading = false
        hasFinishedOnce = true
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        // 进度条收尾后隐藏
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 320_000_000)
            if !self.loading { self.progress = 0 }
        }
    }

    func fail(_ message: String) {
        stopFakeCrawl()
        loading = false
        progress = 0
        failed = true
        failedMessage = message
    }

    func load(_ url: URL) {
        beginLoading()
        // 带上 Cookie 才能让各后台的登录态生效
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        let headers = HTTPCookie.requestHeaderFields(with: cookies)
        var request = URLRequest(url: url, timeoutInterval: 30)
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        webView.load(request)
    }

    func reload() {
        if webView.url == nil {
            return
        }
        beginLoading()
        if failed {
            webView.load(URLRequest(url: webView.url ?? URL(string: "about:blank")!,
                                    timeoutInterval: 30))
        } else {
            webView.reload()
        }
    }

    /// 切标签时如果没有加载过，就首次加载
    func ensureLoaded(_ url: URL) {
        if webView.url == nil {
            load(url)
        }
    }

    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }
}

// MARK: - WKWebView 包装

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - 导航代理（挂在 App 层，单独一个文件更清楚）

final class NavigationCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var engine: WebEngine?

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.engine?.beginLoading()
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.engine?.currentURL = webView.url
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let engine = self?.engine else { return }
            engine.currentTitle = webView.title ?? ""
            engine.currentURL = webView.url
            engine.finishLoading()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let ns = error as NSError
        guard ns.code != NSURLErrorCancelled else { return }
        Task { @MainActor [weak self] in
            self?.engine?.fail(ns.localizedDescription)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let ns = error as NSError
        guard ns.code != NSURLErrorCancelled else { return }
        Task { @MainActor [weak self] in
            self?.engine?.fail(ns.localizedDescription)
        }
    }

    // 处理 _blank 及 window.open
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    // 站内导航放行；非 https（tel/mailto 等）交给系统
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
        if let scheme = url.scheme?.lowercased(), scheme != "http", scheme != "https", scheme != "about" {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
