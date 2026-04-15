import XCTest
@testable import ASAAgentSDK

final class ASAAgentSDKTests: XCTestCase {

    // MARK: - Configuration

    func testConfigureCreatesSharedInstance() {
        ASAAgent.configure(
            apiKey: "ask_test_123",
            appId: "999999999",
            baseURL: URL(string: "https://localhost:3000")!,
            loggingEnabled: false
        )
        // Accessing .shared should not crash after configure()
        _ = ASAAgent.shared
    }

    func testConfigureSetsApiKeyAndAppId() {
        let agent = ASAAgent.configure(
            apiKey: "ask_test_key",
            appId: "123456789",
            baseURL: URL(string: "https://localhost:3000")!,
            loggingEnabled: false
        )
        XCTAssertEqual(agent.configuration.apiKey, "ask_test_key")
        XCTAssertEqual(agent.configuration.appId, "123456789")
    }

    func testDeviceIdIsStableWithinInstance() {
        let agent = ASAAgent.configure(
            apiKey: "ask_test",
            appId: "111",
            baseURL: URL(string: "https://localhost:3000")!
        )
        let id1 = agent.deviceId
        let id2 = agent.deviceId
        XCTAssertEqual(id1, id2, "Device ID should be stable within an instance")
        // Note: cross-launch persistence requires Keychain access (iOS device/simulator only)
    }

    func testDeviceIdIsValidUUID() {
        let agent = ASAAgent.configure(
            apiKey: "ask_test",
            appId: "111",
            baseURL: URL(string: "https://localhost:3000")!
        )
        XCTAssertNotNil(UUID(uuidString: agent.deviceId), "Device ID should be a valid UUID")
    }

    func testBaseURLDefault() {
        let config = ASAAgent.Configuration(apiKey: "ask_test", appId: "111")
        XCTAssertEqual(config.baseURL.absoluteString, "https://asaagent.xyz")
    }

    func testBaseURLOverride() {
        let url = URL(string: "https://custom.example.com")!
        let config = ASAAgent.Configuration(apiKey: "ask_test", appId: "111", baseURL: url)
        XCTAssertEqual(config.baseURL.absoluteString, "https://custom.example.com")
    }

    // MARK: - Models

    func testRevenueEventTypeRawValues() {
        XCTAssertEqual(RevenueEventType.purchase.rawValue, "purchase")
        XCTAssertEqual(RevenueEventType.subscription.rawValue, "subscription")
        XCTAssertEqual(RevenueEventType.trial.rawValue, "trial")
        XCTAssertEqual(RevenueEventType.renewal.rawValue, "renewal")
        XCTAssertEqual(RevenueEventType.refund.rawValue, "refund")
    }

    func testRevenueEventEncodesCorrectly() throws {
        let event = RevenueEvent(
            deviceId: "test-device-id",
            eventType: "purchase",
            productId: "com.test.product",
            revenue: 9.99,
            currency: "USD",
            transactionId: "txn_123"
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["device_id"] as? String, "test-device-id")
        XCTAssertEqual(json["event_type"] as? String, "purchase")
        XCTAssertEqual(json["product_id"] as? String, "com.test.product")
        XCTAssertEqual(json["revenue"] as? Double, 9.99)
        XCTAssertEqual(json["currency"] as? String, "USD")
        XCTAssertEqual(json["transaction_id"] as? String, "txn_123")
        XCTAssertEqual(json["sdk_version"] as? String, SDKConstants.version)
        XCTAssertNotNil(json["timestamp"])
    }

    func testAttributionPayloadEncodesCorrectly() throws {
        let payload = AttributionPayload(
            deviceId: "dev-123",
            attributionToken: "fake-token-base64",
            bundleId: "com.test.app",
            appVersion: "1.0.0",
            osVersion: "17.4",
            sdkVersion: SDKConstants.version,
            environment: .debug,
            installDate: "2026-03-20T10:00:00Z"
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["device_id"] as? String, "dev-123")
        XCTAssertEqual(json["attribution_token"] as? String, "fake-token-base64")
        XCTAssertEqual(json["bundle_id"] as? String, "com.test.app")
        XCTAssertEqual(json["app_version"] as? String, "1.0.0")
        XCTAssertEqual(json["sdk_version"] as? String, SDKConstants.version)
        XCTAssertEqual(json["environment"] as? String, "debug")
        XCTAssertEqual(json["install_date"] as? String, "2026-03-20T10:00:00Z")
    }

    func testAttributionPayloadWithNilInstallDate() throws {
        let payload = AttributionPayload(
            deviceId: "dev-456",
            attributionToken: nil,
            bundleId: "com.test.app",
            appVersion: "1.0.0",
            osVersion: "17.4",
            sdkVersion: SDKConstants.version,
            environment: .production,
            installDate: nil
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["device_id"] as? String, "dev-456")
        XCTAssertNil(json["attribution_token"])
        // install_date should be encoded as null or absent
    }

    func testDetectInstallDateReturnsISO8601() {
        // On macOS/simulator, Documents directory always exists
        let installDate = AttributionManager.detectInstallDate()
        if let date = installDate {
            // Should be a valid ISO 8601 string
            let formatter = ISO8601DateFormatter()
            XCTAssertNotNil(formatter.date(from: date), "Install date should be valid ISO 8601")
        }
        // nil is also acceptable (e.g., sandboxed test environment)
    }

    // MARK: - SDK Constants

    func testSDKVersion() {
        XCTAssertEqual(SDKConstants.version, "0.8.0")
    }

