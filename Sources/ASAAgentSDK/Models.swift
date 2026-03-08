import Foundation

// MARK: - Revenue Event Types

/// The type of revenue event being tracked.
public enum RevenueEventType: String, Sendable {
    /// One-time purchase (consumable or non-consumable).
    case purchase
    /// Initial subscription purchase.
    case subscription
    /// Free trial started.
    case trial
    /// Subscription renewed.
    case renewal
    /// Refund issued.
    case refund
}

// MARK: - Environment Detection

/// The runtime environment of the app.
enum AppEnvironment: String, Encodable {
    case debug
    case testflight
    case production

    /// Detect the current environment automatically.
    static var current: AppEnvironment {
        #if DEBUG
        return .debug
        #else
        if let receiptURL = Bundle.main.appStoreReceiptURL,
           receiptURL.lastPathComponent == "sandboxReceipt" {
            return .testflight
        }
        return .production
        #endif
    }
}

// MARK: - Internal Models

/// Attribution payload sent to the backend.
struct AttributionPayload: Encodable {
    let deviceId: String
    let attributionToken: String?
    let bundleId: String?
    let appVersion: String?
    let osVersion: String
    let sdkVersion: String
    let environment: AppEnvironment
}

/// Revenue event payload sent to the backend.
struct RevenueEvent: Encodable {
    let deviceId: String
    let eventType: String
    let productId: String
    let revenue: Double
    let currency: String
    let transactionId: String?
    let sdkVersion: String = SDKConstants.version
    let timestamp: String = ISO8601DateFormatter().string(from: Date())
    let environment: AppEnvironment = AppEnvironment.current
}

/// SDK constants.
enum SDKConstants {
    static let version = "0.4.1"
    static let keychainService = "com.asaagent.sdk"
    static let keychainDeviceIdKey = "device_id"
    static let attributionSentKey = "com.asaagent.sdk.attribution_sent"
    static let historicalSyncKey = "com.asaagent.sdk.historical_sync_v1"
}
