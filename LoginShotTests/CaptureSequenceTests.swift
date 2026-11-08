import XCTest
@testable import LoginShot

final class CaptureSequenceTests: XCTestCase {

    // MARK: - Stabilization delay

    func testZeroWarmUpWaitsBaselineDelay() async throws {
        let script = ScriptedCapture(photos: [.success(frame(0x01, luminance: 0.4))])
        let sequence = script.makeSequence(quality: makeQuality(warmUpMs: 0))

        let result = try await sequence.run()

        XCTAssertEqual(script.sleeps, [500])
        XCTAssertEqual(result.stabilizationMs, 500)
    }

    func testShortWarmUpClampsToBaselineDelay() async throws {
        let script = ScriptedCapture(photos: [.success(frame(0x01, luminance: 0.4))])
        let sequence = script.makeSequence(quality: makeQuality(warmUpMs: 300))

        let result = try await sequence.run()

        XCTAssertEqual(script.sleeps, [500])
        XCTAssertEqual(result.stabilizationMs, 500)
    }

    func testConfiguredWarmUpIsUsed() async throws {
        let script = ScriptedCapture(photos: [.success(frame(0x01, luminance: 0.4))])
        let sequence = script.makeSequence(quality: makeQuality(warmUpMs: 2000))

        let result = try await sequence.run()

        XCTAssertEqual(script.sleeps, [2000])
        XCTAssertEqual(result.stabilizationMs, 2000)
    }

    // MARK: - Capture sequence

    func testBrightPhotoSkipsRetry() async throws {
        let script = ScriptedCapture(photos: [.success(frame(0x01, luminance: 0.4))])
        let sequence = script.makeSequence(quality: makeQuality())

        let result = try await sequence.run()

        XCTAssertEqual(script.photoCallCount, 1)
        XCTAssertEqual(script.sleeps, [500])
        XCTAssertEqual(result.frame, frame(0x01, luminance: 0.4))
        XCTAssertEqual(result.attemptCount, 1)
        XCTAssertFalse(result.darkFrameDetected)
    }

    func testDarkPhotoRetriesAndKeepsBrighterPhoto() async throws {
        let script = ScriptedCapture(photos: [
            .success(frame(0x01, luminance: 0.01)),
            .success(frame(0x02, luminance: 0.4))
        ])
        let sequence = script.makeSequence(quality: makeQuality())

        let result = try await sequence.run()

        XCTAssertEqual(script.photoCallCount, 2)
        XCTAssertEqual(script.sleeps, [500, 1500])
        XCTAssertEqual(result.frame.jpegData, Data([0x02]))
        XCTAssertEqual(result.attemptCount, 2)
        XCTAssertFalse(result.darkFrameDetected)
    }

    func testDarkerRetryKeepsFirstPhoto() async throws {
        let script = ScriptedCapture(photos: [
            .success(frame(0x01, luminance: 0.02)),
            .success(frame(0x02, luminance: 0.01))
        ])
        let sequence = script.makeSequence(quality: makeQuality())

        let result = try await sequence.run()

        XCTAssertEqual(result.frame.jpegData, Data([0x01]))
        XCTAssertEqual(result.attemptCount, 2)
        XCTAssertTrue(result.darkFrameDetected)
    }

    func testFailedRetryKeepsFirstPhoto() async throws {
        let script = ScriptedCapture(photos: [
            .success(frame(0x01, luminance: 0.01)),
            .failure(CaptureError.captureFailed("retry boom"))
        ])
        let sequence = script.makeSequence(quality: makeQuality())

        let result = try await sequence.run()

        XCTAssertEqual(script.photoCallCount, 2)
        XCTAssertEqual(result.frame.jpegData, Data([0x01]))
        XCTAssertEqual(result.attemptCount, 2)
        XCTAssertTrue(result.darkFrameDetected)
    }

    func testRetryDisabledSavesDarkPhotoWithoutRetry() async throws {
        let script = ScriptedCapture(photos: [.success(frame(0x01, luminance: 0.01))])
        let sequence = script.makeSequence(quality: makeQuality(retryEnabled: false))

        let result = try await sequence.run()

        XCTAssertEqual(script.photoCallCount, 1)
        XCTAssertEqual(script.sleeps, [500])
        XCTAssertEqual(result.attemptCount, 1)
        XCTAssertTrue(result.darkFrameDetected)
    }

