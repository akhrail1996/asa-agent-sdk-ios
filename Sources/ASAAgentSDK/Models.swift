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

// MARK: - Internal Models

/// Attribution payload sent to the backend.
struct AttributionPayload: Encodable {
    let deviceId: String
    let attributionToken: String?
    let bundleId: String?
    let appVersion: String?
    let osVersion: String
    let sdkVersion: String
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
}

/// SDK constants.
enum SDKConstants {
    static let version = "0.1.0"
    static let keychainService = "com.asaagent.sdk"
    static let keychainDeviceIdKey = "device_id"
    static let attributionSentKey = "com.asaagent.sdk.attribution_sent"
}
