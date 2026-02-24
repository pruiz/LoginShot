/// Information about the camera device used for capture.
struct CameraInfo: Codable, Sendable {
    let deviceName: String
    let position: String
    let uniqueID: String?

    static let unknown = CameraInfo(deviceName: "Unknown", position: "unknown", uniqueID: nil)
}

/// Camera device descriptor for UI selection.
struct CameraDeviceDescriptor: Sendable, Equatable {
    let uniqueID: String
    let deviceName: String
    let position: String
}
