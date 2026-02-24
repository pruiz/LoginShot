@testable import LoginShot
import Foundation

/// Mock implementation of CaptureServiceProtocol for testing capture orchestration.
final class MockCaptureService: CaptureServiceProtocol, @unchecked Sendable {

    /// The result to return from captureJPEG. Defaults to minimal valid data.
    var captureResult: Result<CaptureResult, Error> = .success(
        CaptureResult(jpegData: Data([0xFF, 0xD8, 0xFF, 0xE0]), cameraInfo: .unknown)
    )

    /// Number of times captureJPEG was called.
    var captureCallCount = 0

    /// Last maxWidth parameter received.
    var lastMaxWidth: Int?

    /// Last quality parameter received.
    var lastQuality: Double?

    /// Optional delay to simulate capture time.
    var captureDelay: Duration?

    /// Last camera unique ID parameter received.
    var lastCameraUniqueID: String?

    func captureJPEG(maxWidth: Int, quality: Double, cameraUniqueID: String?) async throws -> CaptureResult {
        captureCallCount += 1
        lastMaxWidth = maxWidth
        lastQuality = quality
        lastCameraUniqueID = cameraUniqueID

        if let delay = captureDelay {
            try await Task.sleep(for: delay)
        }

        return try captureResult.get()
    }

    func listCameras() -> [CameraDeviceDescriptor] {
        [
            CameraDeviceDescriptor(uniqueID: "camera-1", deviceName: "FaceTime HD Camera", position: "front"),
            CameraDeviceDescriptor(uniqueID: "camera-2", deviceName: "External USB Camera", position: "unspecified")
        ]
    }

    // MARK: - Test Helpers

    /// Configure to return a successful capture with custom data.
    func succeedWith(jpegData: Data, cameraInfo: CameraInfo = .unknown) {
        captureResult = .success(CaptureResult(jpegData: jpegData, cameraInfo: cameraInfo))
    }

    /// Configure to throw an error on capture.
    func failWith(_ error: Error) {
        captureResult = .failure(error)
    }

    /// Reset all recorded state.
    func reset() {
        captureCallCount = 0
        lastMaxWidth = nil
        lastQuality = nil
        lastCameraUniqueID = nil
        captureResult = .success(
            CaptureResult(jpegData: Data([0xFF, 0xD8, 0xFF, 0xE0]), cameraInfo: .unknown)
        )
    }
}
