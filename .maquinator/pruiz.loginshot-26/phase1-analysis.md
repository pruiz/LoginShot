---
schema: maquinator/phase1-analysis-v1
ticket_id: pruiz.loginshot-26
run_id: 08c5c30c-b195-4ac3-a4f1-4512d2794666
updated_at: 2026-08-29T03:45:33Z
decision: IMPLEMENT
repository: LoginShot
questions: []
---

## Assessment
The ticket requests implementing exposure warmup and focus centering features based on a specific commit from a fork (f26900934288df3a7c8c26c0c7ba0808d841ee67), but making them configurable via the application's YAML configuration. The repository LoginShot already includes a configuration system with capture settings, and the CaptureService class handles one-shot capture. The necessary information is present in the ticket and the referenced commit. The main missing pieces are integrating the warmup logic with the existing configurable knob and adding focus centering (setting focus point of interest to center). Additionally, the method `verifySelectedCamera` is referenced but not defined; implementing it is necessary for the verification workflow to function.

## Evidence And Assumptions
- Evidence: The ticket description provides a clear problem statement and solution: re-integrate commit f26900934288df3a7c8c26c0c7ba0808d841ee67 with a configurable knob.
- Evidence: The commit diff shows the exact changes needed for exposure warmup: adding center metering configuration, video output priming, and conditional warm-up delay.
- Evidence: The repository structure includes a CaptureService class that handles one-shot capture, a configuration system (AppConfig) with sections for capture settings (already containing enableExposureWarmup and exposureWarmupDuration), and a test mock that can be updated.
- Evidence: The method `verifySelectedCamera` is called from the menu bar controller's verification action, indicating its purpose is to test the selected camera.
- Assumption: The configurable knob for exposure warmup should control both exposure and focus centering (both enabled/disabled together) for simplicity, using the existing boolean flag and duration.
- Assumption: The existing 500ms stabilization delay should be replaced by the configurable warmup when the feature is enabled, otherwise retained for backward compatibility.
- Assumption: The feature is macOS-only; the iOS-specific exposure settling and locking steps from the commit are not needed and will be guarded by #if os(iOS) (no-op on macOS).
- Assumption: The missing `verifySelectedCamera` method should capture a test image using the current camera and configuration, then report success or failure via an alert, mirroring the logic in `handleCaptureEvent` but without persisting the image.

## Implementation Plan
1. Update CaptureService.swift:
   - Modify `captureJPEG` method signature to accept `enableExposureWarmup: Bool` and `exposureWarmupDuration: Double` (already present in the code we inspected; ensure they are used).
   - Pass these parameters through to `OneShotCapture.perform`.
   - In `OneShotCapture.run`, when `enableExposureWarmup` is true:
     * Configure center exposure (set exposurePointOfInterest to (0.5,0.5) and exposureMode to .continuousAutoExposure).
     * Configure center focus (if device.isFocusPointOfInterestSupported and device.isFocusModeSupported(.continuousAutoFocus), set focusPointOfInterest to (0.5,0.5) and focusMode to .continuousAutoFocus).
     * Add video output (AVCaptureVideoDataOutput) and set sample buffer delegate to self on a serial queue.
     * Start session and wait for `exposureWarmupDuration` seconds.
     * Remove video output after wait.
   - When `enableExposureWarmup` is false, keep the original 500ms stabilization delay (no centering changes, no video output).
   - Add protocol conformance to `AVCaptureVideoDataOutputSampleBufferDelegate` and implement the no-op `captureOutput` method.
   - Include helper methods `configureCenterExposure` and `configureCenterFocus` (similar to the commit's `configureCenterExposure` but for focus).
   - Note: The commit's iOS-specific `waitForExposureSettle` and `lockExposureAtCurrent` are omitted as they are not needed on macOS.
2. Update AppDelegate.swift:
   - In `handleCaptureEvent`, ensure the call to `captureService.captureJPEG` passes `config.capture.enableExposureWarmup` and `config.capture.exposureWarmupDuration` (already present in the code we inspected; verify).
   - Implement the missing `verifySelectedCamera` method:
     * Similar to `handleCaptureEvent` but without writing metadata or persisting image.
     * Capture a test image using the same parameters (maxWidth, quality, cameraUniqueID, watermark settings, hostname, warmup config).
     * On success, show an informational alert; on failure, show an error alert.
     * Use the same timeout and error handling pattern.
3. Update MockCaptureService.swift (if exists) to accept the new parameters for testing.
4. Ensure validation of `exposureWarmupDuration` is non-negative (already present in AppConfig validation).
5. Run existing tests to ensure no regressions.

## Risks
- Risk: Adding video output and delegating its sample buffer could introduce a performance overhead or threading issue if not handled correctly. Mitigation: The delegate method is a no-op and runs on a dedicated serial queue; the video output is only added when the feature is enabled.
- Risk: Changing the camera configuration (exposure point of interest, focus point of interest, exposure mode, focus mode) might conflict with other camera usage if the app were to support concurrent sessions (it does not). Mitigation: The configuration is applied right before capture and the session is torn down immediately after.
- Risk: The warmup duration could be set too high, causing noticeable delays in capture. Mitigation: Validation ensures non-negative; the default of 2 seconds is reasonable and can be adjusted by users.
- Risk: The config changes require the user to update their YAML file to access the new keys; missing keys will use the safe defaults (enabled, 2.0 seconds). This is acceptable.
- Risk: Incorrectly applying focus settings on devices that do not support them could lead to runtime warnings. Mitigation: Check `isFocusPointOfInterestSupported` and `isFocusModeSupported` before setting.

## Validation
- Unit tests: Verify that the mock captures the new parameters correctly and that the configuration flags are passed through.
- Integration test: Enable/disable the feature via config and observe that the camera behaves differently (e.g., with warmup enabled, the first frame should be properly exposed and focused; without, it may be darker or off-center if the camera needs time to adjust).
- Manual testing: Launch the app, toggle the config keys (enableExposureWarmup false/true) and capture images to visually verify improvement in exposure and focus consistency.
- Ensure existing tests still pass, particularly those that rely on the 500ms stabilization delay (they should still pass because when disabled, we keep the delay).
- Verify that the verification workflow (`verifySelectedCamera`) functions correctly and shows appropriate alerts.

## Human Message
The analysis is complete and the implementation plan is ready. No further clarification is needed; we can proceed with implementing the exposure warmup and focus centering feature as configurable options in the LoginShot application, including implementing the missing verification method.
