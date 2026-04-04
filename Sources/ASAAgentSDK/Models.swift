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
    /// ISO 8601 timestamp of when the app was first installed on this device.
    /// Server compares this to the attribution timestamp to distinguish
    /// new installs from existing users who updated to the SDK version.
    let installDate: String?
}

/// Revenue event payload sent to the backend.
struct RevenueEvent: Encodable {
    let deviceId: String
    let eventType: String
    let productId: String
    let revenue: Double
    let currency: String
    let transactionId: String?
    let originalTransactionId: String?
    let sdkVersion: String = SDKConstants.version
    let timestamp: String
    let environment: AppEnvironment = AppEnvironment.current
    let isHistorical: Bool

    init(
        deviceId: String,
        eventType: String,
        productId: String,
        revenue: Double,
        currency: String,
        transactionId: String?,
        originalTransactionId: String? = nil,
        timestamp: Date = Date(),
        isHistorical: Bool = false
    ) {
        self.deviceId = deviceId
        self.eventType = eventType
        self.productId = productId
        self.revenue = revenue
        self.currency = currency
        self.transactionId = transactionId
        self.originalTransactionId = originalTransactionId
        self.timestamp = ISO8601DateFormatter().string(from: timestamp)
        self.isHistorical = isHistorical
    }
}

/// SDK constants.
enum SDKConstants {
    static let version = "0.6.0"
    static let keychainService = "com.asaagent.sdk"
    static let keychainDeviceIdKey = "device_id"
    static let attributionSentKey = "com.asaagent.sdk.attribution_sent"
    static let historicalSyncKey = "com.asaagent.sdk.historical_sync_v1"
}
