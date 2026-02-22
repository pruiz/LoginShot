@testable import LoginShot
import Foundation

/// Mock implementation of StorageWriterProtocol for testing storage orchestration.
final class MockStorageWriter: StorageWriterProtocol, @unchecked Sendable {

    /// Number of times writeCapture was called.
    var writeCallCount = 0

    /// All events received in order.
    var writtenEvents: [CaptureEvent] = []

    /// All JPEG data received in order.
    var writtenJpegData: [Data] = []

    /// All metadata received in order.
    var writtenMetadata: [CaptureMetadata] = []

    /// All configs received in order.
    var writtenConfigs: [AppConfig] = []

    /// If set, writeCapture will throw this error.
    var shouldThrow: Error?

    func writeCapture(
        event: CaptureEvent,
        jpegData: Data,
        metadata: CaptureMetadata,
        config: AppConfig
    ) async throws {
        // Record call count first so tests can verify method was invoked even if it throws
        writeCallCount += 1
        writtenEvents.append(event)
        writtenJpegData.append(jpegData)
        writtenMetadata.append(metadata)
        writtenConfigs.append(config)

        if let error = shouldThrow {
            throw error
        }
    }

    // MARK: - Test Helpers

    /// Configure to throw an error on write.
    func failWith(_ error: Error) {
        shouldThrow = error
    }

    /// Reset all recorded state.
    func reset() {
        writeCallCount = 0
        writtenEvents.removeAll()
        writtenJpegData.removeAll()
        writtenMetadata.removeAll()
        writtenConfigs.removeAll()
        shouldThrow = nil
    }

    /// Get the last written metadata, if any.
    var lastMetadata: CaptureMetadata? {
        writtenMetadata.last
    }

    /// Get the last written event, if any.
    var lastEvent: CaptureEvent? {
        writtenEvents.last
    }
}
