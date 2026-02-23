import Foundation

/// Manages AdServices token collection and submission to ASA Agent backend.
final class AttributionManager {

    private let network: NetworkClient
    private let storage: Storage
    private let logger: Logger

    init(network: NetworkClient, storage: Storage, logger: Logger) {
        self.network = network
        self.storage = storage
        self.logger = logger
    }

    /// Collect the AdServices attribution token and send it to the backend.
    /// No-ops if already sent (unless `force` is true).
    func collectAndSendIfNeeded(deviceId: String, force: Bool = false) {
        guard force || !storage.attributionSent else {
            logger.log("Attribution already sent, skipping.")
            return
        }

        // AdServices is only available on iOS 14.3+
        guard #available(iOS 14.3, *) else {
            logger.log("iOS 14.3+ required for AdServices. Skipping attribution.")
            return
        }

        // Collect token on a background queue (may involve system call)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            let token = self.getAdServicesToken()

            guard let token = token else {
                self.logger.log("No AdServices token available (organic install or error).")
                return
            }

            self.logger.log("AdServices token collected (\(token.count) chars). Sending to backend...")

            let payload = AttributionPayload(
                deviceId: deviceId,
                attributionToken: token,
                bundleId: Bundle.main.bundleIdentifier,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                sdkVersion: SDKConstants.version
            )

            self.network.sendAttribution(payload) { [weak self] result in
                switch result {
                case .success:
                    self?.storage.attributionSent = true
                    self?.logger.log("Attribution sent successfully.")
                case .failure(let error):
                    self?.logger.log("Attribution send failed: \(error.localizedDescription). Will retry next launch.")
                }
            }
        }
    }

    /// Collect the AdServices attribution token.
    /// Returns `nil` for organic installs or if AdServices is unavailable.
    @available(iOS 14.3, *)
    private func getAdServicesToken() -> String? {
        // Dynamic lookup to avoid hard link — allows SDK to compile even without AdServices
        guard let adServicesClass = NSClassFromString("AAAttribution") else {
            logger.log("AAAttribution class not found. Ensure AdServices.framework is linked.")
            return nil
        }

        let selector = NSSelectorFromString("attributionTokenWithError:")

        guard adServicesClass.responds(to: selector) else {
            logger.log("attributionTokenWithError: not available.")
            return nil
        }

        // Use the direct import approach
        return Self.fetchToken()
    }

    /// Fetch token using AdServices framework.
    @available(iOS 14.3, *)
    private static func fetchToken() -> String? {
        // We use dynamic invocation to keep the SDK compilable without AdServices linked
        let handle = dlopen("/System/Library/Frameworks/AdServices.framework/AdServices", RTLD_LAZY)
        guard handle != nil else { return nil }
        defer { dlclose(handle) }

        typealias AttributionTokenFunc = @convention(c) (AnyClass, Selector, UnsafeMutablePointer<NSError?>) -> NSString?

        guard let cls = NSClassFromString("AAAttribution") else { return nil }
        let sel = NSSelectorFromString("attributionTokenWithError:")
        guard let method = class_getClassMethod(cls, sel) else { return nil }
        let imp = method_getImplementation(method)

        let function = unsafeBitCast(imp, to: AttributionTokenFunc.self)
        var error: NSError?
        let token = function(cls, sel, &error)

        if let error = error {
            // Error code 1 = no attribution (organic install), not a real error
            if error.code != 1 {
                NSLog("[ASAAgent] AdServices error: \(error)")
            }
            return nil
        }

        return token as String?
    }
}
