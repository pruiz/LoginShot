---
schema: maquinator/phase1-analysis-v1
ticket_id: pruiz.loginshot-26
run_id: 26475716-3220-475e-9607-9c6557becf62
updated_at: 2026-08-29T01:06:25Z
decision: IMPLEMENT
repository: LoginShot
questions: []
---

## Assessment
The ticket requests implementing exposure warmup and focus centering features based on a specific commit from a fork, but making them configurable via the application's YAML configuration. The changes involve modifying the camera capture pipeline to center metering, add a video output priming step, and optionally wait for exposure stabilization. All necessary information is present in the ticket and the referenced commit. The repository is a single macOS Swift project (LoginShot) with clear configuration and capture service structures.

## Evidence And Assumptions
- Evidence: The ticket description provides a clear problem statement and solution: re-integrate commit f26900934288df3a7c8c26c0c7ba0808d841ee67 with a configurable knob.
- Evidence: The commit diff shows the exact changes needed: adding exposure warmup duration, center metering configuration, video output delegation, and conditional warm-up delay.
- Evidence: The repository structure includes a CaptureService class that handles one-shot capture, a configuration system (AppConfig) with sections for capture settings, and a test mock that can be updated.
- Assumption: The configurable knob should be a boolean flag to enable/disable the feature and a double for warmup duration (in seconds), added under CaptureConfig.
- Assumption: The existing 500ms stabilization delay should be replaced by the configurable warmup when the feature is enabled, otherwise retained for backward compatibility.
- Assumption: The feature should be macOS-only; the iOS-specific exposure settling and locking steps from the commit are not needed (as indicated by the #if !os(macOS) guard).

## Implementation Plan
1. Update AppConfig.swift: Add `enableExposureWarmup: Bool` and `exposureWarmupDuration: Double` to CaptureConfig with defaults (true, 2.0). Update validation to ensure non-negative duration.
2. Update CaptureService.swift: 
   - Modify `captureJPEG` method signature to accept the two new parameters.
   - Pass them through to `OneShotCapture.perform`.
   - Update `OneShotCapture` init and `perform` to store the parameters.
   - In `run`, conditionally apply center metering, add video output, and sleep for `exposureWarmupDuration` when enabled; otherwise keep the original 500ms sleep.
   - Add protocol conformance to `AVCaptureVideoDataOutputSampleBufferDelegate` and implement the no-op `captureOutput` method.
   - Include the helper methods from the commit (`configureCenterExposure`, `waitForExposureSettle`, `lockExposureAtCurrent`) but note that `waitForExposureSettle` and `lockExposureAtCurrent` are iOS-only and will be no-ops on macOS (guarded by #if os(iOS)).
3. Update AppDelegate.swift: 
   - In `handleCaptureEvent` and `verifySelectedCamera`, pass `config.capture.enableExposureWarmup` and `config.capture.exposureWarmupDuration` to the captureService call.
4. Update MockCaptureService.swift: Add the two new parameters to the mocked `captureJPEG` method and store them for test assertions.
5. Run existing tests to ensure no regressions; add unit tests for the new config values if desired.

## Risks
- Risk: Adding video output and delegating its sample buffer could introduce a performance overhead or threading issue if not handled correctly. Mitigation: The delegate method is a no-op and runs on a dedicated serial queue; the video output is only added when the feature is enabled.
- Risk: Changing the camera configuration (exposure point of interest, exposure mode) might conflict with other camera usage if the app were to support concurrent sessions (it does not). Mitigation: The configuration is applied right before capture and the session is torn down immediately after.
- Risk: The warmup duration could be set too high, causing noticeable delays in capture. Mitigation: Validation ensures non-negative; the default of 2 seconds is reasonable and can be adjusted by users.
- Risk: The config changes require the user to update their YAML file to access the new keys; missing keys will use the safe defaults (enabled, 2.0 seconds). This is acceptable.
- Risk: The commit's iOS-specific code is guarded by #if !os(macOS), so it will not compile on macOS if we accidentally include it. We have placed it inside #if os(iOS) blocks, which is safe.

## Validation
- Unit tests: Verify that the mock captures the new parameters correctly.
- Integration test: Enable/disable the feature via config and observe that the camera behaves differently (e.g., with warmup enabled, the first frame should be properly exposed; without, it may be darker if the camera needs time to adjust).
- Manual testing: Launch the app, toggle the config keys (enableExposureWarmup false/true) and capture images to visually verify improvement in exposure consistency.
- Ensure existing tests still pass, particularly those that rely on the 500ms stabilization delay (they should still pass because when disabled, we keep the delay).

## Human Message
The analysis is complete and the implementation plan is ready. No further clarification is needed; we can proceed with implementing the exposure warmup and focus centering feature as configurable options in the LoginShot application.
