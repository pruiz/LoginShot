import Foundation

/// Result of a successful one-shot capture.
struct CaptureResult: Sendable {
    let jpegData: Data
    let cameraInfo: CameraInfo
}

/// Errors from the capture pipeline.
enum CaptureError: Error, Sendable {
    case notImplemented
    case cameraUnavailable(String)
    case captureFailed(String)
}

/// Protocol for one-shot webcam capture (test seam).
protocol CaptureServiceProtocol: Sendable {
    func captureJPEG(maxWidth: Int, quality: Double) async throws -> CaptureResult
}

/// Stub implementation — returns an error until AVFoundation capture is wired.
final class CaptureService: CaptureServiceProtocol, Sendable {
    func captureJPEG(maxWidth: Int, quality: Double) async throws -> CaptureResult {
        // TODO: Implement AVFoundation one-shot capture
        Log.capture.warning("CaptureService.captureJPEG() is a stub — not yet implemented")
        throw CaptureError.notImplemented
    }
}
