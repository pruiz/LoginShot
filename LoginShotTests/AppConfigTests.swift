import XCTest
@testable import LoginShot

final class AppConfigTests: XCTestCase {

    // MARK: - Defaults

    func testDefaultValues() {
        let config = AppConfig.default

        XCTAssertTrue(config.output.directory.hasSuffix("Pictures/LoginShot"))
        XCTAssertEqual(config.output.format, "jpg")
        XCTAssertEqual(config.output.maxWidth, 1280)
        XCTAssertEqual(config.output.jpegQuality, 0.85)
        XCTAssertTrue(config.triggers.onSessionOpen)
        XCTAssertTrue(config.triggers.onUnlock)
        XCTAssertTrue(config.triggers.onLock)
        XCTAssertTrue(config.metadata.writeSidecar)
        XCTAssertTrue(config.ui.menuBarIcon)
        XCTAssertTrue(config.capture.silent)
        XCTAssertEqual(config.capture.debounceSeconds, 3)
        XCTAssertNil(config.capture.cameraUniqueID)
        XCTAssertEqual(config.capture.exposureWarmUpMilliseconds, 2000)
        XCTAssertTrue(config.capture.centerMeteringEnabled)
        XCTAssertTrue(config.capture.darkFrameRetryEnabled)
        XCTAssertEqual(config.capture.darkFrameThreshold, 0.03, accuracy: 0.0001)
        XCTAssertTrue(config.watermark.enabled)
        XCTAssertEqual(config.watermark.format, AppConfig.WatermarkConfig.defaultFormat)
    }

    func testDefaultDirectoryExpandsTilde() {
        let config = AppConfig.default
        XCTAssertFalse(config.output.directory.contains("~"),
                       "Default directory should have ~ expanded")
        XCTAssertTrue(config.output.directory.hasPrefix("/"),
                      "Default directory should be an absolute path")
    }

    // MARK: - Validation: format

    func testValidationRejectsNonJpgFormat() {
        var config = AppConfig.default
        config.output.format = "heic"
        let validated = config.validated()
        XCTAssertEqual(validated.output.format, "jpg",
                       "Non-jpg format should fall back to jpg in v1")
    }

    func testValidationKeepsJpgFormat() {
        var config = AppConfig.default
        config.output.format = "jpg"
        let validated = config.validated()
        XCTAssertEqual(validated.output.format, "jpg")
    }

    // MARK: - Validation: jpegQuality

    func testValidationClampsQualityAboveOne() {
        var config = AppConfig.default
        config.output.jpegQuality = 1.5
        let validated = config.validated()
        XCTAssertEqual(validated.output.jpegQuality, 1.0, accuracy: 0.001)
    }

    func testValidationClampsQualityBelowZero() {
        var config = AppConfig.default
        config.output.jpegQuality = -0.3
        let validated = config.validated()
        XCTAssertEqual(validated.output.jpegQuality, 0.0, accuracy: 0.001)
    }

    func testValidationKeepsValidQuality() {
        var config = AppConfig.default
        config.output.jpegQuality = 0.5
        let validated = config.validated()
        XCTAssertEqual(validated.output.jpegQuality, 0.5, accuracy: 0.001)
    }

    // MARK: - Validation: maxWidth

    func testValidationFixesNegativeMaxWidth() {
        var config = AppConfig.default
        config.output.maxWidth = -100
        let validated = config.validated()
        XCTAssertEqual(validated.output.maxWidth, 0)
    }

    func testValidationKeepsZeroMaxWidth() {
        var config = AppConfig.default
        config.output.maxWidth = 0
        let validated = config.validated()
        XCTAssertEqual(validated.output.maxWidth, 0)
    }

    func testValidationKeepsPositiveMaxWidth() {
        var config = AppConfig.default
        config.output.maxWidth = 1920
        let validated = config.validated()
        XCTAssertEqual(validated.output.maxWidth, 1920)
    }

    // MARK: - Validation: debounceSeconds

    func testValidationFixesNegativeDebounce() {
        var config = AppConfig.default
        config.capture.debounceSeconds = -5
        let validated = config.validated()
        XCTAssertEqual(validated.capture.debounceSeconds, 0)
    }

    func testValidationKeepsPositiveDebounce() {
        var config = AppConfig.default
        config.capture.debounceSeconds = 10
        let validated = config.validated()
        XCTAssertEqual(validated.capture.debounceSeconds, 10)
    }

