import AVFoundation
import CoreGraphics
import CoreMedia
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum WatermarkFormatter {
    static let defaultTimestampFormat = "yyyy-MM-dd HH:mm:ss zzz"

    static func text(hostname: String, date: Date, format: String) -> String {
        "\(hostname) \(timestamp(date: date, format: format))"
    }

    static func timestamp(date: Date, format: String) -> String {
        let trimmed = format.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenFormat = trimmed.isEmpty ? defaultTimestampFormat : trimmed

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = chosenFormat
        let value = formatter.string(from: date)
        if value.isEmpty || (looksLikeLiteralFormat(chosenFormat) && value == chosenFormat) {
            formatter.dateFormat = defaultTimestampFormat
            return formatter.string(from: date)
        }
        return value
    }

    private static func looksLikeLiteralFormat(_ format: String) -> Bool {
        let symbols = CharacterSet(charactersIn: "yYMdDEHhmsSaAzZvV")
        return format.rangeOfCharacter(from: symbols) == nil
    }
}

/// Result of a successful one-shot capture.
struct CaptureResult: Sendable {
    let jpegData: Data
    let cameraInfo: CameraInfo
    /// Number of photos taken for this capture (2 when a dark frame was retried).
    let attemptCount: Int
    /// Mean luminance of the saved image (0.0 black ... 1.0 white), when measurable.
    let meanLuminance: Double?
    /// Whether the saved image was still considered a dark frame.
    let darkFrameDetected: Bool
    /// Stabilization delay applied before the first photo, in milliseconds.
    let exposureWarmUpMs: Int

    init(
        jpegData: Data,
        cameraInfo: CameraInfo,
        attemptCount: Int = 1,
        meanLuminance: Double? = nil,
        darkFrameDetected: Bool = false,
        exposureWarmUpMs: Int = 0
    ) {
        self.jpegData = jpegData
        self.cameraInfo = cameraInfo
        self.attemptCount = attemptCount
        self.meanLuminance = meanLuminance
        self.darkFrameDetected = darkFrameDetected
        self.exposureWarmUpMs = exposureWarmUpMs
    }
}

/// Camera quality settings applied to a single capture.
struct CaptureQuality: Sendable, Equatable {
    /// Requested warm-up before the still capture, in milliseconds.
    /// Values below the built-in baseline delay are applied as the baseline.
    var exposureWarmUpMilliseconds: Int
    /// Meter exposure from the center of the frame when the camera supports it.
    var centerMeteringEnabled: Bool
    /// Take a second photo when the first one is nearly black.
    var darkFrameRetryEnabled: Bool
    /// Mean luminance below which a photo counts as a dark frame.
    var darkFrameThreshold: Double
}

/// Errors from the capture pipeline.
enum CaptureError: Error, Sendable {
    case notImplemented
    case cameraUnavailable(String)
    case captureFailed(String)
}

/// Protocol for one-shot webcam capture (test seam).
protocol CaptureServiceProtocol: Sendable {
    func captureJPEG(
        maxWidth: Int,
        quality: Double,
        cameraUniqueID: String?,
        watermarkEnabled: Bool,
        watermarkFormat: String,
        hostname: String,
        captureQuality: CaptureQuality
    ) async throws -> CaptureResult
    func listCameras() -> [CameraDeviceDescriptor]
}

/// Real AVFoundation one-shot capture implementation.
/// Acquires camera, captures a single photo, resizes if needed, releases camera.
final class CaptureService: CaptureServiceProtocol, Sendable {
    func captureJPEG(
        maxWidth: Int,
        quality: Double,
        cameraUniqueID: String?,
        watermarkEnabled: Bool,
        watermarkFormat: String,
        hostname: String,
        captureQuality: CaptureQuality
    ) async throws -> CaptureResult {
        try await OneShotCapture.perform(
            maxWidth: maxWidth,
            quality: quality,
            cameraUniqueID: cameraUniqueID,
            watermarkEnabled: watermarkEnabled,
            watermarkFormat: watermarkFormat,
            hostname: hostname,
            captureQuality: captureQuality
        )
    }

