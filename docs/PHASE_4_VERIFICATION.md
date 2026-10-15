# Phase 4 verification

Implementation period: 2026-10-14–15. Implementation and available emulator/simulator functional checks are complete. GPU effects and a minimal foreground verification exporter, not the Phase 8 production job engine. Full phase/hardware sign-off remains open.

## Scope and architecture

- Public Flutter package for Android/iOS; existing Cubit/controller owns immutable project edits, history and native preparation. Host applications need not use BLoC.
- Thirteen native GPU stages with finite validated parameters and intensity: color, grayscale, vignette, grain, blur, glow, sharpen, chromatic aberration, distortion, glitch, light leak, pulse and LUT. Four package-authored LUT grades; maximum eight ordered stages per clip.
- Shared catalog/shader body generates both backends. Android uses Media3/OpenGL ES, iOS AVFoundation/Metal. Decoded frames remain native.
- Project filters precede effects. Instance updates preserve order. Effects persist in project JSON; one slider release creates one undo entry. Native failures leave committed edits available for undo/retry.
- Bounded proof export shares the render plan: current even dimensions up to 1080p area/1920 per side, default frame-rate setting 30 (Android ceiling/iOS cadence), at most 60 seconds, foreground MP4, native encoder quality, exclusive new output path, cancellation and two-minute deadline. Full settings, progress, background jobs and Export UI remain Phase 8.
- The user explicitly approved moving the original transition-demo suggestion to Step 7 and proceeding without a physical iPhone. They subsequently approved finishing on the Android emulator when the phone disconnected.

## Test environment and results

Flutter 3.47.7 / Dart 3.13.5, macOS/Xcode 27. Android hardware earlier in the task: Xiaomi 21091116I / Android 13. Final Android target: arm64 Android 16 API 36 emulator. iOS: iPhone 16 / iOS 26.5 simulator. No physical iPhone available.

| Check | Actual result |
| --- | --- |
| Package format/analyze/test | Analysis clean; 103 tests passed |
| Example analyze/test | Analysis clean; 2 tests passed |
| Swift RunnerTests | 6 passed; simulator build/link emits Xcode XCTest deployment-target warnings |
| Android native unit tests | 6 passed; native build has Kotlin safe-call/toolchain warnings |
| Earlier physical Android GPU suite | 5 passed, including all 13 effects at 640×360 and preview/export comparisons; predates final aspect/configuration refinements |
| Final Android emulator GPU suite | 6 passed after source-aspect/silent-export fixes; all 13 stages verified at 1280×720 |
| Android emulator playback/timeline/foundation regression | 9 + 5 + 3 passed |
| iOS simulator GPU/playback/timeline/foundation | 5 + 9 + 5 + 3 = 22 passed together; additional portrait/rotation GPU test passed separately (23 total) |
| Final effect-control theme tests | 2 passed on each emulator/simulator |

The GPU suite checks rendered color/monochrome, zero intensity, removal, every stage, ordered updates, invalid native parameters, cancellation/recovery, unsupported output settings, duplicate jobs, wrong cancellation ID, no overwrite, leading black gaps, trims, 2× speed, duration, undo and preview/export pixel agreement. The final timeline test upscales a 640×360 source to a 1280×720 project and asserts preview surface aspect, allowing one downscaled pixel of integer layout rounding. Additional portrait/rotation exports verify display dimensions, nonblack filtered frames, duration and preservation of silent/audio-bearing single sources. The 24 fps silent fixture exports at 24 fps on Android and 30 fps on iOS; the rotated 30 fps fixture exports at 30 fps on both.

Package tests include registry defaults/bounds/unknown parameters/NaN/infinity, chain limits and persistence, edit races/disposal, one history commit, host themes and 200% text. Native tests cover registry boundaries and lifecycle/invalid composition handling. Earlier playback tests continue to cover missing/corrupt files, portrait/rotation, background pause, replacement/close races, repeated ownership and replay.

## Pixel comparison method

At a fixed timeline time, capture the preview renderer, export, reopen the encoded MP4 at the same time, and compare interior RGB samples. Mean absolute error threshold is 0.08 on normalized channels, allowing compression/decoder differences; this is not a bit-identity test. Final iOS 720p all-stage results range from 0.00167 to 0.00470; final Android emulator 720p results range from 0.00371 to 0.03656 (including SurfaceView integer layout/resampling differences). Earlier physical Android 360p results range from 0.00306 to 0.01533.

