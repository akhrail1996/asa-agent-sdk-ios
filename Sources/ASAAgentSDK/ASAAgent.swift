import Foundation

/// ASA Agent SDK — lightweight Apple Search Ads attribution and revenue tracking.
///
/// ## Quick Start
/// ```swift
/// // 1. Configure on app launch
/// ASAAgent.configure(apiKey: "ask_...", appId: "123456789")
///
/// // 2. Track revenue after purchases
/// ASAAgent.trackRevenue(
///     productId: "com.app.premium",
///     revenue: 9.99,
///     currency: "USD",
///     type: .purchase,
///     transactionId: "2000000123456789"
/// )
/// ```
public final class ASAAgent {

    // MARK: - Public Configuration

    /// Configuration options for the SDK.
    public struct Configuration {
        /// Your API key from the ASA Agent dashboard (starts with `ask_`).
        public let apiKey: String
        /// Your app's Adam ID (numeric App Store ID).
        public let appId: String
        /// Base URL for the ASA Agent API. Override for testing.
        public var baseURL: URL
        /// Enable verbose logging to console. Default: `false`.
        public var loggingEnabled: Bool

        public init(
            apiKey: String,
            appId: String,
            baseURL: URL = URL(string: "https://asaagent.xyz")!,
            loggingEnabled: Bool = false
        ) {
            self.apiKey = apiKey
            self.appId = appId
            self.baseURL = baseURL
            self.loggingEnabled = loggingEnabled
        }
    }

    // MARK: - Singleton

    /// Shared instance. Only accessible after `configure()`.
    public static var shared: ASAAgent {
        guard let instance = _shared else {
            fatalError("ASAAgent.configure() must be called before accessing shared instance.")
        }
        return instance
    }

    private static var _shared: ASAAgent?

    // MARK: - Public API

    /// Initialize the SDK. Call once on app launch (e.g. in `application(_:didFinishLaunchingWithOptions:)`
    /// or in your SwiftUI `App.init()`).
    ///
    /// This will:
    /// 1. Generate a persistent anonymous device ID
    /// 2. Collect the AdServices attribution token (if not already sent)
    /// 3. Send the token to ASA Agent for keyword-level attribution resolution
    ///
    /// - Parameters:
    ///   - apiKey: Your SDK API key from the ASA Agent dashboard.
    ///   - appId: Your app's Adam ID.
    ///   - baseURL: Override the API base URL (for testing). Default: production.
    ///   - loggingEnabled: Enable debug logging. Default: `false`.
    @discardableResult
    public static func configure(
        apiKey: String,
        appId: String,
        baseURL: URL? = nil,
        loggingEnabled: Bool = false
    ) -> ASAAgent {
        var config = Configuration(apiKey: apiKey, appId: appId, loggingEnabled: loggingEnabled)
        if let baseURL = baseURL {
            config.baseURL = baseURL
        }

        let instance = ASAAgent(configuration: config)
        _shared = instance

        // Fire-and-forget attribution collection
        instance.collectAttributionIfNeeded()

        // Flush any revenue events that failed in previous sessions
        instance.flushPendingEvents()

        return instance
    }

    /// Track a revenue event (purchase, subscription, trial, renewal, or refund).
    ///
    /// Call this after a successful StoreKit transaction. The SDK will send the event
    /// to ASA Agent, which joins it with the attribution data to compute keyword-level LTV.
    ///
    /// - Parameters:
    ///   - productId: The StoreKit product identifier (e.g. `com.app.premium_monthly`).
    ///   - revenue: Revenue amount in the transaction currency.
    ///   - currency: ISO 4217 currency code (e.g. "USD", "EUR").
    ///   - type: The type of revenue event.
    ///   - transactionId: The StoreKit transaction ID (for deduplication).
    ///   - timestamp: When the transaction originally occurred. Defaults to now.
    ///   - isHistorical: Whether this is a backfilled historical transaction.
    public static func trackRevenue(
        productId: String,
        revenue: Double,
        currency: String,
        type: RevenueEventType = .purchase,
        transactionId: String? = nil,
        originalTransactionId: String? = nil,
        timestamp: Date = Date(),
        isHistorical: Bool = false
    ) {
        shared.sendRevenueEvent(
            productId: productId,
            revenue: revenue,
            currency: currency,
            type: type,
            transactionId: transactionId,
            originalTransactionId: originalTransactionId,
            timestamp: timestamp,
            isHistorical: isHistorical
        )
    }

    /// Manually trigger attribution collection. Normally called automatically by `configure()`.
    /// Use this if you need to retry after a network failure.
    public static func retryAttribution() {
        shared.collectAttributionIfNeeded(force: true)
    }

    /// The anonymous device ID used by this SDK instance.
    /// Persisted across app launches via Keychain.
    public var deviceId: String {
        storage.deviceId
    }

    // MARK: - Internal

    let configuration: Configuration
    let network: NetworkClient
    let storage: Storage
    let attribution: AttributionManager
    let logger: Logger

    private init(configuration: Configuration) {
        self.configuration = configuration
        self.logger = Logger(enabled: configuration.loggingEnabled)
        self.storage = Storage()
        self.network = NetworkClient(
            baseURL: configuration.baseURL,
            apiKey: configuration.apiKey,
            appId: configuration.appId,
            logger: logger
        )
        self.attribution = AttributionManager(
            network: network,
            storage: storage,
            logger: logger
        )

        logger.log("ASAAgent configured — appId: \(configuration.appId), deviceId: \(storage.deviceId)")
    }

    private func collectAttributionIfNeeded(force: Bool = false) {
        attribution.collectAndSendIfNeeded(deviceId: storage.deviceId, force: force)
    }

    private func sendRevenueEvent(
        productId: String,
        revenue: Double,
        currency: String,
        type: RevenueEventType,
        transactionId: String?,
        originalTransactionId: String? = nil,
        timestamp: Date = Date(),
        isHistorical: Bool = false
    ) {
        let event = RevenueEvent(
            deviceId: storage.deviceId,
            eventType: type.rawValue,
            productId: productId,
            revenue: revenue,
            currency: currency,
            transactionId: transactionId,
            originalTransactionId: originalTransactionId,
            timestamp: timestamp,
            isHistorical: isHistorical
        )

        sendEventWithRetry(event)
    }

    /// Send an event, retry once after 5 seconds on failure, then persist to queue.
    private func sendEventWithRetry(_ event: RevenueEvent, isRetry: Bool = false) {
        network.sendEvent(event) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.logger.log("Revenue event sent: \(event.eventType) \(event.revenue) \(event.currency) [\(event.productId)]")
            case .failure(let error):
                if isRetry {
                    self.logger.log("Revenue event retry failed: \(error.localizedDescription). Queuing for next session.")
                    self.storage.enqueueEvent(event)
                } else {
                    self.logger.log("Revenue event failed: \(error.localizedDescription). Retrying in 5s...")
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) { [weak self] in
                        self?.sendEventWithRetry(event, isRetry: true)
                    }
                }
            }
        }
    }

    /// Retry sending any revenue events queued from previous sessions.
    private func flushPendingEvents() {
        let pendingEvents = storage.dequeuePendingEvents()
        guard !pendingEvents.isEmpty else { return }
        logger.log("Flushing \(pendingEvents.count) pending revenue event(s) from previous session.")
        for event in pendingEvents {
            sendEventWithRetry(event)
        }
    }
}
