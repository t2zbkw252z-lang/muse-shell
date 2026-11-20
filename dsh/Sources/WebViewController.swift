import UIKit
import WebKit

final class WebViewController: UIViewController {
    private let panelBase = "https://muse.yuwan2026.online"
    private let defaultPanelToken = "8cf94db4cd50e2621e0a1d87370269f1"
    private var webView: WKWebView!
    private var hapticBridge: HapticBridge?
    private var didLoad = false
    private var statusLabel: UILabel!

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }
    override var prefersStatusBarHidden: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let bridge = HapticBridge()
        config.userContentController.add(bridge, name: "haptic")
        config.userContentController.addUserScript(WKUserScript(source: Self.hapticScript,
                                                               injectionTime: .atDocumentEnd,
                                                               forMainFrameOnly: true))
        self.hapticBridge = bridge

        let webView = NoAccessoryWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.keyboardDismissMode = .interactive
        webView.allowsBackForwardNavigationGestures = true
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

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.text = "启动中…"
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
        self.statusLabel = label
        label.isHidden = false
    }

    private var watchdog: Timer?

    private func startLoadWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.setStatus("10 秒还没加载出来\n可能是 ATS 拦了 http\n或者网络不通")
        }
    }

    private func setStatus(_ text: String, visible: Bool = true) {
        statusLabel.text = text
        statusLabel.isHidden = !visible
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        disableKeyboardAccessory(in: webView)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidShow),
                                              name: UIResponder.keyboardDidShowNotification, object: nil)
        if !didLoad {
            didLoad = true
            loadTarget()
        }
    }

    private var panelToken: String {
        let saved = UserDefaults.standard.string(forKey: "panelToken") ?? ""
        return saved.isEmpty ? defaultPanelToken : saved
    }

    /// DSH 的 token 每次重启都会变，所以启动时先去面板拿当前链接，再打开。
    private func loadTarget() {
        guard var comps = URLComponents(string: panelBase + "/api/dsh/link") else { return }
        comps.queryItems = [URLQueryItem(name: "token", value: panelToken)]
        guard let url = comps.url else { return }

        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        setStatus("正在取 DSH 链接…")
        showLoading(true)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self else { return }
            var target = ""
            if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                target = (obj["url"] as? String) ?? ""
            }
            DispatchQueue.main.async {
                self.showLoading(false)
                if target.isEmpty {
                    self.setStatus("取链接失败，点重试")
                    self.showOffline(); return
                }
                self.setStatus("正在打开 DSH…\n" + target)
                self.startLoadWatchdog()
                guard let u = URL(string: target) else { return }
                let types: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]
                WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
                    self.webView.load(URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
                }
            }
        }.resume()
    }

    private var loadingView: UIView?
    private var offlineView: UIView?

    private func showLoading(_ on: Bool) {
        if on {
            guard loadingView == nil else { return }
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            spinner.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            loadingView = spinner
        } else {
            loadingView?.removeFromSuperview()
            loadingView = nil
        }
    }

    private func showOffline() {
        guard offlineView == nil else { return }
        let box = UIView()
        box.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(box)
        NSLayoutConstraint.activate([
            box.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            box.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        let label = UILabel()
        label.text = "连不上面板，点一下重试"
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        let btn = UIButton(type: .system)
        btn.setTitle("重试", for: .normal)
        btn.addTarget(self, action: #selector(retry), for: .touchUpInside)
        box.addSubview(label)
        box.addSubview(btn)
        label.translatesAutoresizingMaskIntoConstraints = false
        btn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: box.topAnchor),
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            btn.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 12),
            btn.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            btn.bottomAnchor.constraint(equalTo: box.bottomAnchor)
        ])
        offlineView = box
    }

    @objc private func retry() {
        offlineView?.removeFromSuperview()
        offlineView = nil
        loadTarget()
    }

    @objc private func keyboardDidShow() {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        for window in windows { hideAssistantBar(in: window) }
    }

    private func hideAssistantBar(in view: UIView) {
        let name = NSStringFromClass(type(of: view))
        if name.contains("AssistantBar") || name.contains("CandidateBar")
            || name.contains("PredictionBar") || name.contains("KeyboardToolbar") {
            view.isHidden = true
            return
        }
        for sub in view.subviews { hideAssistantBar(in: sub) }
    }

    private func disableKeyboardAccessory(in view: UIView) {
        for subview in view.subviews { disableKeyboardAccessory(in: subview) }
    }

    static let hapticScript = """
    (function(){
      if (window.__dshHapticInstalled) return;
      window.__dshHapticInstalled = true;
      var last = 0;
      var sel = 'button, [role="button"], [role="tab"], [role="menuitem"], [role="option"], [role="switch"], [role="checkbox"], [role="radio"], [role="link"], a[href], summary, label, [tabindex]:not([tabindex="-1"])';
      document.addEventListener('touchstart', function(e){
        var el = e.target && e.target.closest ? e.target.closest(sel) : null;
        if (!el && e.target && e.target.closest) {
          var cur = e.target.closest('*');
          while (cur && cur !== document.body) {
            var st = window.getComputedStyle(cur);
            if (st && st.cursor === 'pointer') { el = cur; break; }
            cur = cur.parentElement;
          }
        }
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

    override var inputAccessoryView: UIView? { zeroAccessory }
}

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        setStatus("开始加载…")
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        setStatus("已收到内容，渲染中…")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        disableKeyboardAccessory(in: webView)
        watchdog?.invalidate()
        statusLabel?.isHidden = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        setStatus("打开失败：" + error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        setStatus("加载失败：" + error.localizedDescription)
    }
}

extension WebViewController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        return nil
    }
}