Android captures the actual SurfaceView via PixelCopy. iOS AVAssetImageGenerator uses the player's custom videoComposition: pixel assertions establish renderer parity, not AVPlayerLayer screen presentation. Separate screen captures verify presentation. This does not establish cross-platform/color-managed/HDR equivalence. Capture PNG paths cross the test bridge only on request; no per-frame buffers cross Pigeon. Tests remove temporary captures/exports; optional CAPTURE_GPU retains diagnostic PNGs only when explicitly enabled.

## Defects found and fixed

- Android shader helper bound only one scalar from the parameter array; explicit array uniform upload restores all color controls.
- Android paused frames retained the old chain; asynchronous effect updates now reprepare and complete on readiness, with timeout/disposal cancellation.
- Android composition replay after end required stop/prepare; gap frames needed project-canvas normalization before encoding.
- Android preview inherited a square default when size events were absent; project/source metadata now sets authoritative display aspect.
- Android emulated storage disallowed hard links; proof export reserves the final path exclusively and copies on a worker. Consumers must await completion before reading it.
- Additional portrait/rotation proof tests found Android added a silent audio track to silent single-source exports; the source render plan now selects video-only output when metadata has no audio. Timeline plans may retain a silent track for gaps/mixed clips.
- iOS Core Image/Metal coordinate mismatch vertically flipped frames; top-left shader coordinates and explicit orientation normalization restore preview/export agreement.
- UI modal scrim darkened grading previews; transparent barrier preserves focus/dismissal without altering displayed color. LUT controls now show and announce preset names.

## UI evidence and finish review

Final captures: [Android emulator dark](verification/phase4-android-emulator-dark.png), [Android emulator light](verification/phase4-android-emulator-light.png), [iOS dark](verification/phase4-ios-dark.png), [iOS light](verification/phase4-ios-light.png). The older `phase4-android-dark/light.png` files are before-fix physical-device evidence, not final UI verification.

The scoped finish reviewer scored all three requested fixes resolved: undimmed preview, Android full-width aspect, named LUT selection. The documenter confirmed the extension preserves [PHASE_3_DESIGN.md](PHASE_3_DESIGN.md): host Material theming, native preview, controller-owned commits, no new fixed design system. This verdict does not certify the entire editor, tablets, screen readers or native performance.

## Reproduce

From the package root:

```sh
dart run tool/generate_effects.dart
dart run pigeon --input pigeons/vn_editor_api.dart
dart format lib test example/integration_test
flutter analyze
flutter test
```

From `example/`:

```sh
flutter analyze
flutter test test
flutter test integration_test/effects_integration_test.dart integration_test/playback_integration_test.dart integration_test/timeline_media_integration_test.dart integration_test/plugin_integration_test.dart -d DEVICE --no-uninstall
flutter test integration_test/effects_ui_test.dart -d DEVICE --no-uninstall
```

`tool/capture_effect_ui.sh android DEVICE phase4-android-emulator` (or `ios DEVICE phase4-ios`) captures both themes at test markers with Flutter/adb on PATH. Native: `example/android/gradlew :vn_editor:testDebugUnitTest` from that Android directory. For Swift, build normal `lib/main.dart` for the simulator before running `xcodebuild -workspace Runner.xcworkspace -scheme Runner -destination id=SIMULATOR -only-testing:RunnerTests FLUTTER_TARGET=lib/main.dart test` from `example/ios`.

## Pending gates — not inferred passes

- Final Android physical-device reconfirmation after the source/project aspect and export guards; phone unavailable, user will reconnect later.
- All physical-iPhone GPU/codec/memory/thermal/A/V-sync tests. Simulator rendering cannot establish hardware performance.
- Sustained GPU memory/thermal/dropped-frame profiling, low-end devices, maximum chain/size performance, long projects, broader OS/codec/VFR coverage, hardware interruption behavior during export and release binary-size delta.
- HDR/wide-gamut support, cross-device color fidelity and full production export recovery are not claimed. The proof exporter is not crash-resumable and configurable bitrate is not implemented. The default 30 fps setting is an Android ceiling (lower source rates remain lower) and an iOS compositor cadence, not a cross-platform constant-frame-rate guarantee.
- Step 5 overlays, Step 6 audio mixing and Step 7 two-frame transitions/keyframes are not implemented by Step 4.
