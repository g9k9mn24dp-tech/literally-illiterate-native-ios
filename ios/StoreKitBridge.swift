import Foundation
import WebKit

@MainActor
final class StoreKitBridge: NSObject, WKScriptMessageHandler {

    static let shared = StoreKitBridge()

    private weak var webView: WKWebView?

    private override init() {
        super.init()
    }

    func attach(to webView: WKWebView) {
        self.webView = webView

        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: "storeKit"
        )

        webView.configuration.userContentController.add(
            self,
            name: "storeKit"
        )
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "storeKit" else {
            return
        }

        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            sendError("Invalid StoreKit request")
            return
        }

        switch action {
        case "loadProducts":
            Task {
                await loadProducts()
            }

        case "purchase":
            guard let productID = body["productId"] as? String else {
                sendError("Missing productId")
                return
            }

            Task {
                await purchase(productID: productID)
            }

        default:
            sendError("Unknown StoreKit action")
        }
    }

    private func loadProducts() async {
        await StoreKitManager.shared.loadProducts()

        let products = StoreKitManager.shared.products.map { product in
            [
                "id": product.id,
                "displayName": product.displayName,
                "description": product.description,
                "displayPrice": product.displayPrice
            ]
        }

        sendToWeb(
            event: "storeKitProducts",
            data: products
        )
    }

    private func purchase(productID: String) async {
        let result = await StoreKitManager.shared.purchase(
            productID: productID
        )

        switch result {
        case .success(let productID, let transactionID):
            sendToWeb(
                event: "storeKitPurchaseSuccess",
                data: [
                    "productId": productID,
                    "transactionId": transactionID
                ]
            )

        case .cancelled:
            sendToWeb(
                event: "storeKitPurchaseCancelled",
                data: [:]
            )

        case .pending:
            sendToWeb(
                event: "storeKitPurchasePending",
                data: [:]
            )

        case .failed(let message):
            sendError(message)
        }
    }

    private func sendError(_ message: String) {
        sendToWeb(
            event: "storeKitPurchaseError",
            data: ["message": message]
        )
    }

    private func sendToWeb(event: String, data: Any) {
        guard let webView else {
            return
        }

        guard JSONSerialization.isValidJSONObject(data),
              let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let json = String(data: jsonData, encoding: .utf8) else {
            return
        }

        let javascript = """
        window.dispatchEvent(
            new CustomEvent('\(event)', {
                detail: \(json)
            })
        );
        """

        webView.evaluateJavaScript(javascript)
    }
}
