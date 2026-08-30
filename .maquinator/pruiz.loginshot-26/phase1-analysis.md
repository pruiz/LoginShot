---
schema: maquinator/phase1-analysis-v1
ticket_id: pruiz.loginshot-26
run_id: 465ff445-5dac-45de-bef1-bf5a7aaa9b9d
updated_at: 2026-08-30T04:15:00Z
decision: IMPLEMENT
repository: LoginShot
questions: []
---

## Assessment

The ticket requests re-integration of exposure warm-up and focus centering work from a fork (zicojiao/LoginShot commit f269009), with the addition of a configurable knob. I have examined both the fork's implementation and the current LoginShot codebase.

**Key findings:**
- The fork commit adds three core improvements: (1) a 2-second exposure warm-up by running a video pipeline before still capture, (2) center-weighted exposure metering (exposurePointOfInterest at 0.5, 0.5), and (3) exposure lock on iOS after warm-up.
- The current LoginShot codebase has a simple 500ms sleep for sensor stabilization but lacks center metering and the video pipeline warm-up.
- The app already has a mature YAML-based configuration system (`AppConfig.CaptureConfig`) with validation, making it straightforward to add configurable knobs.
- The implementation is confined to `LoginShotApp/Capture/CaptureService.swift` (the `OneShotCapture` class), a single file with clear separation of concerns.
- No multi-repository changes are needed; all work is within the `LoginShot` repository.

**Confidence**: High. The fork provides a working reference implementation, the target codebase is well-structured, and the configuration system is ready for extension.

## Evidence And Assumptions

**Confirmed facts:**
- Ticket references commit `f26900934288df3a7c8c26c0c7ba0808d841ee67` from `zicojiao/LoginShot`.
- That commit modifies only `LoginShotApp/Capture/CaptureService.swift` (+93/-4 lines).
- Current `LoginShot` repo's `CaptureService.swift` is at a similar baseline (no video output, 500ms sleep, no center metering).
- Configuration is loaded via `ConfigLoader` from YAML at `~/.config/LoginShot/config.yml` or `~/Library/Application Support/LoginShot/config.yml`.
- `AppConfig.CaptureConfig` already exists with `silent`, `debounceSeconds`, `cameraUniqueID` fields.
- The app is macOS-only (no iOS target), so iOS-specific exposure lock code from the fork can be omitted or guarded.

**Assumptions:**
- The "configurable knob" means adding YAML config options for: warm-up duration (default 2s), enable/disable center metering (default true), and optionally enable/disable warm-up entirely.
- macOS does not support `AVCaptureDevice.setExposureModeCustom` (iOS-only), so exposure locking is not applicable; center metering + warm-up are the primary mechanisms.
- The video output delegate (`AVCaptureVideoDataOutputSampleBufferDelegate`) is a no-op — it exists solely to keep the pipeline running.
- Existing tests (`MockCaptureService`, `ConfigLoaderTests`) will need updates to cover new config fields and capture behavior.