    func testSessionStoppingDuringRetryDelayKeepsFirstPhoto() async throws {
        let script = ScriptedCapture(photos: [
            .success(frame(0x01, luminance: 0.01)),
            .success(frame(0x02, luminance: 0.4))
        ])
        script.onSleep = { milliseconds in
            if milliseconds == 1500 {
                script.sessionRunning = false
            }
        }
        let sequence = script.makeSequence(quality: makeQuality())

        let result = try await sequence.run()

        XCTAssertEqual(script.photoCallCount, 1, "No photo should be requested from a stopped session")
        XCTAssertEqual(script.sleeps, [500, 1500])
        XCTAssertEqual(result.frame.jpegData, Data([0x01]))
        XCTAssertEqual(result.attemptCount, 1)
        XCTAssertTrue(result.darkFrameDetected)
    }

    func testFailedFirstPhotoThrows() async throws {
        let script = ScriptedCapture(photos: [.failure(CaptureError.captureFailed("first boom"))])
        let sequence = script.makeSequence(quality: makeQuality())

        do {
            _ = try await sequence.run()
            XCTFail("Expected the capture sequence to throw")
        } catch {
            XCTAssertEqual(script.photoCallCount, 1)
        }
    }

    func testSessionNotRunningFailsBeforeCapture() async throws {
        let script = ScriptedCapture(photos: [.success(frame(0x01, luminance: 0.4))])
        script.sessionRunning = false
        let sequence = script.makeSequence(quality: makeQuality())

        do {
            _ = try await sequence.run()
            XCTFail("Expected the capture sequence to throw")
        } catch {
            XCTAssertEqual(script.photoCallCount, 0)
        }
    }

    // MARK: - Priming decision

    func testPipelineIsPrimedWhenWarmUpExceedsBaseline() {
        XCTAssertTrue(CaptureSequence.shouldPrimePipeline(for: makeQuality(warmUpMs: 2000)))
    }

    func testPipelineIsPrimedWhenCenterMeteringEnabled() {
        XCTAssertTrue(
            CaptureSequence.shouldPrimePipeline(
                for: makeQuality(warmUpMs: 0, centerMetering: true)
            )
        )
    }

    func testPipelineIsNotPrimedForBaselineOnlyCapture() {
        XCTAssertFalse(
            CaptureSequence.shouldPrimePipeline(
                for: makeQuality(warmUpMs: 500, centerMetering: false)
            )
        )
    }

    func testStabilizationMillisecondsNeverDropsBelowBaseline() {
        XCTAssertEqual(CaptureSequence.stabilizationMilliseconds(for: makeQuality(warmUpMs: -10)), 500)
        XCTAssertEqual(CaptureSequence.stabilizationMilliseconds(for: makeQuality(warmUpMs: 0)), 500)
        XCTAssertEqual(CaptureSequence.stabilizationMilliseconds(for: makeQuality(warmUpMs: 500)), 500)
        XCTAssertEqual(CaptureSequence.stabilizationMilliseconds(for: makeQuality(warmUpMs: 2000)), 2000)
    }

    // MARK: - Helpers

    private func makeQuality(
        warmUpMs: Int = 0,
        centerMetering: Bool = false,
        retryEnabled: Bool = true,
        threshold: Double = 0.03
    ) -> CaptureQuality {
        CaptureQuality(
            exposureWarmUpMilliseconds: warmUpMs,
            centerMeteringEnabled: centerMetering,
            darkFrameRetryEnabled: retryEnabled,
            darkFrameThreshold: threshold
        )
    }

    private func frame(_ marker: UInt8, luminance: Double?) -> CapturedFrame {
        CapturedFrame(jpegData: Data([marker]), meanLuminance: luminance)
    }
}

/// Records sequence interactions and returns scripted photos.
private final class ScriptedCapture {
    var sleeps: [Int] = []
    var sessionRunning = true
    var photoCallCount = 0
    var photos: [Result<CapturedFrame, Error>]
    var onSleep: ((Int) -> Void)?

    init(photos: [Result<CapturedFrame, Error>]) {
        self.photos = photos
    }

    func makeSequence(quality: CaptureQuality) -> CaptureSequence {
        CaptureSequence(
            quality: quality,
            isSessionRunning: { self.sessionRunning },
            sleep: { milliseconds in
                self.sleeps.append(milliseconds)
                self.onSleep?(milliseconds)
            },
            capturePhoto: {
                let index = self.photoCallCount
                self.photoCallCount += 1
                guard index < self.photos.count else {
                    throw CaptureError.captureFailed("No scripted photo for attempt \(index + 1)")
                }
                return try self.photos[index].get()
            }
        )
    }
}
