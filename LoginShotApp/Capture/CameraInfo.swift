/// Information about the camera device used for capture.
struct CameraInfo: Codable, Sendable {
    let deviceName: String
    let position: String

    static let unknown = CameraInfo(deviceName: "Unknown", position: "unknown")
}
