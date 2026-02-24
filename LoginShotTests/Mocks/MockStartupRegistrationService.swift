@testable import LoginShot

final class MockStartupRegistrationService: StartupRegistrationManaging, @unchecked Sendable {
    var enabled = false
    var setEnabledCallCount = 0
    var lastSetEnabledValue: Bool?
    var setEnabledError: Error?

    func isEnabled() -> Bool {
        enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        setEnabledCallCount += 1
        lastSetEnabledValue = enabled
        if let setEnabledError {
            throw setEnabledError
        }
        self.enabled = enabled
    }
}
