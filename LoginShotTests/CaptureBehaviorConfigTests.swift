import XCTest
@testable import LoginShot

final class CaptureBehaviorConfigTests: XCTestCase {
    func testCaptureDefaultsEnableExposureWarmUpAndCenterMetering() {
        let config = AppConfig.default

        XCTAssertTrue(config.capture.exposureWarmUpEnabled)
        XCTAssertEqual(config.capture.exposureWarmUpMilliseconds, 2000)
        XCTAssertTrue(config.capture.centerMeteringEnabled)
    }

    func testValidationClampsNegativeExposureWarmUpMilliseconds() {
        var config = AppConfig.default
        config.capture.exposureWarmUpMilliseconds = -250

        let validated = config.validated()

        XCTAssertEqual(validated.capture.exposureWarmUpMilliseconds, 0)
    }

    func testValidationKeepsPositiveExposureWarmUpMilliseconds() {
        var config = AppConfig.default
        config.capture.exposureWarmUpMilliseconds = 1500

        let validated = config.validated()

        XCTAssertEqual(validated.capture.exposureWarmUpMilliseconds, 1500)
    }

    func testParseCaptureWarmUpAndCenterMeteringSettings() throws {
        let yaml = """
        capture:
          exposureWarmUpEnabled: false
          exposureWarmUpMilliseconds: 750
          centerMeteringEnabled: false
        """

        let config = try ConfigLoader.parse(yaml: yaml)

        XCTAssertFalse(config.capture.exposureWarmUpEnabled)
        XCTAssertEqual(config.capture.exposureWarmUpMilliseconds, 750)
        XCTAssertFalse(config.capture.centerMeteringEnabled)
    }

    func testWriteConfigPersistsWarmUpAndCenterMeteringSettings() throws {
        let tempDir = NSTemporaryDirectory().appending("LoginShotCaptureBehaviorTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let path = (tempDir as NSString).appendingPathComponent("config.yml")
        var config = AppConfig.default
        config.capture.exposureWarmUpEnabled = false
        config.capture.exposureWarmUpMilliseconds = 900
        config.capture.centerMeteringEnabled = false

        _ = try ConfigWriter.writeConfig(config, to: path)

        let content = try String(contentsOfFile: path, encoding: .utf8)
        let parsed = try ConfigLoader.parse(yaml: content)
        XCTAssertFalse(parsed.capture.exposureWarmUpEnabled)
        XCTAssertEqual(parsed.capture.exposureWarmUpMilliseconds, 900)
        XCTAssertFalse(parsed.capture.centerMeteringEnabled)
    }
}
