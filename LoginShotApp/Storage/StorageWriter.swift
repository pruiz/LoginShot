import Foundation

/// Errors from the storage writer.
enum StorageError: Error, Sendable {
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

/// Writes captured JPEG images and JSON sidecar metadata to disk atomically.
final class StorageWriter: StorageWriterProtocol, Sendable {

    func writeCapture(
        event: CaptureEvent,
        jpegData: Data,
        metadata: CaptureMetadata,
        config: AppConfig
    ) async throws {
        let directory = config.output.directory

        // 1. Ensure output directory exists
        try ensureDirectory(directory)

        // 2. Derive file paths from metadata.outputPath (already contains full JPEG path)
        let jpegPath = metadata.outputPath
        let jsonPath = (jpegPath as NSString).deletingPathExtension + ".json"

        // 3. Atomic write JPEG
        try atomicWrite(data: jpegData, to: jpegPath)
        Log.storage.info("Wrote image: \(jpegPath) (\(jpegData.count) bytes)")

        // 4. Atomic write JSON sidecar if enabled
        if config.metadata.writeSidecar {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(metadata)
            try atomicWrite(data: jsonData, to: jsonPath)
            Log.storage.info("Wrote sidecar: \(jsonPath)")
        }
    }

    // MARK: - Private

    /// Ensure directory exists, creating intermediate directories if needed.
    private func ensureDirectory(_ path: String) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: path, isDirectory: &isDir) {
            guard isDir.boolValue else {
                throw StorageError.directoryCreationFailed(
                    "Path exists but is not a directory: \(path)"
                )
            }
            return
        }
        do {
            try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
            Log.storage.info("Created output directory: \(path)")
        } catch {
            throw StorageError.directoryCreationFailed(
                "Cannot create directory \(path): \(error.localizedDescription)"
            )
        }
    }

    /// Write data atomically using Foundation's built-in temp-file-and-rename pattern.
    private func atomicWrite(data: Data, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw StorageError.writeFailed(
                "Failed to write \(path): \(error.localizedDescription)"
            )
        }
    }
}
