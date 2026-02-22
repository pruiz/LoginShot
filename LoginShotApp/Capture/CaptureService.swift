import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

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

/// Real AVFoundation one-shot capture implementation.
/// Acquires camera, captures a single photo, resizes if needed, releases camera.
final class CaptureService: CaptureServiceProtocol, Sendable {
    func captureJPEG(maxWidth: Int, quality: Double) async throws -> CaptureResult {
        try await OneShotCapture.perform(maxWidth: maxWidth, quality: quality)
    }
}

// MARK: - One-Shot Capture Helper

/// Manages a single AVCaptureSession lifecycle: setup → capture → teardown.
/// Uses @unchecked Sendable because all AVFoundation state is accessed
/// sequentially (never concurrently) through the async run() method.
private final class OneShotCapture: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {

    private let maxWidth: Int
    private let quality: Double
    private var continuation: CheckedContinuation<CaptureResult, Error>?
    private var deviceName: String = "Unknown"
    private var devicePosition: String = "unknown"

    private init(maxWidth: Int, quality: Double) {
        self.maxWidth = maxWidth
        self.quality = quality
        super.init()
    }

    /// Entry point: check authorization, find camera, capture, return JPEG data.
    static func perform(maxWidth: Int, quality: Double) async throws -> CaptureResult {
        // 1. Check / request camera authorization
        try await ensureCameraAuthorization()

        // 2. Run capture
        let capture = OneShotCapture(maxWidth: maxWidth, quality: quality)
        return try await capture.run()
    }

    // MARK: - Authorization

    private static func ensureCameraAuthorization() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                throw CaptureError.cameraUnavailable("Camera access denied by user")
            }
        case .denied, .restricted:
            throw CaptureError.cameraUnavailable(
                "Camera access not granted. Enable in System Settings > Privacy & Security > Camera."
            )
        @unknown default:
            throw CaptureError.cameraUnavailable("Unknown camera authorization status")
        }
    }

    // MARK: - Capture

    private func run() async throws -> CaptureResult {
        // Find default video device
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CaptureError.cameraUnavailable("No video capture device found")
        }

        deviceName = device.localizedName
        devicePosition = Self.positionString(device.position)
        Log.capture.info("Using camera: \(device.localizedName) (\(self.devicePosition))")

        // Setup session
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CaptureError.captureFailed("Cannot create camera input: \(error.localizedDescription)")
        }
        guard session.canAddInput(input) else {
            throw CaptureError.captureFailed("Cannot add camera input to capture session")
        }
        session.addInput(input)

        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else {
            throw CaptureError.captureFailed("Cannot add photo output to capture session")
        }
        session.addOutput(output)

        // Start session and allow camera sensor to stabilize (exposure, white balance)
        session.startRunning()

        try await Task.sleep(for: .milliseconds(500))

        guard session.isRunning else {
            throw CaptureError.captureFailed("Capture session failed to start")
        }

        // Capture photo via delegate callback → continuation
        let result: CaptureResult = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let settings = AVCapturePhotoSettings()
            output.capturePhoto(with: settings, delegate: self)
        }

        // Tear down
        session.stopRunning()
        Log.capture.info("Capture complete (\(result.jpegData.count) bytes)")

        return result
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard let continuation = self.continuation else { return }
        self.continuation = nil

        if let error = error {
            continuation.resume(throwing: CaptureError.captureFailed(
                "Photo processing failed: \(error.localizedDescription)"
            ))
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            continuation.resume(throwing: CaptureError.captureFailed(
                "No image data in captured photo"
            ))
            return
        }

        // Resize and re-encode as JPEG
        do {
            let jpegData = try processImage(data: imageData)
            let cameraInfo = CameraInfo(deviceName: deviceName, position: devicePosition)
            continuation.resume(returning: CaptureResult(jpegData: jpegData, cameraInfo: cameraInfo))
        } catch {
            continuation.resume(throwing: error)
        }
    }

    // MARK: - Image Processing

    private func processImage(data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CaptureError.captureFailed("Failed to decode captured image data")
        }

        let originalWidth = cgImage.width
        let originalHeight = cgImage.height

        // Resize if image exceeds maxWidth (0 = no resize)
        let finalImage: CGImage
        if maxWidth > 0 && originalWidth > maxWidth {
            let scale = Double(maxWidth) / Double(originalWidth)
            let newWidth = maxWidth
            let newHeight = Int(Double(originalHeight) * scale)

            guard let colorSpace = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: nil,
                      width: newWidth,
                      height: newHeight,
                      bitsPerComponent: 8,
                      bytesPerRow: 0,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                throw CaptureError.captureFailed("Failed to create graphics context for resize")
            }

            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

            guard let resized = context.makeImage() else {
                throw CaptureError.captureFailed("Failed to produce resized image")
            }

            finalImage = resized
            Log.capture.info("Resized \(originalWidth)x\(originalHeight) → \(newWidth)x\(newHeight)")
        } else {
            finalImage = cgImage
        }

        // Encode as JPEG with configured quality
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw CaptureError.captureFailed("Failed to create JPEG encoder")
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, finalImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.captureFailed("Failed to finalize JPEG encoding")
        }

        return mutableData as Data
    }

    // MARK: - Helpers

    private static func positionString(_ position: AVCaptureDevice.Position) -> String {
        switch position {
        case .front: "front"
        case .back: "back"
        case .unspecified: "unspecified"
        @unknown default: "unknown"
        }
    }
}
