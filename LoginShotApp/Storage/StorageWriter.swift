import Foundation

/// Errors from the storage writer.
enum StorageError: Error, Sendable {
    case notImplemented
    case directoryCreationFailed(String)
    case writeFailed(String)
}

/// Protocol for atomic file writes (test seam).
protocol StorageWriterProtocol: Sendable {
    func writeCapture(
        event: CaptureEvent,
        jpegData: Data,
        metadata: CaptureMetadata,
        config: AppConfig
    ) async throws
}

/// Stub implementation — logs a TODO until real atomic writes are wired.
final class StorageWriter: StorageWriterProtocol, Sendable {
    func writeCapture(
        event: CaptureEvent,
        jpegData: Data,
        metadata: CaptureMetadata,
        config: AppConfig
    ) async throws {
        // TODO: Implement atomic file writes (JPEG + JSON sidecar)
        Log.storage.info("TODO: Would write capture for event '\(event.rawValue)' (\(jpegData.count) bytes)")
    }
}