**Missing evidence (not blocking):**
- No sample config file in the repo to confirm exact YAML structure for new fields (but `ConfigLoader.parse` shows the pattern clearly).
- No explicit performance requirements for warm-up duration (fork uses 2s; we'll make it configurable).

## Implementation Plan

**Phase 2 tasks (ordered):**

1. **Extend `AppConfig.CaptureConfig`** (in `AppConfig.swift`):
   - Add `exposureWarmUpSeconds: Int` (default: 2, min: 0 to disable).
   - Add `centerMeteringEnabled: Bool` (default: true).
   - Update `validated()` to clamp `exposureWarmUpSeconds` ≥ 0 and log warnings.

2. **Extend `ConfigLoader.parse`** (in `ConfigLoader.swift`):
   - Read `capture.exposureWarmUpSeconds` (Int, default 2).
   - Read `capture.centerMeteringEnabled` (Bool, default true).
   - Coerce types safely (YAML may give Int/Double/Bool).

3. **Modify `OneShotCapture`** (in `CaptureService.swift`):
   - Import `CoreMedia` (needed for `CMSampleBuffer`).
   - Conform to `AVCaptureVideoDataOutputSampleBufferDelegate`.
   - Add `exposureWarmUpDuration` and `centerMeteringEnabled` properties (passed from config).
   - In `run()`:
     - If `centerMeteringEnabled`, call `configureCenterExposure(device:)` before starting session.
     - Create and add `AVCaptureVideoDataOutput` with sample buffer delegate (self) on a dedicated queue.
     - Replace 500ms sleep with `exposureWarmUpDuration` sleep.
     - Remove iOS-specific `waitForExposureSettle` and `lockExposureAtCurrent` (not applicable on macOS).
   - Implement no-op `captureOutput(_:didOutput:from:)` for video delegate.
   - Keep `configureCenterExposure(device:)` static helper (sets `exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)` and `exposureMode = .continuousAutoExposure`).

4. **Wire config through `AppDelegate.handleCaptureEvent`**:
   - Pass `config.capture.exposureWarmUpSeconds` and `config.capture.centerMeteringEnabled` to `captureService.captureJPEG(...)`.
   - Update `CaptureServiceProtocol` and `CaptureService.captureJPEG` signature to accept new parameters.
   - Update `MockCaptureService` to record/ignore new parameters.

5. **Update tests**:
   - `ConfigLoaderTests`: add cases for new capture config fields (present, missing, invalid).
   - `AppConfigTests`: validate clamping/warnings for `exposureWarmUpSeconds`.
   - `MockCaptureService`: add `lastExposureWarmUpSeconds`, `lastCenterMeteringEnabled` tracking.
   - Integration test (if any) to verify capture still works with new params.

6. **Documentation** (optional but recommended):
   - Update sample config (if `ConfigWriter.writeSampleConfig` exists) with new fields commented.

## Risks

- **Compatibility**: macOS versions < 12 may not support `exposurePointOfInterest` on all external cameras. The fork guards with `isExposurePointOfInterestSupported` — we must keep that check.
- **Performance**: A 2s warm-up adds latency to every capture. Mitigated by making it configurable (0 = disabled).
- **Resource usage**: Adding a video output increases memory/CPU briefly. The delegate is a no-op; impact is minimal.
- **Configuration migration**: Existing config files without new fields will get defaults — safe because defaults match fork behavior.
- **Testing**: `OneShotCapture` is private and not directly testable; reliance on `MockCaptureService` and integration tests is appropriate.
- **Thread safety**: The video output delegate runs on a background queue; `OneShotCapture` is `@unchecked Sendable` — ensure no shared mutable state is accessed in `captureOutput`.

## Validation

**Automated checks (Phase 2 must pass):**
- `swift build` / `xcodebuild` compiles without warnings.
- All existing unit tests pass (`swift test`).
- New `ConfigLoaderTests` cases for `exposureWarmUpSeconds` and `centerMeteringEnabled` pass.
- `AppConfigTests` validate clamping (negative warm-up → 0, non-bool centerMetering → default true).
- `MockCaptureService` correctly records new parameters.

**Manual verification (smoke test):**
- Run app with default config → capture triggers, image not dark, face reasonably exposed.
- Set `exposureWarmUpSeconds: 0` → capture fires quickly (no warm-up delay).
- Set `centerMeteringEnabled: false` → camera uses default metering (may expose for background).
- Verify config reload picks up changes without restart (except warm-up applies on next capture).

## Summary

**Decision: IMPLEMENT** on the `LoginShot` repository.

The ticket is actionable. The fork commit provides a complete, working reference implementation for exposure warm-up (2s video pipeline run) and center metering (exposure point at frame center). The current codebase has a clean configuration system ready for two new knobs: `capture.exposureWarmUpSeconds` (Int, default 2) and `capture.centerMeteringEnabled` (Bool, default true).

**Next step (Phase 2):**
1. Add the two config fields to `AppConfig.CaptureConfig` and `ConfigLoader.parse` with validation.
2. Refactor `OneShotCapture` to accept warm-up duration and center metering flag, add video output for pipeline priming, apply center metering when enabled, and sleep for the configured warm-up duration.
3. Plumb the new parameters through `CaptureServiceProtocol`, `CaptureService`, `AppDelegate.handleCaptureEvent`, and `MockCaptureService`.
4. Extend unit tests for config parsing/validation and mock capture.
5. Build, test, and verify manually.

No blocking questions remain. The work is scoped to a single repository and a single primary source file.
