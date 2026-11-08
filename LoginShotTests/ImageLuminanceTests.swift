import XCTest
@testable import LoginShot

final class ImageLuminanceTests: XCTestCase {

    // MARK: - ImageLuminance

    func testBlackImageHasNearZeroLuminance() throws {
        let luminance = try XCTUnwrap(ImageLuminance.mean(of: makeImage(gray: 0.0)))
        XCTAssertEqual(luminance, 0.0, accuracy: 0.01)
    }

    func testWhiteImageHasNearOneLuminance() throws {
        let luminance = try XCTUnwrap(ImageLuminance.mean(of: makeImage(gray: 1.0)))
        XCTAssertEqual(luminance, 1.0, accuracy: 0.01)
    }

    func testMidGrayImageHasMidLuminance() throws {
        let luminance = try XCTUnwrap(ImageLuminance.mean(of: makeImage(gray: 0.5)))
        XCTAssertEqual(luminance, 0.5, accuracy: 0.02)
    }

    func testLuminanceDoesNotDependOnImageSize() throws {
        let small = try XCTUnwrap(ImageLuminance.mean(of: makeImage(gray: 0.25, size: 16)))
        let large = try XCTUnwrap(ImageLuminance.mean(of: makeImage(gray: 0.25, size: 200)))
        XCTAssertEqual(small, large, accuracy: 0.01)
    }

    // MARK: - DarkFramePolicy

    func testDarkFrameDetectedBelowThreshold() {
        let policy = DarkFramePolicy(enabled: true, threshold: 0.03)

        XCTAssertTrue(policy.isDark(meanLuminance: 0.01))
        XCTAssertTrue(policy.shouldRetry(afterAttempt: 1, meanLuminance: 0.01))
    }

    func testBrightFrameIsNotDark() {
        let policy = DarkFramePolicy(enabled: true, threshold: 0.03)

        XCTAssertFalse(policy.isDark(meanLuminance: 0.4))
        XCTAssertFalse(policy.shouldRetry(afterAttempt: 1, meanLuminance: 0.4))
    }

    func testDisabledRetryStillReportsDarkFrame() {
        let policy = DarkFramePolicy(enabled: false, threshold: 0.9)

        XCTAssertTrue(policy.isDark(meanLuminance: 0.0))
        XCTAssertFalse(policy.shouldRetry(afterAttempt: 1, meanLuminance: 0.0))
    }

    func testUnknownLuminanceIsNotTreatedAsDark() {
        let policy = DarkFramePolicy(enabled: true, threshold: 0.03)

        XCTAssertFalse(policy.isDark(meanLuminance: nil))
        XCTAssertFalse(policy.shouldRetry(afterAttempt: 1, meanLuminance: nil))
    }

    func testOnlyOneRetryIsAllowed() {
        let policy = DarkFramePolicy(enabled: true, threshold: 0.03)

        XCTAssertTrue(policy.shouldRetry(afterAttempt: 1, meanLuminance: 0.0))
        XCTAssertFalse(policy.shouldRetry(afterAttempt: 2, meanLuminance: 0.0))
    }

    func testZeroThresholdDisablesBrightnessCheck() {
        let policy = DarkFramePolicy(enabled: true, threshold: 0.0)

        XCTAssertFalse(policy.isDark(meanLuminance: 0.0))
    }

    // MARK: - Helper

    private func makeImage(gray: CGFloat, size: Int = 64) throws -> CGImage {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))

        context.setFillColor(red: gray, green: gray, blue: gray, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        return try XCTUnwrap(context.makeImage())
    }
}
