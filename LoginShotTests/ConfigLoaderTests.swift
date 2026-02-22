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
        metadata:
          writeSidecar: false
        ui:
          menuBarIcon: false
        capture:
          silent: false
          debounceSeconds: 5
        """

        let config = try ConfigLoader.parse(yaml: yaml)

        XCTAssertTrue(config.output.directory.hasSuffix("Desktop/MyCaptures"))
        XCTAssertFalse(config.output.directory.contains("~"))
        XCTAssertEqual(config.output.format, "jpg")
        XCTAssertEqual(config.output.maxWidth, 1920)
        XCTAssertEqual(config.output.jpegQuality, 0.9, accuracy: 0.001)
        XCTAssertFalse(config.triggers.onSessionOpen)
        XCTAssertTrue(config.triggers.onUnlock)
        XCTAssertFalse(config.metadata.writeSidecar)
        XCTAssertFalse(config.ui.menuBarIcon)
        XCTAssertFalse(config.capture.silent)
        XCTAssertEqual(config.capture.debounceSeconds, 5)
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
        XCTAssertTrue(config.metadata.writeSidecar)
        XCTAssertTrue(config.ui.menuBarIcon)
        XCTAssertTrue(config.capture.silent)
        XCTAssertEqual(config.capture.debounceSeconds, 3)
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
        """

        let config = try ConfigLoader.parse(yaml: yaml)

        XCTAssertFalse(config.triggers.onSessionOpen)
        XCTAssertFalse(config.triggers.onUnlock)
        // Other sections should be defaults
        XCTAssertEqual(config.output.maxWidth, 1280)
        XCTAssertTrue(config.ui.menuBarIcon)
    }
}
