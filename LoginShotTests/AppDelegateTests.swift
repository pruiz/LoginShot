import XCTest
@testable import LoginShot

/// Tests for AppDelegate orchestration logic using dependency injection.
@MainActor
final class AppDelegateTests: XCTestCase {

    nonisolated(unsafe) private var mockCaptureService: MockCaptureService!
    nonisolated(unsafe) private var mockStorageWriter: MockStorageWriter!
    nonisolated(unsafe) private var mockConfigLoader: MockConfigLoader!
    nonisolated(unsafe) private var mockUnlockObserver: MockUnlockObserver!
    nonisolated(unsafe) private var mockDateProvider: MockDateProvider!
    nonisolated(unsafe) private var mockAlertPresenter: MockAlertPresenter!

    override func setUp() {
        super.setUp()
        mockCaptureService = MockCaptureService()
        mockStorageWriter = MockStorageWriter()
        mockConfigLoader = MockConfigLoader()
        mockUnlockObserver = MockUnlockObserver()
        mockDateProvider = MockDateProvider(year: 2024, month: 3, day: 15, hour: 10, minute: 30, second: 45)
        mockAlertPresenter = MockAlertPresenter()
    }

    override func tearDown() {
        mockCaptureService = nil
        mockStorageWriter = nil
        mockConfigLoader = nil
        mockUnlockObserver = nil
        mockDateProvider = nil
        mockAlertPresenter = nil
        super.tearDown()
    }

    // MARK: - Helper

    private func makeAppDelegate(config: AppConfig = .default) -> AppDelegate {
        mockConfigLoader.configToReturn = config
        return AppDelegate(
            captureService: mockCaptureService,
            storageWriter: mockStorageWriter,
            configLoader: mockConfigLoader,
            unlockObserver: mockUnlockObserver,
            dateProvider: mockDateProvider,
            alertPresenter: mockAlertPresenter
        )
    }

    // MARK: - Config Loading Tests

    func testReloadConfigCallsConfigLoader() {
        let delegate = makeAppDelegate()
        delegate.reloadConfig()

        XCTAssertEqual(mockConfigLoader.loadCallCount, 1)
    }

    func testReloadConfigUpdatesInternalConfig() {
        var customConfig = AppConfig.default
        customConfig.output.maxWidth = 999

        let delegate = makeAppDelegate(config: customConfig)
        delegate.reloadConfig()

        XCTAssertEqual(delegate.currentConfig.output.maxWidth, 999)
    }

    func testManualReloadSuccessShowsInfoAlert() {
        let delegate = makeAppDelegate()
        delegate.reloadConfig()

        XCTAssertEqual(mockAlertPresenter.infoCalls.count, 1)
        XCTAssertTrue(mockAlertPresenter.errorCalls.isEmpty)
    }

