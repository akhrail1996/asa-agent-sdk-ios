import Foundation

/// Simple console logger for the SDK.
final class Logger {
    private let enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        NSLog("[ASAAgent] %@", message())
    }
}
