import CoreGraphics

/// Estimates image brightness and decides when a capture should be retried
/// because it came out nearly black.
enum ImageLuminance {
    /// Edge length of the downsampled buffer used for the brightness estimate.
    static let sampleDimension = 32

    /// Mean luminance of `image`, in the 0.0 (black) ... 1.0 (white) range.
    /// Returns `nil` when a grayscale drawing context cannot be created.
    static func mean(of image: CGImage) -> Double? {
        let width = sampleDimension
        let height = sampleDimension
        var pixels = [UInt8](repeating: 0, count: width * height)

        let drewImage = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let colorSpace = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2),
                  let context = CGContext(
                      data: buffer.baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else {
                return false
            }

            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard drewImage else { return nil }

        let total = pixels.reduce(0) { $0 + Int($1) }
        return Double(total) / Double(pixels.count * 255)
    }
}

/// Decides whether a captured image is dark enough to justify a retry.
struct DarkFramePolicy: Sendable, Equatable {
    /// Maximum number of photos taken for a single capture event.
    static let maxAttempts = 2

    let enabled: Bool
    let threshold: Double

    /// Brightness check only. Independent of whether retries are enabled, so
    /// the sidecar can still report that a saved photo was dark.
    func isDark(meanLuminance: Double?) -> Bool {
        guard let meanLuminance else { return false }
        return meanLuminance < threshold
    }

    /// - Parameter attempt: 1-based number of the attempt that just completed.
    func shouldRetry(afterAttempt attempt: Int, meanLuminance: Double?) -> Bool {
        enabled && attempt < Self.maxAttempts && isDark(meanLuminance: meanLuminance)
    }
}
