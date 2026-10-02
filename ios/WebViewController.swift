import UIKit
import WebKit
import AuthenticationServices

final class WebViewController: UIViewController,
                               WKNavigationDelegate,
                               WKScriptMessageHandler,
                               ASAuthorizationControllerDelegate,
                               ASAuthorizationControllerPresentationContextProviding {

    private var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        let contentController = WKUserContentController()

        // Tell Base44 that this page is running inside the native iOS wrapper
        let wrapperScript = WKUserScript(
            source: "window.__isIOSWrapper = true;",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(wrapperScript)

        // Native Apple Sign-In bridge
        contentController.add(self, name: "appleSignIn")

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController = contentController

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

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: "appleSignIn"
        )
    }

    private func loadApp() {
        guard let url = URL(
            string: "https://read-bright-verse.base44.app"
        ) else {
            return
        }

        webView.load(URLRequest(url: url))
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "appleSignIn" else {
            return
        }

        DispatchQueue.main.async {
            self.startAppleSignIn()
        }
    }

    // MARK: - Apple Sign In

    private func startAppleSignIn() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()

        request.requestedScopes = [
            .fullName,
            .email
        ]

        let controller = ASAuthorizationController(
            authorizationRequests: [request]
        )

        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential
                as? ASAuthorizationAppleIDCredential else {

            sendAppleError("Invalid Apple Sign-In credential.")
            return
        }

        let identityToken =
            credential.identityToken.flatMap {
                String(data: $0, encoding: .utf8)
            }

        let authorizationCode =
            credential.authorizationCode.flatMap {
                String(data: $0, encoding: .utf8)
            }

        let fullName = PersonNameComponentsFormatter()
            .string(from: credential.fullName ?? PersonNameComponents())

        var payload: [String: Any] = [
            "user": credential.user
        ]

        if let identityToken {
            payload["identityToken"] = identityToken
        }

        if let authorizationCode {
            payload["authorizationCode"] = authorizationCode
        }

        if let email = credential.email {
            payload["email"] = email
        }

        if !fullName.isEmpty {
            payload["fullName"] = fullName
        }

        sendAppleCallback(payload)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let authError = error as? ASAuthorizationError,
           authError.code == .canceled {

            sendAppleCallback([
                "cancelled": true
            ])

            return
        }

        sendAppleError("Sign in with Apple failed.")
    }

    func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {

        if let window = view.window {
            return window
        }

        return UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
            ?? UIWindow()
    }

    // MARK: - JavaScript callback

    private func sendAppleCallback(_ payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(
                withJSONObject: payload
              ),
              let json = String(
                data: data,
                encoding: .utf8
              ) else {

            return
        }

        let script = """
        if (window.__appleSignInCallback) {
            window.__appleSignInCallback(\(json));
        }
        """

        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(script)
        }
    }

    private func sendAppleError(_ message: String) {
        sendAppleCallback([
            "error": message
        ])
    }
}
