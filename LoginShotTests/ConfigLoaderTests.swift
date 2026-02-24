import XCTest
@testable import LoginShot

final class ConfigLoaderTests: XCTestCase {

    // MARK: - Full YAML parsing

    func testParsesCompleteYaml() throws {
        let yaml = """
        output:
          directory: "~/Desktop/MyCaptures"
          format: "jpg"
          maxWidth: 1920
          jpegQuality: 0.9
        triggers:
          onSessionOpen: false
          onUnlock: true
          onLock: true
        metadata:
          writeSidecar: false
        ui:
          menuBarIcon: false
        capture:
          silent: false
          debounceSeconds: 5
        logging:
          enableFileLogging: true
          directory: "~/Library/Logs/LoginShot"
          retentionDays: 7
          cleanupIntervalHours: 12
          level: "Debug"
        """

        let config = try ConfigLoader.parse(yaml: yaml)

        XCTAssertTrue(config.output.directory.hasSuffix("Desktop/MyCaptures"))
        XCTAssertFalse(config.output.directory.contains("~"))
        XCTAssertEqual(config.output.format, "jpg")
        XCTAssertEqual(config.output.maxWidth, 1920)
        XCTAssertEqual(config.output.jpegQuality, 0.9, accuracy: 0.001)
        XCTAssertFalse(config.triggers.onSessionOpen)
        XCTAssertTrue(config.triggers.onUnlock)
        XCTAssertTrue(config.triggers.onLock)
        XCTAssertFalse(config.metadata.writeSidecar)
        XCTAssertFalse(config.ui.menuBarIcon)
        XCTAssertFalse(config.capture.silent)
        XCTAssertEqual(config.capture.debounceSeconds, 5)
        XCTAssertTrue(config.logging.enableFileLogging)
        XCTAssertEqual(config.logging.retentionDays, 7)
        XCTAssertEqual(config.logging.cleanupIntervalHours, 12)
        XCTAssertEqual(config.logging.level, "Debug")
    }

    // MARK: - Partial YAML (missing keys use defaults)

    func testParsesPartialYaml() throws {
        let yaml = """
        output:
          maxWidth: 640
        """

        let config = try ConfigLoader.parse(yaml: yaml)

        // Specified value
        XCTAssertEqual(config.output.maxWidth, 640)

        // Missing values should use defaults
        XCTAssertEqual(config.output.format, "jpg")
        XCTAssertEqual(config.output.jpegQuality, 0.85, accuracy: 0.001)
        XCTAssertTrue(config.triggers.onSessionOpen)
        XCTAssertTrue(config.triggers.onUnlock)
        XCTAssertTrue(config.triggers.onLock)
        XCTAssertTrue(config.metadata.writeSidecar)
        XCTAssertTrue(config.ui.menuBarIcon)
        XCTAssertTrue(config.capture.silent)
        XCTAssertEqual(config.capture.debounceSeconds, 3)
        XCTAssertFalse(config.logging.enableFileLogging)
    }

    // MARK: - Empty YAML

    func testParsesEmptyYaml() throws {
        let config = try ConfigLoader.parse(yaml: "")
        // Empty YAML returns defaults (not a dictionary)
        XCTAssertEqual(config.output.format, "jpg")
        XCTAssertEqual(config.output.maxWidth, 1280)
    }

    // MARK: - Tilde expansion in directory

    func testExpandsTildeInDirectory() throws {
        let yaml = """
        output:
          directory: "~/Library/CloudStorage/Dropbox/LoginShot"
        """

        let config = try ConfigLoader.parse(yaml: yaml)

        XCTAssertFalse(config.output.directory.contains("~"))
        XCTAssertTrue(config.output.directory.hasPrefix("/"))
        XCTAssertTrue(config.output.directory.hasSuffix("Library/CloudStorage/Dropbox/LoginShot"))
    }

    // MARK: - Only specified sections

    func testParsesOnlyTriggersSection() throws {
        let yaml = """
        triggers:
          onSessionOpen: false
          onUnlock: false
          onLock: true
        """

        let config = try ConfigLoader.parse(yaml: yaml)

        XCTAssertFalse(config.triggers.onSessionOpen)
        XCTAssertFalse(config.triggers.onUnlock)
        XCTAssertTrue(config.triggers.onLock)
        // Other sections should be defaults
        XCTAssertEqual(config.output.maxWidth, 1280)
        XCTAssertTrue(config.ui.menuBarIcon)
    }

    // MARK: - Int/Double Coercion (YAML type handling)

    func testParsesJpegQualityAsInteger() throws {
        // YAML `1` is parsed as Int, not Double. Should coerce to 1.0.
        let yaml = """
        output:
          jpegQuality: 1
        """

        let config = try ConfigLoader.parse(yaml: yaml)

        XCTAssertEqual(config.output.jpegQuality, 1.0, accuracy: 0.001)
    }

    func testParsesJpegQualityAsZeroInteger() throws {
        // YAML `0` should coerce to 0.0
        let yaml = """
        output:
          jpegQuality: 0
        """

        let config = try ConfigLoader.parse(yaml: yaml)

        XCTAssertEqual(config.output.jpegQuality, 0.0, accuracy: 0.001)
    }

    func testParsesMaxWidthAsFloat() throws {
        // YAML `1280.0` is parsed as Double, not Int. Should coerce to 1280.
        let yaml = """
        output:
          maxWidth: 1280.0
        """

        let config = try ConfigLoader.parse(yaml: yaml)

        XCTAssertEqual(config.output.maxWidth, 1280)
    }

    func testParsesDebounceSecondsAsFloat() throws {
        // YAML `5.0` is parsed as Double. Should coerce to 5.
        let yaml = """
        capture:
          debounceSeconds: 5.0
        """

        let config = try ConfigLoader.parse(yaml: yaml)

        XCTAssertEqual(config.capture.debounceSeconds, 5)
    }

    func testParsesDebounceSecondsWithFractionalTruncates() throws {
        // YAML `3.7` should truncate to 3 (Int conversion)
        let yaml = """
        capture:
          debounceSeconds: 3.7
        """

        let config = try ConfigLoader.parse(yaml: yaml)

        XCTAssertEqual(config.capture.debounceSeconds, 3)
    }
}
