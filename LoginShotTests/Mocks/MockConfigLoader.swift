@testable import LoginShot
import Foundation

/// Mock implementation of ConfigLoaderProtocol for testing config-dependent behavior.
final class MockConfigLoader: ConfigLoaderProtocol, @unchecked Sendable {

    /// The config to return from load(). Defaults to AppConfig.default.
    var configToReturn: AppConfig = .default

    /// Number of times load() was called.
    var loadCallCount = 0

    func load() -> AppConfig {
        loadCallCount += 1
        return configToReturn
    }

    // MARK: - Test Helpers

    /// Reset all recorded state.
    func reset() {
        loadCallCount = 0
        configToReturn = .default
    }
}
