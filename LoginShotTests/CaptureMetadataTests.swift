import XCTest
@testable import LoginShot

final class CaptureMetadataTests: XCTestCase {

    func testBuildPopulatesAllFields() {
        let cameraInfo = CameraInfo(deviceName: "FaceTime HD Camera", position: "front")
        let metadata = CaptureMetadata.build(
            event: .sessionOpen,
            outputPath: "/tmp/test-session-open.jpg",
            cameraInfo: cameraInfo
        )

        XCTAssertEqual(metadata.event, "session-open")
        XCTAssertEqual(metadata.outputPath, "/tmp/test-session-open.jpg")
        XCTAssertEqual(metadata.camera.deviceName, "FaceTime HD Camera")
        XCTAssertEqual(metadata.camera.position, "front")
        XCTAssertFalse(metadata.hostname.isEmpty, "hostname should not be empty")
        XCTAssertFalse(metadata.username.isEmpty, "username should not be empty")
        XCTAssertFalse(metadata.timestamp.isEmpty, "timestamp should not be empty")
    }

    func testBuildUsesCorrectEventRawValue() {
        let camera = CameraInfo.unknown

        let sessionOpen = CaptureMetadata.build(event: .sessionOpen, outputPath: "/a.jpg", cameraInfo: camera)
        XCTAssertEqual(sessionOpen.event, "session-open")

        let unlock = CaptureMetadata.build(event: .unlock, outputPath: "/b.jpg", cameraInfo: camera)
        XCTAssertEqual(unlock.event, "unlock")

        let manual = CaptureMetadata.build(event: .manual, outputPath: "/c.jpg", cameraInfo: camera)
        XCTAssertEqual(manual.event, "manual")
    }

    func testTimestampIsISO8601() {
        let metadata = CaptureMetadata.build(
            event: .unlock,
            outputPath: "/tmp/test.jpg",
            cameraInfo: .unknown
        )

        // ISO 8601 with fractional seconds should contain "T" and "Z" or timezone offset
        XCTAssertTrue(metadata.timestamp.contains("T"),
                      "Timestamp should be ISO 8601 format: \(metadata.timestamp)")
    }

    func testAppInfoHasBundleId() {
        let metadata = CaptureMetadata.build(
            event: .unlock,
            outputPath: "/tmp/test.jpg",
            cameraInfo: .unknown
        )

        // In test runner, bundle ID may not be our app's, but the field should exist
        XCTAssertFalse(metadata.app.bundleId.isEmpty)
        XCTAssertFalse(metadata.app.version.isEmpty)
        XCTAssertFalse(metadata.app.build.isEmpty)
    }

    func testMetadataIsEncodableToJSON() throws {
        let metadata = CaptureMetadata.build(
            event: .sessionOpen,
            outputPath: "/tmp/2026-02-22T08-41-10-session-open.jpg",
            cameraInfo: CameraInfo(deviceName: "FaceTime HD Camera", position: "front")
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        let json = String(data: data, encoding: .utf8)

        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("\"event\" : \"session-open\""))
        XCTAssertTrue(json!.contains("\"deviceName\" : \"FaceTime HD Camera\""))
        XCTAssertTrue(json!.contains("\"outputPath\""))
    }
}