    func listCameras() -> [CameraDeviceDescriptor] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )

        return discovery.devices.map {
            CameraDeviceDescriptor(
                uniqueID: $0.uniqueID,
                deviceName: $0.localizedName,
                position: OneShotCapture.positionString($0.position)
            )
        }
    }
}

// MARK: - One-Shot Capture Helper

/// Manages a single AVCaptureSession lifecycle: setup → capture → teardown.
/// Uses @unchecked Sendable because all AVFoundation state is accessed
/// sequentially (never concurrently) through the async run() method.
private final class OneShotCapture: NSObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    private let maxWidth: Int
    private let quality: Double
    private var continuation: CheckedContinuation<CapturedFrame, Error>?
    private var deviceName: String = "Unknown"
    private var devicePosition: String = "unknown"
    private var selectedCameraUniqueID: String?
    private let watermarkEnabled: Bool
    private let watermarkFormat: String
    private let hostname: String
    private let captureQuality: CaptureQuality

    private init(
        maxWidth: Int,
        quality: Double,
        watermarkEnabled: Bool,
        watermarkFormat: String,
        hostname: String,
        captureQuality: CaptureQuality
    ) {
        self.maxWidth = maxWidth
        self.quality = quality
        self.watermarkEnabled = watermarkEnabled
        self.watermarkFormat = watermarkFormat
        self.hostname = hostname
        self.captureQuality = captureQuality
        super.init()
    }

    /// Entry point: check authorization, find camera, capture, return JPEG data.
    static func perform(
        maxWidth: Int,
        quality: Double,
        cameraUniqueID: String?,
        watermarkEnabled: Bool,
        watermarkFormat: String,
        hostname: String,
        captureQuality: CaptureQuality
    ) async throws -> CaptureResult {
        // 1. Check / request camera authorization
        try await ensureCameraAuthorization()

        // 2. Run capture
        let capture = OneShotCapture(
            maxWidth: maxWidth,
            quality: quality,
            watermarkEnabled: watermarkEnabled,
            watermarkFormat: watermarkFormat,
            hostname: hostname,
            captureQuality: captureQuality
        )
        return try await capture.run(cameraUniqueID: cameraUniqueID)
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

    private func run(cameraUniqueID: String?) async throws -> CaptureResult {
        // Find selected or default video device
        guard let device = selectCamera(cameraUniqueID: cameraUniqueID) else {
            throw CaptureError.cameraUnavailable("No video capture device found")
        }

        deviceName = device.localizedName
        devicePosition = Self.positionString(device.position)
        selectedCameraUniqueID = device.uniqueID
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

        if captureQuality.centerMeteringEnabled {
            Self.configureCenterExposure(device: device)
        }

        if CaptureSequence.shouldPrimePipeline(for: captureQuality) {
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(
                self,
                queue: DispatchQueue(label: "dev.pruiz.LoginShot.video-priming")
            )
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            } else {
                Log.capture.warning("Cannot add video output; continuing without pipeline priming")
            }
        }

        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else {
            throw CaptureError.captureFailed("Cannot add photo output to capture session")
        }
        session.addOutput(output)

        // Start session, then run the shared warm-up / capture / retry sequence.
        session.startRunning()

        let sequence = CaptureSequence(
            quality: captureQuality,
            isSessionRunning: { session.isRunning },
            capturePhoto: { try await self.capturePhoto(with: output) }
        )
        let outcome = try await sequence.run()

        let result = CaptureResult(
            jpegData: outcome.frame.jpegData,
            cameraInfo: CameraInfo(
                deviceName: deviceName,
                position: devicePosition,
                uniqueID: selectedCameraUniqueID
            ),
            attemptCount: outcome.attemptCount,
            meanLuminance: outcome.frame.meanLuminance,
            darkFrameDetected: outcome.darkFrameDetected,
            exposureWarmUpMs: outcome.stabilizationMs
        )

        // Tear down: remove inputs/outputs before stopping to avoid
        // "NSKVONotifying_AVCapturePhotoOutput not linked" runtime warning.
        session.stopRunning()
        for sessionInput in session.inputs {
            session.removeInput(sessionInput)
        }
        for sessionOutput in session.outputs {
            session.removeOutput(sessionOutput)
        }
        Log.capture.info(
            "Capture complete (\(result.jpegData.count) bytes, attempt(s): \(result.attemptCount))"
        )

        return result
    }

    private func capturePhoto(with output: AVCapturePhotoOutput) async throws -> CapturedFrame {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let settings = AVCapturePhotoSettings()
            output.capturePhoto(with: settings, delegate: self)
        }
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
            continuation.resume(returning: try processImage(data: imageData))
        } catch {
            continuation.resume(throwing: error)
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // No-op: the video output only exists to keep frames flowing so the
        // camera's auto-exposure and auto-white-balance algorithms converge.
    }

    // MARK: - Image Processing

    private func processImage(data: Data) throws -> CapturedFrame {
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

        // Measure brightness before the watermark is drawn on top.
        let meanLuminance = ImageLuminance.mean(of: finalImage)

        let imageForEncoding: CGImage
        if watermarkEnabled {
            imageForEncoding = try applyWatermark(to: finalImage)
        } else {
            imageForEncoding = finalImage
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
        CGImageDestinationAddImage(destination, imageForEncoding, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.captureFailed("Failed to finalize JPEG encoding")
        }

        return CapturedFrame(jpegData: mutableData as Data, meanLuminance: meanLuminance)
    }

    // MARK: - Exposure Metering

    /// Configure center-weighted exposure metering.
    /// Sets exposurePointOfInterest to the frame center (0.5, 0.5) and
    /// exposureMode to continuousAutoExposure if supported by the device.
    private static func configureCenterExposure(device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            guard device.isExposurePointOfInterestSupported else {
                Log.capture.info("Camera does not support exposurePointOfInterest; using default metering")
                return
            }

            device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            Log.capture.debug("Configured center-weighted exposure metering")
        } catch {
            Log.capture.warning("Failed to configure center exposure metering: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    static func positionString(_ position: AVCaptureDevice.Position) -> String {
        switch position {
        case .front: "front"
        case .back: "back"
        case .unspecified: "unspecified"
        @unknown default: "unknown"
        }
    }

    private func selectCamera(cameraUniqueID: String?) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )

        if let cameraUniqueID,
           let selected = discovery.devices.first(where: { $0.uniqueID == cameraUniqueID }) {
            return selected
        }

        if let cameraUniqueID {
            Log.capture.warning("Configured cameraUniqueID \(cameraUniqueID) not found; falling back to default camera")
        }

        if let fallback = AVCaptureDevice.default(for: .video) {
            return fallback
        }

        return discovery.devices.first
    }

    private func applyWatermark(to image: CGImage) throws -> CGImage {
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: image.width,
                  height: image.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw CaptureError.captureFailed("Failed to create graphics context for watermark")
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        let text = WatermarkFormatter.text(hostname: hostname, date: Date(), format: watermarkFormat)
        let fontSize = max(16.0, CGFloat(image.width) * 0.02)
        let font = CTFontCreateWithName("Menlo" as CFString, fontSize, nil)

        let whiteAttrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1.0, alpha: 1.0)
        ]
        let blackAttrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.0, alpha: 0.85)
        ]

        let whiteLine = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: whiteAttrs))
        let blackLine = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: blackAttrs))

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let textWidth = CGFloat(CTLineGetTypographicBounds(whiteLine, &ascent, &descent, &leading))

        let margin: CGFloat = 20
        let x = max(margin, CGFloat(image.width) - textWidth - margin)
        let y = margin + descent

        context.textMatrix = .identity
        let offsets: [(CGFloat, CGFloat)] = [(-1, -1), (-1, 1), (1, -1), (1, 1)]
        for (dx, dy) in offsets {
            context.textPosition = CGPoint(x: x + dx, y: y + dy)
            CTLineDraw(blackLine, context)
        }

        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(whiteLine, context)

        guard let watermarked = context.makeImage() else {
            throw CaptureError.captureFailed("Failed to produce watermarked image")
        }

        Log.capture.debug("Applied watermark to capture")
        return watermarked
    }
}