    func testManualReloadFailureKeepsPreviousConfigAndShowsErrorAlert() {
        var initialConfig = AppConfig.default
        initialConfig.output.maxWidth = 777

        let delegate = makeAppDelegate(config: initialConfig)
        delegate.reloadConfig()

        mockConfigLoader.resultToReturn = .failed(
            path: "/tmp/config.yml",
            error: NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "invalid yaml"])
        )

        delegate.reloadConfig()

        XCTAssertEqual(delegate.currentConfig.output.maxWidth, 777)
        XCTAssertEqual(mockAlertPresenter.errorCalls.count, 1)
    }

    func testApplicationStartsObserverWhenLockEnabled() {
        var config = AppConfig.default
        config.triggers.onSessionOpen = false
        config.triggers.onUnlock = false
        config.triggers.onLock = true

        let delegate = makeAppDelegate(config: config)
        delegate.applicationDidFinishLaunching(Notification(name: Notification.Name("didFinishLaunching")))

        XCTAssertTrue(mockUnlockObserver.startCalled)
    }

    func testApplicationDoesNotStartObserverWhenUnlockAndLockDisabled() {
        var config = AppConfig.default
        config.triggers.onSessionOpen = false
        config.triggers.onUnlock = false
        config.triggers.onLock = false

        let delegate = makeAppDelegate(config: config)
        delegate.applicationDidFinishLaunching(Notification(name: Notification.Name("didFinishLaunching")))

        XCTAssertFalse(mockUnlockObserver.startCalled)
    }

    // MARK: - Capture Pipeline Tests

    func testHandleCaptureEventCallsCaptureService() async throws {
        let delegate = makeAppDelegate()
        delegate.reloadConfig()

        delegate.handleCaptureEvent(.sessionOpen)

        // Wait for the async Task to complete
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(mockCaptureService.captureCallCount, 1)
    }

    func testHandleCaptureEventPassesConfigToCapture() async throws {
        var config = AppConfig.default
        config.output.maxWidth = 800
        config.output.jpegQuality = 0.7
        config.capture.cameraUniqueID = "camera-2"
        config.watermark.enabled = true
        config.watermark.format = "yyyy/MM/dd HH:mm"

        let delegate = makeAppDelegate(config: config)
        delegate.reloadConfig()

        delegate.handleCaptureEvent(.unlock)

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(mockCaptureService.lastMaxWidth, 800)
        XCTAssertEqual(mockCaptureService.lastQuality, 0.7)
        XCTAssertEqual(mockCaptureService.lastCameraUniqueID, "camera-2")
        XCTAssertEqual(mockCaptureService.lastWatermarkEnabled, true)
        XCTAssertEqual(mockCaptureService.lastWatermarkFormat, "yyyy/MM/dd HH:mm")
        XCTAssertNotNil(mockCaptureService.lastHostname)
    }

    func testHandleCaptureEventCallsStorageWriter() async throws {
        let delegate = makeAppDelegate()
        delegate.reloadConfig()

        delegate.handleCaptureEvent(.manual)

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(mockStorageWriter.writeCallCount, 1)
    }

    func testHandleCaptureEventPassesCorrectEventToStorage() async throws {
        let delegate = makeAppDelegate()
        delegate.reloadConfig()

        delegate.handleCaptureEvent(.unlock)

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(mockStorageWriter.lastEvent, .unlock)
    }

    func testHandleCaptureEventSupportsLock() async throws {
        let delegate = makeAppDelegate()
        delegate.reloadConfig()

        delegate.handleCaptureEvent(.lock)

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(mockStorageWriter.lastEvent, .lock)
        XCTAssertTrue(mockStorageWriter.lastMetadata?.outputPath?.contains("-lock.jpg") == true)
    }

    func testHandleCaptureEventPassesJpegDataToStorage() async throws {
        let testData = Data([0xAB, 0xCD, 0xEF])
        mockCaptureService.succeedWith(jpegData: testData)

        let delegate = makeAppDelegate()
        delegate.reloadConfig()

        delegate.handleCaptureEvent(.sessionOpen)

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(mockStorageWriter.writtenJpegData.first, testData)
    }

    func testHandleCaptureEventUsesDateProviderForFilename() async throws {
        let delegate = makeAppDelegate()
        delegate.reloadConfig()

        delegate.handleCaptureEvent(.sessionOpen)

        try await Task.sleep(for: .milliseconds(100))

        let metadata = mockStorageWriter.lastMetadata
        XCTAssertNotNil(metadata)
        // The filename should contain the fixed date from MockDateProvider
        XCTAssertTrue(metadata?.outputPath?.contains("2024-03-15T10-30-45") == true)
    }

    func testCaptureErrorDoesNotCrash() async throws {
        mockCaptureService.failWith(CaptureError.cameraUnavailable("Test error"))

        let delegate = makeAppDelegate()
        delegate.reloadConfig()

        // This should not throw - errors are logged, not propagated
        delegate.handleCaptureEvent(.sessionOpen)

        try await Task.sleep(for: .milliseconds(100))

        // Capture was attempted and failure metadata is still persisted
        XCTAssertEqual(mockCaptureService.captureCallCount, 1)
        XCTAssertEqual(mockStorageWriter.writeCallCount, 1)
        XCTAssertEqual(mockStorageWriter.lastMetadata?.status, "failure")
    }

    func testStorageErrorDoesNotCrash() async throws {
        mockStorageWriter.failWith(StorageError.writeFailed("Test error"))

        let delegate = makeAppDelegate()
        delegate.reloadConfig()

        // This should not throw - errors are logged, not propagated
        delegate.handleCaptureEvent(.sessionOpen)

        try await Task.sleep(for: .milliseconds(100))

        // Both capture and storage were attempted
        XCTAssertEqual(mockCaptureService.captureCallCount, 1)
        XCTAssertEqual(mockStorageWriter.writeCallCount, 2)
    }

    // MARK: - Filename Generation Tests

    func testMakeFilenameWithFixedDate() {
        let date = makeDate(year: 2024, month: 6, day: 15, hour: 14, minute: 30, second: 0)
        let filename = AppDelegate.makeFilename(event: .sessionOpen, format: "jpg", date: date)

        XCTAssertEqual(filename, "2024-06-15T14-30-00-session-open.jpg")
    }

    func testMakeFilenameIncludesEventType() {
        let date = makeDate(year: 2024, month: 1, day: 1, hour: 0, minute: 0, second: 0)

        XCTAssertTrue(AppDelegate.makeFilename(event: .sessionOpen, format: "jpg", date: date).contains("session-open"))
        XCTAssertTrue(AppDelegate.makeFilename(event: .unlock, format: "jpg", date: date).contains("unlock"))
        XCTAssertTrue(AppDelegate.makeFilename(event: .lock, format: "jpg", date: date).contains("lock"))
        XCTAssertTrue(AppDelegate.makeFilename(event: .manual, format: "jpg", date: date).contains("manual"))
    }

    func testMakeFilenameIncludesFormat() {
        let date = makeDate(year: 2024, month: 1, day: 1, hour: 0, minute: 0, second: 0)

        XCTAssertTrue(AppDelegate.makeFilename(event: .sessionOpen, format: "jpg", date: date).hasSuffix(".jpg"))
        XCTAssertTrue(AppDelegate.makeFilename(event: .sessionOpen, format: "png", date: date).hasSuffix(".png"))
    }

    // MARK: - Helper

    /// Create a date with specific components in the current/local timezone.
    /// This matches how `makeFilename` formats dates (using local timezone).
    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        // Use current timezone (same as DateFormatter default in makeFilename)
        components.timeZone = TimeZone.current
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}

final class MockAlertPresenter: AlertPresenting, @unchecked Sendable {
    private(set) var infoCalls: [(title: String, message: String)] = []
    private(set) var errorCalls: [(title: String, message: String)] = []

    @MainActor
    func showInfo(title: String, message: String) {
        infoCalls.append((title, message))
    }

    @MainActor
    func showError(title: String, message: String) {
        errorCalls.append((title, message))
    }
}