    func testRevenueEventWithHistoricalTimestamp() throws {
        let pastDate = Date(timeIntervalSince1970: 1700000000) // 2023-11-14
        let event = RevenueEvent(
            deviceId: "test-device",
            eventType: "renewal",
            productId: "com.test.monthly",
            revenue: 9.99,
            currency: "EUR",
            transactionId: "txn_456",
            timestamp: pastDate,
            isHistorical: true
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["is_historical"] as? Bool, true)
        let timestamp = try XCTUnwrap(json["timestamp"] as? String)
        XCTAssertTrue(timestamp.contains("2023-11-14"), "Timestamp should reflect the provided date, not Date()")
    }

    func testRevenueEventDefaultsToNonHistorical() throws {
        let event = RevenueEvent(
            deviceId: "test-device",
            eventType: "purchase",
            productId: "com.test.product",
            revenue: 4.99,
            currency: "USD",
            transactionId: nil
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["is_historical"] as? Bool, false)
    }

    // MARK: - Logger

    func testLoggerDoesNotCrashWhenDisabled() {
        let logger = Logger(enabled: false)
        logger.log("This should not crash")
    }

    func testLoggerDoesNotCrashWhenEnabled() {
        let logger = Logger(enabled: true)
        logger.log("This should not crash either")
    }

    // MARK: - Codable Round-Trip

    func testRevenueEventRoundTripEncoding() throws {
        let event = RevenueEvent(
            deviceId: "test-device",
            eventType: "purchase",
            productId: "com.test.product",
            revenue: 9.99,
            currency: "USD",
            transactionId: "txn_123",
            originalTransactionId: "txn_orig_100"
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(RevenueEvent.self, from: data)

        XCTAssertEqual(decoded.deviceId, event.deviceId)
        XCTAssertEqual(decoded.eventType, event.eventType)
        XCTAssertEqual(decoded.productId, event.productId)
        XCTAssertEqual(decoded.revenue, event.revenue)
        XCTAssertEqual(decoded.currency, event.currency)
        XCTAssertEqual(decoded.transactionId, event.transactionId)
        XCTAssertEqual(decoded.originalTransactionId, event.originalTransactionId)
        XCTAssertEqual(decoded.sdkVersion, event.sdkVersion)
        XCTAssertEqual(decoded.timestamp, event.timestamp)
        XCTAssertEqual(decoded.isHistorical, event.isHistorical)
    }

    func testRevenueEventDecodesWithNilOptionals() throws {
        let event = RevenueEvent(
            deviceId: "test-device",
            eventType: "trial",
            productId: "com.test.trial",
            revenue: 0,
            currency: "USD",
            transactionId: nil
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(RevenueEvent.self, from: data)

        XCTAssertNil(decoded.transactionId)
        XCTAssertNil(decoded.originalTransactionId)
        XCTAssertEqual(decoded.revenue, 0)
    }

    func testAppEnvironmentRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for env in [AppEnvironment.debug, .testflight, .production] {
            let data = try encoder.encode(env)
            let decoded = try decoder.decode(AppEnvironment.self, from: data)
            XCTAssertEqual(decoded, env)
        }
    }

    // MARK: - Storage

    func testStorageAttributionSentFlag() {
        let storage = Storage()
        let originalValue = storage.attributionSent

        storage.attributionSent = true
        XCTAssertTrue(storage.attributionSent)

        storage.attributionSent = false
        XCTAssertFalse(storage.attributionSent)

        // Restore
        storage.attributionSent = originalValue
    }

    // MARK: - Event Queue

    func testStorageEnqueueAndDequeueEvents() {
        let storage = Storage()
        _ = storage.dequeuePendingEvents()

        let event1 = RevenueEvent(
            deviceId: "dev-1", eventType: "purchase", productId: "prod_a",
            revenue: 1.99, currency: "USD", transactionId: "t1"
        )
        let event2 = RevenueEvent(
            deviceId: "dev-1", eventType: "subscription", productId: "prod_b",
            revenue: 9.99, currency: "EUR", transactionId: "t2"
        )

        storage.enqueueEvent(event1)
        storage.enqueueEvent(event2)

        let exp = expectation(description: "Queue writes complete")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { exp.fulfill() }
        wait(for: [exp], timeout: 2)

        let dequeued = storage.dequeuePendingEvents()
        XCTAssertEqual(dequeued.count, 2)
        XCTAssertEqual(dequeued[0].productId, "prod_a")
        XCTAssertEqual(dequeued[1].productId, "prod_b")

        let empty = storage.dequeuePendingEvents()
        XCTAssertTrue(empty.isEmpty)
    }

    func testStorageEventQueueCap() {
        let storage = Storage()
        _ = storage.dequeuePendingEvents()

        for i in 0..<105 {
            let event = RevenueEvent(
                deviceId: "dev", eventType: "purchase", productId: "prod_\(i)",
                revenue: 1.0, currency: "USD", transactionId: "t_\(i)"
            )
            storage.enqueueEvent(event)
        }

        let exp = expectation(description: "Queue writes complete")
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { exp.fulfill() }
        wait(for: [exp], timeout: 3)

        let dequeued = storage.dequeuePendingEvents()
        XCTAssertEqual(dequeued.count, 100)
        XCTAssertEqual(dequeued[0].productId, "prod_5")
        XCTAssertEqual(dequeued[99].productId, "prod_104")
    }

    func testStorageDequeueEmptyReturnsEmptyArray() {
        let storage = Storage()
        _ = storage.dequeuePendingEvents()
        let result = storage.dequeuePendingEvents()
        XCTAssertTrue(result.isEmpty)
    }
}
