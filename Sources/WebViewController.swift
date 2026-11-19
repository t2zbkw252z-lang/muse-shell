import UIKit
import WebKit

final class WebViewController: UIViewController {
    private let baseURL = "https://muse.yuwan2026.online/"
    private var webView: WKWebView!
    private var didAskToken = false

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var prefersStatusBarHidden: Bool { false }
    override var prefersHomeIndicatorAutoHidden: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = NoAccessoryWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self

        view.addSubview(webView)
        view.keyboardLayoutGuide.followsUndockedKeyboard = true
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])
        self.webView = webView

        if let token = UserDefaults.standard.string(forKey: "panelToken"), !token.isEmpty {
            loadPanel(token: token)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        disableKeyboardAccessory(in: webView)
        if !didAskToken, (UserDefaults.standard.string(forKey: "panelToken") ?? "").isEmpty {
            didAskToken = true
            askForToken()
        }
    }

    private func loadPanel(token: String) {
        guard let url = URL(string: baseURL + "?token=" + token) else { return }
        webView.load(URLRequest(url: url))
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

    private func disableKeyboardAccessory(in view: UIView) {
        for subview in view.subviews {
            if let responder = subview as? UIResponder {
                let item = responder.inputAssistantItem
                item.leadingBarButtonGroups = []
                item.trailingBarButtonGroups = []
            }
            disableKeyboardAccessory(in: subview)
        }
    }
}

private final class NoAccessoryWebView: WKWebView {
    override var inputAssistantItem: UITextInputAssistantItem {
        let item = super.inputAssistantItem
        item.leadingBarButtonGroups = []
        item.trailingBarButtonGroups = []
        return item
    }

    override var inputAccessoryView: UIView? { nil }
}

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        disableKeyboardAccessory(in: webView)
        injectSafeAreaCSS()
    }

    private func injectSafeAreaCSS() {
        let top = Int(view.safeAreaInsets.top.rounded())
        let bottom = Int(view.safeAreaInsets.bottom.rounded())
        let css = """
        #chatView .chat-header{top:\(top)px !important}
        #chatView .msg-list{padding-top:calc(\(top)px + 12rem) !important}
        #chatView .input-float{padding-bottom:calc(\(bottom)px + 10px) !important}
        #chatView .input-float.kb-up{padding-bottom:6px !important}
        """
        let escaped = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let js = "var s=document.getElementById('native-safe')||document.createElement('style');s.id='native-safe';s.textContent=\"\(escaped)\";document.head.appendChild(s);"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}
