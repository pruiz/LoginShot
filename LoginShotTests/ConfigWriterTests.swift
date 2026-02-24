import XCTest
@testable import LoginShot

final class ConfigWriterTests: XCTestCase {

    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory()
            .appending("LoginShotConfigWriterTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir) {
            try? FileManager.default.removeItem(atPath: tempDir)
        }
        super.tearDown()
    }

    // MARK: - writeSampleConfig

    func testWritesSampleConfigToSpecifiedPath() throws {
        let path = (tempDir as NSString).appendingPathComponent("config.yml")
        let result = try ConfigWriter.writeSampleConfig(to: path)

        XCTAssertEqual(result, path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testCreatesParentDirectoryIfMissing() throws {
        let path = (tempDir as NSString)
            .appendingPathComponent("nested/dir/config.yml")

        _ = try ConfigWriter.writeSampleConfig(to: path)

        let parentDir = (path as NSString).deletingLastPathComponent
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: parentDir, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testDoesNotOverwriteExistingFile() throws {
        let path = (tempDir as NSString).appendingPathComponent("config.yml")

        // Write once (should succeed)
        _ = try ConfigWriter.writeSampleConfig(to: path)

        // Write again (should throw fileAlreadyExists)
        do {
            _ = try ConfigWriter.writeSampleConfig(to: path)
            XCTFail("Expected ConfigWriterError.fileAlreadyExists")
        } catch ConfigWriterError.fileAlreadyExists(let existingPath) {
            XCTAssertEqual(existingPath, path)
        }
    }

    func testWrittenContentMatchesSampleYAML() throws {
        let path = (tempDir as NSString).appendingPathComponent("config.yml")
        _ = try ConfigWriter.writeSampleConfig(to: path)

        let content = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertEqual(content, ConfigWriter.sampleYAML())
    }

    // MARK: - sampleYAML

    func testWriteConfigPersistsCameraUniqueID() throws {
        let path = (tempDir as NSString).appendingPathComponent("config.yml")
        var config = AppConfig.default
        config.capture.cameraUniqueID = "camera-xyz"

        _ = try ConfigWriter.writeConfig(config, to: path)

        let content = try String(contentsOfFile: path, encoding: .utf8)
        let parsed = try ConfigLoader.parse(yaml: content)
        XCTAssertEqual(parsed.capture.cameraUniqueID, "camera-xyz")
    }

    func testSampleYAMLContainsAllSections() {
        let yaml = ConfigWriter.sampleYAML()

        XCTAssertTrue(yaml.contains("output:"), "Missing output section")
        XCTAssertTrue(yaml.contains("triggers:"), "Missing triggers section")
        XCTAssertTrue(yaml.contains("metadata:"), "Missing metadata section")
        XCTAssertTrue(yaml.contains("ui:"), "Missing ui section")
        XCTAssertTrue(yaml.contains("capture:"), "Missing capture section")
        XCTAssertTrue(yaml.contains("logging:"), "Missing logging section")
    }

    func testSampleYAMLContainsDefaultValues() {
        let yaml = ConfigWriter.sampleYAML()

        XCTAssertTrue(yaml.contains("~/Pictures/LoginShot"), "Missing default directory")
        XCTAssertTrue(yaml.contains("maxWidth: 1280"), "Missing default maxWidth")
        XCTAssertTrue(yaml.contains("jpegQuality: 0.85"), "Missing default jpegQuality")
        XCTAssertTrue(yaml.contains("debounceSeconds: 3"), "Missing default debounceSeconds")
        XCTAssertTrue(yaml.contains("cameraUniqueID: null"), "Missing default cameraUniqueID")
        XCTAssertTrue(yaml.contains("onLock: true"), "Missing default onLock")
        XCTAssertTrue(yaml.contains("enableFileLogging: false"), "Missing default file logging toggle")
    }

    func testSampleYAMLIsValidYAML() throws {
        // The sample YAML should be parseable by ConfigLoader
        let yaml = ConfigWriter.sampleYAML()
        let config = try ConfigLoader.parse(yaml: yaml)

        XCTAssertEqual(config.output.format, "jpg")
        XCTAssertEqual(config.output.maxWidth, 1280)
        XCTAssertEqual(config.output.jpegQuality, 0.85, accuracy: 0.001)
        XCTAssertTrue(config.triggers.onSessionOpen)
        XCTAssertTrue(config.triggers.onUnlock)
        XCTAssertTrue(config.triggers.onLock)
        XCTAssertTrue(config.metadata.writeSidecar)
        XCTAssertTrue(config.ui.menuBarIcon)
        XCTAssertTrue(config.capture.silent)
        XCTAssertEqual(config.capture.debounceSeconds, 3)
        XCTAssertNil(config.capture.cameraUniqueID)
        XCTAssertFalse(config.logging.enableFileLogging)
    }
}
