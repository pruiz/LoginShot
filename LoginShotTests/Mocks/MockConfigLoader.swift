@testable import LoginShot
import Foundation

/// Mock implementation of ConfigLoaderProtocol for testing config-dependent behavior.
final class MockConfigLoader: ConfigLoaderProtocol, @unchecked Sendable {

    /// The config to return from load(). Defaults to AppConfig.default.
    var configToReturn: AppConfig = .default

    /// Number of times load() was called.
    var loadCallCount = 0

    /// Optional explicit result to return from loadResult().
    var resultToReturn: ConfigLoadResult?

    func load() -> AppConfig {
        loadCallCount += 1
        return configToReturn
    }

    func loadResult() -> ConfigLoadResult {
        loadCallCount += 1
        if let resultToReturn {
            return resultToReturn
        }
        return .loaded(config: configToReturn, sourcePath: "/tmp/config.yml")
    }

    // MARK: - Test Helpers

    /// Reset all recorded state.
    func reset() {
        loadCallCount = 0
        configToReturn = .default
        resultToReturn = nil
    }
}
