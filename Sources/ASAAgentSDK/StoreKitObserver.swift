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

    /// One-time scan of all historical transactions to backfill any
    /// that were missed (e.g. trials before SDK tracked them).
    /// Server-side dedup by transaction_id prevents duplicates.
    func syncHistoricalTransactions() {
        Task(priority: .background) {
            for await result in Transaction.all {
                guard case .verified(let txn) = result else { continue }
                if isSandbox(txn) { continue }
                guard let (type, revenue) = classifyTransaction(txn) else { continue }
                let currency = resolveCurrency(txn)
                ASAAgent.trackRevenue(
                    productId: txn.productID,
                    revenue: revenue,
                    currency: currency,
                    type: type,
                    transactionId: String(txn.id)
                )
            }
        }
    }

    private func handleVerifiedTransaction(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else { return }

        if isSandbox(transaction) {
            await transaction.finish()
            return
        }

        guard let (type, revenue) = classifyTransaction(transaction) else {
            await transaction.finish()
            return
        }

        let currency = resolveCurrency(transaction)

        ASAAgent.trackRevenue(
            productId: transaction.productID,
            revenue: revenue,
            currency: currency,
            type: type,
            transactionId: String(transaction.id)
        )

        await transaction.finish()
    }

    /// Check if transaction is from a sandbox/Xcode environment.
    private func isSandbox(_ transaction: StoreKit.Transaction) -> Bool {
        if #available(iOS 16.0, *) {
            return transaction.environment == .sandbox || transaction.environment == .xcode
        }
        return false
    }

    /// Classify transaction into event type and revenue. Returns nil for unsupported types.
    private func classifyTransaction(_ transaction: StoreKit.Transaction) -> (RevenueEventType, Double)? {
        let revenue = NSDecimalNumber(decimal: transaction.price ?? 0).doubleValue

        switch transaction.productType {
        case .autoRenewable:
            if revenue == 0 {
                return (.trial, 0)
            } else if transaction.isUpgraded {
                return (.subscription, revenue)
            } else {
                return (.renewal, revenue)
            }
        case .consumable, .nonConsumable, .nonRenewable:
            return revenue > 0 ? (.purchase, revenue) : nil
        default:
            return nil
        }
    }

    /// Resolve the transaction currency code.
    private func resolveCurrency(_ transaction: StoreKit.Transaction) -> String {
        if #available(iOS 16.0, *) {
            return transaction.currency?.identifier ?? "USD"
        }
        return "USD"
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

        // One-time backfill: scan historical transactions to catch
        // trials/renewals missed by earlier SDK versions.
        let syncKey = SDKConstants.historicalSyncKey
        if !UserDefaults.standard.bool(forKey: syncKey) {
            observer.syncHistoricalTransactions()
            UserDefaults.standard.set(true, forKey: syncKey)
            shared.logger.log("Historical transaction sync started.")
        }
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
