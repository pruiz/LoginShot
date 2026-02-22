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
        XCTAssertTrue(config.metadata.writeSidecar)
        XCTAssertTrue(config.ui.menuBarIcon)
        XCTAssertTrue(config.capture.silent)
        XCTAssertEqual(config.capture.debounceSeconds, 3)
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
}
