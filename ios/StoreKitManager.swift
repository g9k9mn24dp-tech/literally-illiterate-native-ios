import Foundation
import StoreKit

@MainActor
final class StoreKitManager: ObservableObject {

    static let shared = StoreKitManager()

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPurchasing = false
    @Published var lastError: String?

    private let productIDs = [
        "com.codemavericks.literallyilliterate.points5000",
        "com.codemavericks.literallyilliterate.points15000",
        "com.codemavericks.literallyilliterate.points40000",
        "com.codemavericks.literallyilliterate.points100000",
        "com.codemavericks.literallyilliterate.points250000"
    ]

    private init() {}

    func loadProducts() async {
        do {
            products = try await Product.products(for: productIDs)
            products.sort { $0.price < $1.price }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func purchase(productID: String) async -> PurchaseResult {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let availableProducts = try await Product.products(for: [productID])

            guard let product = availableProducts.first else {
                return .failed("Product not found")
            }

            let result = try await product.purchase()

            switch result {

            case .success(let verification):
                switch verification {

                case .verified(let transaction):
                    let transactionID = String(transaction.id)

                    await transaction.finish()

                    return .success(
                        productID: transaction.productID,
                        transactionID: transactionID
                    )

                case .unverified:
                    return .failed("Transaction could not be verified")
                }

            case .userCancelled:
                return .cancelled

            case .pending:
                return .pending

            @unknown default:
                return .failed("Unknown purchase result")
            }

        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

enum PurchaseResult {
    case success(productID: String, transactionID: String)
    case cancelled
    case pending
    case failed(String)
}
