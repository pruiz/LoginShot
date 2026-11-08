import XCTest
@testable import LoginShot

final class CaptureMetadataTests: XCTestCase {

    func testBuildPopulatesAllFields() {
        let cameraInfo = CameraInfo(deviceName: "FaceTime HD Camera", position: "front", uniqueID: "camera-1")
        let metadata = CaptureMetadata.build(
            event: .sessionOpen,
            outputPath: "/tmp/test-session-open.jpg",
            cameraInfo: cameraInfo,
            success: true
        )

        XCTAssertEqual(metadata.event, "session-open")
        XCTAssertEqual(metadata.outputPath, "/tmp/test-session-open.jpg")
        XCTAssertEqual(metadata.camera.deviceName, "FaceTime HD Camera")
        XCTAssertEqual(metadata.camera.position, "front")
        XCTAssertEqual(metadata.status, "success")
        XCTAssertFalse(metadata.hostname.isEmpty, "hostname should not be empty")
        XCTAssertFalse(metadata.username.isEmpty, "username should not be empty")
        XCTAssertFalse(metadata.timestamp.isEmpty, "timestamp should not be empty")
    }

    func testBuildUsesCorrectEventRawValue() {
        let camera = CameraInfo.unknown

        let sessionOpen = CaptureMetadata.build(event: .sessionOpen, outputPath: "/a.jpg", cameraInfo: camera, success: true)
        XCTAssertEqual(sessionOpen.event, "session-open")

        let unlock = CaptureMetadata.build(event: .unlock, outputPath: "/b.jpg", cameraInfo: camera, success: true)
        XCTAssertEqual(unlock.event, "unlock")

        let lock = CaptureMetadata.build(event: .lock, outputPath: "/l.jpg", cameraInfo: camera, success: true)
        XCTAssertEqual(lock.event, "lock")

        let manual = CaptureMetadata.build(event: .manual, outputPath: "/c.jpg", cameraInfo: camera, success: true)
        XCTAssertEqual(manual.event, "manual")
    }

    func testTimestampIsISO8601() {
        let metadata = CaptureMetadata.build(
            event: .unlock,
            outputPath: "/tmp/test.jpg",
            cameraInfo: .unknown,
            success: true
        )

        // ISO 8601 with fractional seconds should contain "T" and "Z" or timezone offset
        XCTAssertTrue(metadata.timestamp.contains("T"),
                      "Timestamp should be ISO 8601 format: \(metadata.timestamp)")
    }

    func testAppInfoHasBundleId() {
        let metadata = CaptureMetadata.build(
            event: .unlock,
            outputPath: "/tmp/test.jpg",
            cameraInfo: .unknown,
            success: true
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
            cameraInfo: CameraInfo(deviceName: "FaceTime HD Camera", position: "front", uniqueID: "camera-1"),
            success: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        let json = String(data: data, encoding: .utf8)

        XCTAssertNotNil(json)
        XCTAssertTrue(json!.contains("\"event\" : \"session-open\""))
        XCTAssertTrue(json!.contains("\"status\" : \"success\""))
        XCTAssertTrue(json!.contains("\"deviceName\" : \"FaceTime HD Camera\""))
        XCTAssertTrue(json!.contains("\"outputPath\""))
    }

    func testFailureMetadataIncludesFailureInfo() {
        let metadata = CaptureMetadata.build(
            event: .unlock,
            outputPath: "/tmp/failure.jpg",
            cameraInfo: .unknown,
            success: false,
            failure: CaptureMetadata.FailureInfo(reason: "camera_capture_failed", message: "denied")
        )

        XCTAssertEqual(metadata.status, "failure")
        XCTAssertEqual(metadata.failure?.reason, "camera_capture_failed")
        XCTAssertEqual(metadata.failure?.message, "denied")
    }

    // MARK: - Capture quality diagnostics

    func testDiagnosticsEncodeCaptureQualityFieldsWhenProvided() throws {
        let metadata = CaptureMetadata.build(
            event: .unlock,
            outputPath: "/tmp/dark.jpg",
            cameraInfo: .unknown,
            success: true,
            diagnostics: CaptureMetadata.Diagnostics(
                backend: "avfoundation",
                durationMs: 2500,
                attemptCount: 2,
                failureCode: nil,
                meanLuminance: 0.012,
                darkFrameDetected: true,
                exposureWarmUpMs: 2000
            )
        )

        let data = try JSONEncoder().encode(metadata)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"attemptCount\":2"))
        XCTAssertTrue(json.contains("\"meanLuminance\":0.012"))
        XCTAssertTrue(json.contains("\"darkFrameDetected\":true"))
        XCTAssertTrue(json.contains("\"exposureWarmUpMs\":2000"))
    }

    func testDiagnosticsOmitCaptureQualityFieldsWhenUnknown() throws {
        let metadata = CaptureMetadata.build(
            event: .unlock,
            outputPath: "/tmp/plain.jpg",
            cameraInfo: .unknown,
            success: true,
            diagnostics: CaptureMetadata.Diagnostics(
                backend: "avfoundation",
                durationMs: 600,
                attemptCount: 1,
                failureCode: nil
            )
        )

        let data = try JSONEncoder().encode(metadata)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.contains("meanLuminance"))
        XCTAssertFalse(json.contains("darkFrameDetected"))
        XCTAssertFalse(json.contains("exposureWarmUpMs"))
    }

    func testDecodesSidecarWithoutCaptureQualityFields() throws {
        let json = """
        {
          "timestamp": "2026-08-30T10:00:00.000Z",
          "event": "unlock",
          "hostname": "host",
          "username": "user",
          "outputPath": "/tmp/legacy.jpg",
          "status": "success",
          "diagnostics": {
            "backend": "avfoundation",
            "durationMs": 500,
            "attemptCount": 1
          },
          "app": { "bundleId": "dev.pruiz.LoginShot", "version": "1.0", "build": "1" },
          "camera": { "deviceName": "Camera", "position": "front", "uniqueID": null }
        }
        """

        let metadata = try JSONDecoder().decode(CaptureMetadata.self, from: Data(json.utf8))

        XCTAssertEqual(metadata.diagnostics?.attemptCount, 1)
        XCTAssertNil(metadata.diagnostics?.meanLuminance)
        XCTAssertNil(metadata.diagnostics?.darkFrameDetected)
        XCTAssertNil(metadata.diagnostics?.exposureWarmUpMs)
    }
}
