#if os(iOS)
import Foundation
import StoreKit

/// Automatic StoreKit 2 transaction observer.
///
/// Listens for verified transactions and automatically reports revenue to ASA Agent.
/// Enable with `ASAAgent.enableAutoTracking()` after `configure()`.
///
/// For StoreKit 1 or manual tracking, use `ASAAgent.trackRevenue()` directly.
@available(iOS 15.0, *)
public final class StoreKitObserver {

    private var updateTask: Task<Void, Never>?

    /// Start listening for StoreKit 2 transactions.
    public func startObserving() {
        updateTask = Task(priority: .background) {
            for await result in Transaction.updates {
                await self.handleVerifiedTransaction(result)
            }
        }
    }

    /// Stop listening.
    public func stopObserving() {
        updateTask?.cancel()
        updateTask = nil
    }

    private func handleVerifiedTransaction(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else { return }

        let type: RevenueEventType
        let revenue: Double

        switch transaction.productType {
        case .autoRenewable:
            type = transaction.isUpgraded ? .subscription : .renewal
            revenue = NSDecimalNumber(decimal: transaction.price ?? 0).doubleValue
        case .consumable, .nonConsumable:
            type = .purchase
            revenue = NSDecimalNumber(decimal: transaction.price ?? 0).doubleValue
        case .nonRenewable:
            type = .purchase
            revenue = NSDecimalNumber(decimal: transaction.price ?? 0).doubleValue
        default:
            return
        }

        guard revenue > 0 else { return }

        let currency: String
        if #available(iOS 16.0, *) {
            currency = transaction.currency?.identifier ?? "USD"
        } else {
            currency = "USD"
        }

        ASAAgent.trackRevenue(
            productId: transaction.productID,
            revenue: revenue,
            currency: currency,
            type: type,
            transactionId: String(transaction.id)
        )

        // Finish the transaction
        await transaction.finish()
    }
}

// MARK: - ASAAgent Extension

extension ASAAgent {

    private static var _storeKitObserver: Any?

    /// Enable automatic StoreKit 2 revenue tracking.
    /// Listens for all verified transactions and reports them to ASA Agent.
    /// Requires iOS 15+.
    @available(iOS 15.0, *)
    public static func enableAutoTracking() {
        let observer = StoreKitObserver()
        observer.startObserving()
        _storeKitObserver = observer
        shared.logger.log("Auto-tracking enabled (StoreKit 2).")
    }

    /// Disable automatic StoreKit 2 revenue tracking.
    @available(iOS 15.0, *)
    public static func disableAutoTracking() {
        if let observer = _storeKitObserver as? StoreKitObserver {
            observer.stopObserving()
        }
        _storeKitObserver = nil
    }
}
#endif
