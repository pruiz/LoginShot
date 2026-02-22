import Foundation

/// Sidecar metadata written alongside each captured image.
/// Schema matches README.md specification.
struct CaptureMetadata: Codable, Sendable {
    let timestamp: String
    let event: String
    let hostname: String
    let username: String
    let outputPath: String
    let app: AppInfo
    let camera: CameraInfo

    struct AppInfo: Codable, Sendable {
        let bundleId: String
        let version: String
        let build: String
    }

    /// Build metadata for a capture event using current system state.
    static func build(
        event: CaptureEvent,
        outputPath: String,
        cameraInfo: CameraInfo
    ) -> CaptureMetadata {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let bundle = Bundle.main
        return CaptureMetadata(
            timestamp: formatter.string(from: Date()),
            event: event.rawValue,
            hostname: ProcessInfo.processInfo.hostName,
            username: NSUserName(),
            outputPath: outputPath,
            app: AppInfo(
                bundleId: bundle.bundleIdentifier ?? "dev.pruiz.LoginShot",
                version: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
                build: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "1"
            ),
            camera: cameraInfo
        )
    }
}
