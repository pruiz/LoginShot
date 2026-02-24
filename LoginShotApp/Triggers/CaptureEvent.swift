/// Events that trigger a webcam capture.
enum CaptureEvent: String, Sendable, CaseIterable {
    /// App launched after user login.
    case sessionOpen = "session-open"
    /// User session unlocked / became active.
    case unlock = "unlock"
    /// User session locked / became inactive (best-effort on macOS).
    case lock = "lock"
    /// Manual capture requested from menu bar.
    case manual = "manual"
}
