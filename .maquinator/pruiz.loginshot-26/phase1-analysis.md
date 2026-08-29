---
schema: maquinator/phase1-analysis-v1
ticket_id: pruiz.loginshot-26
run_id: 43b7d2be-7124-4591-a6d0-ad80e66e9d7e
updated_at: 2026-08-29T21:05:00Z
decision: IMPLEMENT
repository: LoginShot
questions: []
---
## Assessment
The ticket requests adding exposure warmup and focus centering features, making them configurable based on prior work by zicojiao (commit f26900934288df3a7c8c26c0c7ba0808d841ee67). The LoginShot repository contains a mature configuration system (AppConfig) where new flags can be added under CaptureConfig. The necessary code changes are localized to CaptureService.swift and its helper OneShotCapture, with clear integration points via existing parameters passed from AppDelegate. All required information is present: the feature implementation, configuration mechanism, and call sites.

## Evidence And Assumptions
Evidence:
- Ticket description explicitly references integrating zicojiao's work with a configurable knob.
- Repository context shows LoginShot is a macOS Swift app using AVFoundation.
- Existing CaptureConfig in AppConfig.swift provides a pattern for adding new settings (e.g., silent, debounceSeconds, cameraUniqueID).
- The commit f26900934288df3a7c8c26c0c7ba0808d841ee67 diff shows concrete changes to add exposure warmup (video output, warmup delay) and focus centering (center exposure metering).
- AppDelegate passes configuration values to CaptureService.captureJPEG, demonstrating how to propagate new settings.
Assumptions:
- The warmup and centering features are appropriate for macOS (the commit includes iOS-specific blocks guarded by #if !os(macOS), indicating macOS compatibility for the core logic).
- A single boolean flag (exposureWarmupEnabled) and duration (exposureWarmupDuration) suffices as the "configurable knob."
- No breaking changes to existing API are required; new parameters can be added with default values preserving current behavior.

## Implementation Plan
1. Update AppConfig.CaptureConfig:
   - Add exposureWarmupEnabled: Bool (default: true)
   - Add exposureWarmupDuration: Double (default: 2.0 seconds)
   - Update validated() to clamp duration >= 0.
2. Update AppDelegate.handleCaptureEvent to pass the new config values to captureJPEG.
3. Update CaptureService.captureJPEG signature to accept exposureWarmupEnabled: Bool and exposureWarmupDuration: Double.
4. Update OneShotCapture.perform to accept the new parameters.
5. In OneShotCapture.run:
   - Conditionally configure center exposure (if exposureWarmupEnabled).
   - Conditionally add AVCaptureVideoDataOutput and set sample buffer delegate (if exposureWarmupEnabled) to run the pipeline for warmup.
   - If enabled, wait for exposureWarmupDuration before capturing.
   - Keep existing 500ms stabilization sleep only when warmup is disabled (to preserve current behavior).
   - Import CoreMedia for Duration.
   - Add helper methods waitForExposureSettle, configureCenterExposure, lockExposureAtCurrent (guarded by #if os(iOS) as in original commit).
6. Update tests (MockCaptureService, etc.) to accommodate new parameters.
7. Verify build and run unit tests.

## Risks
- Introducing the video output delegate may have unintended side effects if the delegate methods are called unexpectedly; however, the implementation only uses it for priming and the delegate is a no-op.
- Adding configuration increases surface area; mitigated by sensible defaults and validation.
- The warmup delay adds latency to capture; configurable duration allows users to trade off speed for quality.
- macOS-specific behavior: the iOS-focused exposure settling and locking are skipped, which is appropriate.
- Potential conflicts with future changes to capture session configuration; mitigated by isolating changes to OneShotCapture.

## Validation
- Unit tests: verify new parameters are passed through and that OneShotCapture conditions on the flag.
- Manual testing: toggle exposureWarmupEnabled and observe changes in capture behavior (e.g., latency, image brightness/centering).
- Regression test: ensure existing functionality (watermark, triggers, etc.) remains unchanged when warmup is disabled.
- Performance: measure capture latency with and without warmup to confirm configurability works.

## Summary
The ticket is ready for implementation. We will add exposure warmup and focus centering features from commit f26900934288df3a7c8c26c0c7ba0808d841ee67, making them configurable via two new settings under CaptureConfig: exposureWarmupEnabled (boolean) and exposureWarmupDuration (seconds, default 2). Changes will be confined to the LoginShot repository, touching AppConfig, AppDelegate, CaptureService, and OneShotCapture. Defaults preserve existing behavior when disabled. No further clarification is needed.
