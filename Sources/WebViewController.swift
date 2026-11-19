import UIKit
import WebKit

final class WebViewController: UIViewController {
    private let startURL = URL(string: "https://muse.yuwan2026.online/?token=8cf94db4cd50e2621e0a1d87370269f1")!
    private var webView: WKWebView!

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
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        self.webView = webView
        webView.load(URLRequest(url: startURL))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        disableKeyboardAccessory(in: webView)
    }

    private func disableKeyboardAccessory(in view: UIView) {
        for subview in view.subviews {
            if let textInput = subview as? UITextInput, let responder = subview as? UIResponder {
                let item = responder.inputAssistantItem
                item.leadingBarButtonGroups = []
                item.trailingBarButtonGroups = []
                _ = textInput
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
    }
}
