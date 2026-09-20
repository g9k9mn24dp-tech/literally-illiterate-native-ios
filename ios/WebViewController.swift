import UIKit
import WebKit

final class WebViewController: UIViewController, WKNavigationDelegate {

    private var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        StoreKitBridge.shared.attach(to: webView)
        loadApp()
    }

    private func loadApp() {
        guard let url = URL(string: "https://read-bright-verse.base44.app") else {
            return
        }

        webView.load(URLRequest(url: url))
    }
}
