import XCTest
@testable import LoginShot

final class StorageWriterTests: XCTestCase {

    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "LoginShotTests-\(UUID().uuidString)"
    }

    override func tearDown() {
        super.tearDown()
        if let dir = tempDir {
            try? FileManager.default.removeItem(atPath: dir)
        }
    }

    // MARK: - Directory creation

    func testCreatesOutputDirectoryIfMissing() async throws {
        var config = AppConfig.default
        config.output.directory = tempDir

        let writer = StorageWriter()
        let metadata = CaptureMetadata.build(
            event: .sessionOpen,
            outputPath: (tempDir as NSString).appendingPathComponent("test-session-open.jpg"),
            cameraInfo: .unknown,
            success: true
        )

        try await writer.writeCapture(
            event: .sessionOpen,
            jpegData: Data([0xFF, 0xD8, 0xFF, 0xE0]), // minimal JPEG header
            metadata: metadata,
            config: config
        )

        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    // MARK: - File writing

    func testWritesJPEGFile() async throws {
        var config = AppConfig.default
        config.output.directory = tempDir

        let jpegPath = (tempDir as NSString).appendingPathComponent("test.jpg")
        let writer = StorageWriter()
        let metadata = CaptureMetadata.build(
            event: .unlock,
            outputPath: jpegPath,
            cameraInfo: .unknown,
            success: true
        )

        let testData = Data(repeating: 0xAB, count: 1024)
        try await writer.writeCapture(
            event: .unlock,
            jpegData: testData,
            metadata: metadata,
            config: config
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: jpegPath))
        let written = try Data(contentsOf: URL(fileURLWithPath: jpegPath))
        XCTAssertEqual(written, testData)
    }

    func testWritesJSONSidecar() async throws {
        var config = AppConfig.default
        config.output.directory = tempDir
        config.metadata.writeSidecar = true

        let jpegPath = (tempDir as NSString).appendingPathComponent("test-unlock.jpg")
        let jsonPath = (tempDir as NSString).appendingPathComponent("test-unlock.json")
        let writer = StorageWriter()
        let metadata = CaptureMetadata.build(
            event: .unlock,
            outputPath: jpegPath,
            cameraInfo: CameraInfo(deviceName: "Test Camera", position: "front", uniqueID: "test-camera"),
            success: true
        )

        try await writer.writeCapture(
            event: .unlock,
            jpegData: Data([0xFF]),
            metadata: metadata,
            config: config
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonPath),
                      "JSON sidecar should be written when writeSidecar=true")

        let jsonData = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
        let decoded = try JSONDecoder().decode(CaptureMetadata.self, from: jsonData)
        XCTAssertEqual(decoded.event, "unlock")
        XCTAssertEqual(decoded.camera.deviceName, "Test Camera")
    }

    func testSkipsJSONSidecarWhenDisabled() async throws {
        var config = AppConfig.default
        config.output.directory = tempDir
        config.metadata.writeSidecar = false

        let jpegPath = (tempDir as NSString).appendingPathComponent("test-manual.jpg")
        let jsonPath = (tempDir as NSString).appendingPathComponent("test-manual.json")
        let writer = StorageWriter()
        let metadata = CaptureMetadata.build(
            event: .manual,
            outputPath: jpegPath,
            cameraInfo: .unknown,
            success: true
        )

        try await writer.writeCapture(
            event: .manual,
            jpegData: Data([0xFF]),
            metadata: metadata,
            config: config
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: jpegPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: jsonPath),
                       "JSON sidecar should NOT be written when writeSidecar=false")
    }

    func testWritesFailureSidecarEvenWhenDisabled() async throws {
        var config = AppConfig.default
        config.output.directory = tempDir
        config.metadata.writeSidecar = false

        let jpegPath = (tempDir as NSString).appendingPathComponent("test-failure.jpg")
        let jsonPath = (tempDir as NSString).appendingPathComponent("test-failure.json")
        let writer = StorageWriter()
        let metadata = CaptureMetadata.build(
            event: .unlock,
            outputPath: jpegPath,
            cameraInfo: .unknown,
            success: false,
            failure: CaptureMetadata.FailureInfo(reason: "camera_capture_failed", message: "camera unavailable")
        )

        try await writer.writeCapture(
            event: .unlock,
            jpegData: nil,
            metadata: metadata,
            config: config
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: jpegPath),
                       "No image should be written for a failure-only persistence")
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonPath),
                      "Failure sidecar should always be written")

        let jsonData = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
        let decoded = try JSONDecoder().decode(CaptureMetadata.self, from: jsonData)
        XCTAssertEqual(decoded.status, "failure")
        XCTAssertEqual(decoded.failure?.reason, "camera_capture_failed")
    }
}
