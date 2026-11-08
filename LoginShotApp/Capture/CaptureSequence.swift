import Foundation

/// One photo produced by the capture pipeline, before the sequence decides
/// which attempt to keep.
struct CapturedFrame: Sendable, Equatable {
    let jpegData: Data
    let meanLuminance: Double?
}

/// Outcome of the warm-up + capture + dark-frame retry sequence.
struct CaptureSequenceResult: Sendable {
    let frame: CapturedFrame
    let attemptCount: Int
    let darkFrameDetected: Bool
    let stabilizationMs: Int
}

/// Runs the ordered steps of a single capture: stabilization wait, session
/// check, first photo, and one optional retry when the photo is nearly black.
///
/// Camera interaction and sleeping are injected so the sequence can be tested
/// without AVFoundation or real delays.
struct CaptureSequence {
    /// Delay that lets the camera settle when no warm-up is configured.
    static let baselineStabilizationMilliseconds = 500
    /// Extra settle time before the second photo of a dark-frame retry.
    static let darkFrameRetryDelayMilliseconds = 1500

    let quality: CaptureQuality
    let isSessionRunning: () -> Bool
    let sleep: (Int) async throws -> Void
    let capturePhoto: () async throws -> CapturedFrame

    init(
        quality: CaptureQuality,
        isSessionRunning: @escaping () -> Bool,
        sleep: @escaping (Int) async throws -> Void = { milliseconds in
            try await Task.sleep(for: .milliseconds(milliseconds))
        },
        capturePhoto: @escaping () async throws -> CapturedFrame
    ) {
        self.quality = quality
        self.isSessionRunning = isSessionRunning
        self.sleep = sleep
        self.capturePhoto = capturePhoto
    }

    /// Effective stabilization delay: the configured warm-up, but never less
    /// than the baseline delay the app has always applied.
    static func stabilizationMilliseconds(for quality: CaptureQuality) -> Int {
        max(baselineStabilizationMilliseconds, quality.exposureWarmUpMilliseconds)
    }

    /// The video output is only useful when frames must keep flowing, either
    /// for a warm-up longer than the baseline or for center-weighted metering.
    static func shouldPrimePipeline(for quality: CaptureQuality) -> Bool {
        quality.centerMeteringEnabled
            || quality.exposureWarmUpMilliseconds > baselineStabilizationMilliseconds
    }

    func run() async throws -> CaptureSequenceResult {
        let stabilizationMs = Self.stabilizationMilliseconds(for: quality)

        if quality.exposureWarmUpMilliseconds > Self.baselineStabilizationMilliseconds {
            Log.capture.info("Warming up exposure for \(stabilizationMs)ms before still capture")
        } else {
            Log.capture.debug("Applying baseline camera stabilization for \(stabilizationMs)ms before still capture")
        }
        try await sleep(stabilizationMs)

        guard isSessionRunning() else {
            throw CaptureError.captureFailed("Capture session failed to start")
        }

        let policy = DarkFramePolicy(
            enabled: quality.darkFrameRetryEnabled,
            threshold: quality.darkFrameThreshold
        )

        var attemptCount = 1
        var frame = try await capturePhoto()
        Log.capture.info("Capture attempt 1: mean luminance \(Self.describe(frame.meanLuminance))")

        if policy.shouldRetry(afterAttempt: attemptCount, meanLuminance: frame.meanLuminance) {
            Log.capture.warning(
                "Dark frame detected (mean luminance \(Self.describe(frame.meanLuminance))); "
                    + "retrying in \(Self.darkFrameRetryDelayMilliseconds)ms"
            )
            try await sleep(Self.darkFrameRetryDelayMilliseconds)

            // Requesting another photo from a stopped session can raise an
            // Objective-C exception, so recheck the camera before retrying.
            guard isSessionRunning() else {
                Log.capture.warning(
                    "Capture session stopped before the dark-frame retry; keeping the first photo"
                )
                return Self.result(
                    frame: frame,
                    attemptCount: attemptCount,
                    policy: policy,
                    stabilizationMs: stabilizationMs
                )
            }

            attemptCount += 1

            do {
                let retry = try await capturePhoto()
                Log.capture.info("Capture attempt \(attemptCount): mean luminance \(Self.describe(retry.meanLuminance))")
                if (retry.meanLuminance ?? 0) > (frame.meanLuminance ?? 0) {
                    frame = retry
                }
            } catch {
                // Keep the first photo: a partial audit image beats none.
                Log.capture.warning(
                    "Dark-frame retry failed (\(error.localizedDescription)); keeping the first photo"
                )
            }
        }

        return Self.result(
            frame: frame,
            attemptCount: attemptCount,
            policy: policy,
            stabilizationMs: stabilizationMs
        )
    }

    /// Assemble the outcome and log a still-dark result.
    private static func result(
        frame: CapturedFrame,
        attemptCount: Int,
        policy: DarkFramePolicy,
        stabilizationMs: Int
    ) -> CaptureSequenceResult {
        let darkFrameDetected = policy.isDark(meanLuminance: frame.meanLuminance)
        if darkFrameDetected {
            Log.capture.warning(
                "Capture still looks dark after \(attemptCount) attempt(s); saving best available image"
            )
        }

        return CaptureSequenceResult(
            frame: frame,
            attemptCount: attemptCount,
            darkFrameDetected: darkFrameDetected,
            stabilizationMs: stabilizationMs
        )
    }

    private static func describe(_ meanLuminance: Double?) -> String {
        guard let meanLuminance else { return "unknown" }
        return String(format: "%.3f", meanLuminance)
    }
}
