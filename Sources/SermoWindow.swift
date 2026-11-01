import AppKit
import WebKit

/// Sermo 独立版主窗口：只加载 QuotOS Aether 内置页。
///
/// 与 Lawlearn 里的 Sermo 小窗相比，这里去掉了「切换网页版 AI」那条路径，
/// 因为独立版只做 Aether。其余行为保持一致：单例窗口、外链交系统浏览器、
/// Aether → Swift 的云端桥、localStorage 持久化（对话历史与图鉴靠它留存）。
@MainActor
final class SermoWindowController: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {

    static let shared = SermoWindowController()

    private var window: NSWindow?
    private var webView: WKWebView?
    /// 页面是否已经装好设置面板（didFinish 可能被调用多次）
    private var settingsInstalled = false

    private override init() { super.init() }

    // MARK: - 入口

    func show() {
        if let window {
            ensureOnScreen(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        buildWindow()
    }

    /// 窗口若与所有屏幕都不相交（拔掉副屏、改分辨率后会这样），搬回主显示器中央
    private func ensureOnScreen(_ win: NSWindow) {
        let frame = win.frame
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        guard !visible, let vf = NSScreen.screens.first?.visibleFrame else { return }
        win.setFrameOrigin(NSPoint(
            x: vf.midX - frame.width / 2,
            y: vf.midY - frame.height / 2
        ))
    }

    /// 菜单「设置…」调用：把页面里的设置面板打开
    func openSettings() {
        show()
        guard let wv = webView else { return }
        wv.evaluateJavaScript("window.__sermoOpenSettings && window.__sermoOpenSettings();", completionHandler: nil)
    }

    private func buildWindow() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Sermo"
        win.titlebarAppearsTransparent = false
        // 居中到主显示器。
        // 不能信 win.center()，它会挑「当前活动屏幕」；也不能信 NSScreen.main，
        // 它的定义是「有键盘焦点的窗口所在屏幕」，启动瞬间还没有 key window 时
        // 会退回鼠标所在屏幕——鼠标停在副屏上，窗口就开到副屏去了，看着像没启动。
        // NSScreen.screens 的顺序固定：第 0 个就是带菜单栏的主显示器。
        let home = NSScreen.screens.first
        if let vf = home?.visibleFrame {
            win.setFrameOrigin(NSPoint(
                x: vf.midX - win.frame.width / 2,
                y: vf.midY - win.frame.height / 2
            ))
        } else {
            win.center()
        }
        win.isReleasedWhenClosed = false
        win.tabbingMode = .disallowed
        win.minSize = NSSize(width: 380, height: 520)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        let uc = WKUserContentController()
        uc.add(self, name: "aetherBridge")
        config.userContentController = uc

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 640), configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = false
        wv.autoresizingMask = [.width, .height]
        // macOS 26 起 SDK 不再向 Swift 暴露 WKWebView.scrollView，改从子视图取底层滚动视图
        if let scroll = wv.subviews.compactMap({ $0 as? NSScrollView }).first {
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = false
            scroll.verticalScrollElasticity = .allowed
            scroll.contentInsets = NSEdgeInsetsZero
        }
        win.contentView = wv

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
        self.webView = wv

        wv.loadHTMLString(SermoHTML.aether, baseURL: URL(string: "https://quotos.local/"))
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        // Aether 是本地页：只放行本地请求，外链交系统浏览器
        if url.host == nil || url.host == "quotos.local" {
            decisionHandler(.allow)
        } else {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        DispatchQueue.main.async {
            let ready = CloudModelBridge.shared.isConfigured
            webView.evaluateJavaScript("window.__aetherCloudConfigured = \(ready ? "true" : "false");", completionHandler: nil)
            if !self.settingsInstalled {
                webView.evaluateJavaScript(SermoSettingsJS.install) { _, err in
                    if let err { NSLog("[Sermo] 设置面板注入失败: \(err.localizedDescription)") }
                }
                self.settingsInstalled = true
            }
            self.pushPrefs(to: webView)
        }
    }

    // MARK: - 设置面板数据

    /// 把当前 Key / 服务商 / 模型推给页面，页面的设置面板据此回填
    private func pushPrefs(to wv: WKWebView?) {
        guard let wv else { return }
        let bridge = CloudModelBridge.shared
        let providers: [[String: String]] = CloudProviderCatalog.all.map {
            ["id": $0.id, "name": $0.name, "defaultModel": $0.defaultModel]
        }
        let payload: [String: Any] = [
            "key": bridge.apiKey,
            "providerID": bridge.providerID,
            "model": bridge.model,
            "providers": providers,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        wv.evaluateJavaScript("window.__sermoPrefs && window.__sermoPrefs(\(json));", completionHandler: nil)
    }

    // MARK: - WKScriptMessageHandler

    // 回调由 WebKit 后台串行队列触发，SDK 却把 WKScriptMessage 标为 @MainActor；
    // 整段解析与主线程工作都放进 DispatchQueue.main.async，避免隐式 hop 破坏主执行器引用。
    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                          didReceive message: WKScriptMessage) {
        DispatchQueue.main.async { [weak self] in
            guard let self, message.name == "aetherBridge",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            switch type {
            case "api":
                self.handleAPIRequest(body)
            case "settings":
                self.handleSettings(body)
            default:
                break
            }
        }
    }

    private func handleAPIRequest(_ body: [String: Any]) {
        guard let reqId = body["reqId"] as? Int,
              let system = body["system"] as? String,
              let messages = body["messages"] as? [[String: String]] else { return }
        let reasoning = body["reasoning"] as? String
        let wv = self.webView
        CloudModelBridge.shared.completeChat(
            system: system,
            messages: messages,
            reasoning: reasoning,
            maxTokens: 1400,
            onDelta: { _ in },
            onDone: { text in
                Self.aetherApiCallback(to: wv, reqId: reqId, ok: true, text: text)
            },
            onError: { err in
                Self.aetherApiCallback(to: wv, reqId: reqId, ok: false, text: err)
            }
        )
    }

    private func handleSettings(_ body: [String: Any]) {
        guard let action = body["action"] as? String else { return }
        let bridge = CloudModelBridge.shared
        switch action {
        case "get":
            pushPrefs(to: webView)
        case "save":
            if let key = body["key"] as? String { bridge.apiKey = key }
            if let pid = body["providerID"] as? String, !pid.isEmpty { bridge.providerID = pid }
            if let m = body["model"] as? String { bridge.model = m }
            let configured = bridge.isConfigured ? "true" : "false"
            webView?.evaluateJavaScript("window.__aetherCloudConfigured = \(configured);", completionHandler: nil)
            webView?.evaluateJavaScript(SermoSettingsJS.saved, completionHandler: nil)
            pushPrefs(to: webView)
            NSLog("[Sermo] 已保存设置：服务商=\(bridge.providerID) 模型=\(bridge.effectiveModel) 已配置=\(bridge.isConfigured)")
        default:
            break
        }
    }

    private static func aetherApiCallback(to wv: WKWebView?, reqId: Int, ok: Bool, text: String) {
        guard let wv else { return }
        let okStr = ok ? "true" : "false"
        // 把回复正文安全转成 JS 字符串字面量：包一层数组再剥掉首尾方括号，得到合法的 JSON 字符串
        var jsText = "''"
        if let data = try? JSONSerialization.data(withJSONObject: [text]),
           let s = String(data: data, encoding: .utf8),
           s.hasPrefix("[\""), s.hasSuffix("\"]") {
            jsText = String(s.dropFirst().dropLast())
        }
        let js = "window.__aetherApiResult(\(reqId), \(okStr), \(jsText))"
        wv.evaluateJavaScript(js, in: nil, in: .page) { result in
            if case .failure(let e) = result { NSLog("[Sermo] API 回调执行失败: \(e.localizedDescription)") }
        }
    }
}
