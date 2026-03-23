import Foundation
import AdServices

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

        // Collect token on a background queue (may involve system call)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            let token = self.getAdServicesToken()
            let environment = AppEnvironment.current

            if let token = token {
                self.logger.log("AdServices token collected (\(token.count) chars), environment: \(environment.rawValue). Sending to backend...")
            } else {
                self.logger.log("No AdServices token (organic install or AdServices unavailable), " +
                    "environment: \(environment.rawValue). Reporting to backend...")
            }

            let installDate = Self.detectInstallDate()

            let payload = AttributionPayload(
                deviceId: deviceId,
                attributionToken: token,
                bundleId: Bundle.main.bundleIdentifier,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                sdkVersion: SDKConstants.version,
                environment: environment,
                installDate: installDate
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

    /// Detect when the app was first installed by checking the Documents directory creation date.
    /// This date persists across app updates but resets on reinstall — which is correct,
    /// since a reinstall IS a new install from the SDK's perspective.
    /// Returns an ISO 8601 string, or nil if the date can't be determined.
    static func detectInstallDate() -> String? {
        guard let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: docsURL.path)
            guard let creationDate = attrs[.creationDate] as? Date else { return nil }
            return ISO8601DateFormatter().string(from: creationDate)
        } catch {
            return nil
        }
    }

    /// Collect the AdServices attribution token.
    /// Returns `nil` for organic installs or if AdServices is unavailable.
    private func getAdServicesToken() -> String? {
        do {
            let token = try AAAttribution.attributionToken()
            return token
        } catch {
            // Error code 1 = no attribution (organic install), not a real error
            let nsError = error as NSError
            if nsError.code != 1 {
                logger.log("AdServices error: \(error.localizedDescription)")
            }
            return nil
        }
    }
}