    func testValidationClearsEmptyCameraUniqueID() {
        var config = AppConfig.default
        config.capture.cameraUniqueID = "   "

        let validated = config.validated()

        XCTAssertNil(validated.capture.cameraUniqueID)
    }

    func testValidationRestoresDefaultWatermarkFormatWhenEmpty() {
        var config = AppConfig.default
        config.watermark.format = "  "

        let validated = config.validated()

        XCTAssertEqual(validated.watermark.format, AppConfig.WatermarkConfig.defaultFormat)
    }

    // MARK: - Validation: exposure warm-up

    func testValidationFixesNegativeExposureWarmUp() {
        var config = AppConfig.default
        config.capture.exposureWarmUpMilliseconds = -250

        let validated = config.validated()

        XCTAssertEqual(validated.capture.exposureWarmUpMilliseconds, 0)
    }

    func testValidationKeepsZeroExposureWarmUp() {
        var config = AppConfig.default
        config.capture.exposureWarmUpMilliseconds = 0

        let validated = config.validated()

        XCTAssertEqual(validated.capture.exposureWarmUpMilliseconds, 0)
    }

    func testValidationKeepsPositiveExposureWarmUp() {
        var config = AppConfig.default
        config.capture.exposureWarmUpMilliseconds = 1500

        let validated = config.validated()

        XCTAssertEqual(validated.capture.exposureWarmUpMilliseconds, 1500)
    }

    func testValidationClampsExposureWarmUpAboveMaximum() {
        var config = AppConfig.default
        config.capture.exposureWarmUpMilliseconds = 20_000

        let validated = config.validated()

        XCTAssertEqual(
            validated.capture.exposureWarmUpMilliseconds,
            AppConfig.CaptureConfig.maxExposureWarmUpMilliseconds
        )
    }

    func testValidationKeepsExposureWarmUpAtMaximum() {
        var config = AppConfig.default
        config.capture.exposureWarmUpMilliseconds = AppConfig.CaptureConfig.maxExposureWarmUpMilliseconds

        let validated = config.validated()

        XCTAssertEqual(
            validated.capture.exposureWarmUpMilliseconds,
            AppConfig.CaptureConfig.maxExposureWarmUpMilliseconds
        )
    }

    // MARK: - Validation: non-finite numbers

    func testValidationReplacesNonFiniteJpegQuality() {
        for invalid in [Double.nan, Double.infinity, -Double.infinity] {
            var config = AppConfig.default
            config.output.jpegQuality = invalid

            let validated = config.validated()

            XCTAssertEqual(
                validated.output.jpegQuality,
                AppConfig.OutputConfig.default.jpegQuality,
                accuracy: 0.0001,
                "Quality \(invalid) should fall back to the default"
            )
        }
    }

    func testValidationReplacesNonFiniteDarkFrameThreshold() {
        for invalid in [Double.nan, Double.infinity, -Double.infinity] {
            var config = AppConfig.default
            config.capture.darkFrameThreshold = invalid

            let validated = config.validated()

            XCTAssertEqual(
                validated.capture.darkFrameThreshold,
                AppConfig.CaptureConfig.default.darkFrameThreshold,
                accuracy: 0.0001,
                "Threshold \(invalid) should fall back to the default"
            )
        }
    }

    // MARK: - Validation: dark frame threshold

    func testValidationClampsDarkFrameThresholdAboveOne() {
        var config = AppConfig.default
        config.capture.darkFrameThreshold = 1.7

        let validated = config.validated()

        XCTAssertEqual(validated.capture.darkFrameThreshold, 1.0, accuracy: 0.0001)
    }

    func testValidationClampsNegativeDarkFrameThreshold() {
        var config = AppConfig.default
        config.capture.darkFrameThreshold = -0.2

        let validated = config.validated()

        XCTAssertEqual(validated.capture.darkFrameThreshold, 0.0, accuracy: 0.0001)
    }

    func testValidationKeepsValidDarkFrameThreshold() {
        var config = AppConfig.default
        config.capture.darkFrameThreshold = 0.15

        let validated = config.validated()

        XCTAssertEqual(validated.capture.darkFrameThreshold, 0.15, accuracy: 0.0001)
    }
}
