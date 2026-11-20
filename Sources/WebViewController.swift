import UIKit
import WebKit

final class WebViewController: UIViewController {
    private let baseURL = "https://muse.yuwan2026.online/"
    private var webView: WKWebView!
    private var didAskToken = false
    private var hapticBridge: HapticBridge?
    private var bundledToken: String {
        (Bundle.main.object(forInfoDictionaryKey: "PanelToken") as? String) ?? ""
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }
    override var prefersStatusBarHidden: Bool { false }
    override var prefersHomeIndicatorAutoHidden: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let bridge = HapticBridge()
        config.userContentController.add(bridge, name: "haptic")
        config.userContentController.addUserScript(WKUserScript(source: Self.hapticScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        self.hapticBridge = bridge

        let webView = NoAccessoryWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.scrollView.decelerationRate = .normal
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.keyboardDismissMode = .interactive
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = self
        webView.uiDelegate = self

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        self.webView = webView

        let savedToken = UserDefaults.standard.string(forKey: "panelToken") ?? ""
        let token = savedToken.isEmpty ? bundledToken : savedToken
        if !token.isEmpty {
            UserDefaults.standard.set(token, forKey: "panelToken")
            loadPanel(token: token)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        disableKeyboardAccessory(in: webView)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidShow), name: UIResponder.keyboardDidShowNotification, object: nil)
        if !didAskToken, (UserDefaults.standard.string(forKey: "panelToken") ?? "").isEmpty, bundledToken.isEmpty {
            didAskToken = true
            askForToken()
        }
    }

    private func loadPanel(token: String) {
        guard var comps = URLComponents(string: baseURL) else { return }
        comps.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970)))
        ]
        guard let url = comps.url else { return }
        let types: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
            self.webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        }
    }

    private func askForToken() {
        let alert = UIAlertController(
            title: "Muse 面板",
            message: "输入面板 token，只需一次",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "token"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "打开", style: .default) { [weak self, weak alert] _ in
            let token = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !token.isEmpty else { self?.didAskToken = false; self?.askForToken(); return }
            UserDefaults.standard.set(token, forKey: "panelToken")
            self?.loadPanel(token: token)
        })
        present(alert, animated: true)
    }

    @objc private func keyboardDidShow() {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        for window in windows { hideAssistantBar(in: window) }
    }

    private func hideAssistantBar(in view: UIView) {
        let name = NSStringFromClass(type(of: view))
        if name.contains("AssistantBar") || name.contains("CandidateBar") || name.contains("PredictionBar") || name.contains("KeyboardToolbar") {
            view.isHidden = true
            return
        }
        for sub in view.subviews { hideAssistantBar(in: sub) }
    }

    private func disableKeyboardAccessory(in view: UIView) {
        for subview in view.subviews {
            if let responder = subview as? UIResponder {
                let item = responder.inputAssistantItem
                item.leadingBarButtonGroups = []
                item.trailingBarButtonGroups = []
            }
            if let field = subview as? UITextField {
                field.autocorrectionType = .no
                field.spellCheckingType = .no
                field.smartQuotesType = .no
                field.smartDashesType = .no
            }
            if let textView = subview as? UITextView {
                textView.autocorrectionType = .no
                textView.spellCheckingType = .no
                textView.smartQuotesType = .no
                textView.smartDashesType = .no
            }
            disableKeyboardAccessory(in: subview)
        }
    }
}

private extension WebViewController {
    static let hapticScript = """
    (function(){
      if (window.__museHapticInstalled) return;
      window.__museHapticInstalled = true;
      var last = 0;
      document.addEventListener('touchstart', function(e){
        var el = e.target && e.target.closest ? e.target.closest('button, [role="button"], .status-card, .search-item, .msg-hit, .drawer-item, .switcher-item, .input-plus, .send-btn') : null;
        if (!el || el.disabled) return;
        var now = Date.now();
        if (now - last < 45) return;
        last = now;
        try { window.webkit.messageHandlers.haptic.postMessage('light'); } catch (_) {}
      }, {passive:true, capture:true});
    })();
    """
}

private final class HapticBridge: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "haptic" else { return }
        let kind = message.body as? String
        if kind == "selection" {
            let g = UISelectionFeedbackGenerator()
            g.prepare()
            g.selectionChanged()
            return
        }
        let style: UIImpactFeedbackGenerator.FeedbackStyle = (kind == "medium") ? .medium : .light
        let g = UIImpactFeedbackGenerator(style: style)
        g.prepare()
        g.impactOccurred()
    }
}

private final class NoAccessoryWebView: WKWebView {
    private let zeroAccessory = UIView(frame: .zero)

    override var inputAssistantItem: UITextInputAssistantItem {
        let item = super.inputAssistantItem
        item.leadingBarButtonGroups = []
        item.trailingBarButtonGroups = []
        return item
    }

    // 用 0 高度的自定义 accessory 顶掉系统那条空辅助栏
    override var inputAccessoryView: UIView? { zeroAccessory }
}

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        disableKeyboardAccessory(in: webView)
    }
}

extension WebViewController: WKUIDelegate {
    // window.open(url, "_blank") 之类的新窗口请求：交给系统浏览器打开，
    // 这样 http 的 DSH 链接在 WKWebView（ATS 限制）里也能正常跳转。
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        return nil
    }
}
