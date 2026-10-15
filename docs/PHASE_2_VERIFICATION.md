# Phase 2: native single-video playback

Implementation and verification performed on 2026-10-14. **The code is implemented, but Phase 2 is not signed off:** physical iOS verification is unavailable, so the roadmap gate remains unchecked.

Follow-up on 2026-10-15: the user confirmed they do not have an iPhone and explicitly approved beginning Phase 3 without claiming hardware sign-off. The remaining checks below are still required before production release.

## Delivered behavior

- Android Media3 1.11.1 with platform decoders, native TextureView in hybrid composition, audio-focus/noisy-route handling, native activity-pause callbacks and activity-detach pause. Lifecycle callbacks unregister on detach, including engine teardown.
- iOS AVPlayer/AVPlayerLayer, asynchronously loaded AVFoundation metadata, interruption/headphone/background pause; host audio-session policy remains untouched.
- Absolute readable local files and file URLs; finite video required. No networking, media-library permissions, content/Photos URI resolver, or bundled codec.
- Display-oriented dimensions, duration, optional frame rate and audio presence. Rotation metadata is applied by native playback and reflected in public dimensions.
- Native source-time and buffering events around 5 Hz, plus state changes; no Flutter playback timer or per-frame channel data. Native players keep audio/video on their own media clock.
- Play, pause, bounded seek, end and replay. Open never auto-plays. Pauses/interruption never auto-resume. Seek acknowledgement means accepted; observe native events for the completed position.
- Exactly one active engine owner. Session/request IDs reject stale events; replacement/disposal cancel pending opens. A 30-second readiness deadline bounds open operations. Close releases native players, observers, callbacks and surfaces idempotently.
- Cubit-owned playback state and metadata, public `EditorPreview`, editor play/pause/seek controls, and an example consuming only the public API. Scrubbing commits one seek when released rather than sending one command per pointer move.

This is **single-source preview**, not timeline rendering. Trim/speed/volume/effect data, overlays and transitions do not yet alter native playback. Export remains unavailable.

## Actual verification

| Check | Result |
| --- | --- |
| Dart format and package analyzer | Passed; no analyzer issues |
| Package unit/widget/bridge tests | 71 passed |
| Example analyzer and unit/widget tests | Passed; 2 tests |
| Kotlin native lifecycle/validation tests | 3 passed |
| Swift XCTest lifecycle/validation tests | 3 passed on iPhone simulator |
| Android 13 physical Xiaomi 21091116I | 9 playback tests passed, including optional 60-second probe, after hybrid-composition fix |
| Android 16/API 36 arm64 emulator | Final expanded 8 playback tests passed |
| iPhone 16 / iOS 26.5 simulator | Final expanded 8 playback tests passed |
| Earlier-phase save/reopen/lifecycle/shell integration | 3 passed on Android emulator and 3 on iOS simulator |
| Native preview visual inspection | First paused frame and controls verified on Android hardware and iOS simulator |
| Physical iPhone | Not connected; not tested |

The playback suite checks real H.264/AAC media, play/pause/native clock, seek/end/replay, silent portrait media, display rotation, missing/relative/remote/corrupt/empty/audio-only inputs, recovery, competing opens, disposal during open, new ownership, ten repeated release/recreate cycles, a seek to 599 seconds in a ten-minute source, lifecycle pause, and real public-editor controls.

Unit/bridge tests additionally cover initialization/retry/disposal races, command acknowledgements not inventing playback state, native event ownership and stale session/request rejection. Existing timeline/persistence tests remain part of the package suite.

## Bugs found by verification

- The first rotation fixture lacked an actual display matrix. Both native tests correctly reported landscape dimensions. Regenerated with FFmpeg's `-display_rotation 90`, independently verified by `ffprobe`, then rotation tests passed.
- Android texture-composed `AndroidView` showed a black initial paused frame although subsequent playback rendered. Native screenshots exposed this gap in state-only tests. Switching the Android preview to hybrid composition displayed frame zero before Play. iOS already displayed frame zero.
- Fixed an iOS replay-seek/pause race using a play-intent generation; interruptions also invalidate that intent. Cancelled metadata tasks check generation before acquiring an asset, and disposal cancels AVAsset loading.
- Earlier-phase shell tests still expected the obsolete "coming soon" copy. Updated the expectation to the current local-video instruction and reran all three earlier-phase checks successfully on both platforms.

Saved initial-frame evidence: [Android hardware](verification/phase2-android.png), [iOS simulator](verification/phase2-ios.png). These demonstrate visible pixels/layout, not frame-rate or A/V-sync accuracy. An earlier screenshot attempt missed the temporary integration-test window; only normal-demo screenshots are retained.

## Physical Android probe: limits of the evidence

The optional one-minute test passed twice, including after the surface fix. The fixture is deliberately small (160×90, 10 fps); this is a sustained-playback smoke test, not a high-resolution stress benchmark.

During the earlier debug integration run, `dumpsys meminfo` sampled total PSS at 349,021 and 424,613 KiB across different test stages (native heap 51,348 and 57,788 KiB; graphics 55,788 and 114,708 KiB). These are whole debug-app snapshots with different live surfaces, **not** a leak measurement, SDK memory delta, or post-fix performance claim. The test runner terminated the process before the final post-release memory query, so no comparable post-release memory plateau was established.

Sampled Android thermal status was 0 before/during/after the probe. Current HAL CPU readings across those samples were approximately 55.7°C, 43.0°C and 41.3°C, with battery 30°C. Final post-fix thermal status was also 0. Charging, ambient conditions and other workloads were uncontrolled. Do not infer production thermal safety from this.

Decoder logs identify `c2.mtk.avc.decoder`; sampled five-second windows for the low-resolution probe reported 50/51 rendered frames and zero drops. Logs also show ExoPlayer release and codec transition to uninitialized. Startup debug logs included skipped-frame warnings: release/profile performance is still uncharacterized.

## Remaining sign-off / release checks

- Physical iPhone: playback, interruptions/routes, repeated lifecycle, memory, codec support and thermal checks.
- Quantitative A/V sync using a flash/beep or lip-sync fixture; the current sine-tone fixture verifies an audio track, not perceptual sync. Native clock ownership alone is not measured sync evidence.
- Profile/release memory plateau, frame pacing and thermal tests on representative 1080p/4K, HEVC/HDR/VFR media and lower-end supported devices; release package size delta.
- Real OS background/foreground, incoming calls, headphone changes and activity recreation. Automated lifecycle tests inject Flutter lifecycle notifications; that is not the entire OS/device matrix.
- Timeout injection and deterministic decoder failure after readiness; corrupt files exercise failure during loading, not every runtime failure mode.
- Swift state is now `@MainActor`-isolated; legacy Pigeon/Flutter protocol conformances use `@preconcurrency`, and main-queue AVFoundation notifications assert main-actor isolation. The tested Xcode 27 / Swift 5-language-mode build passes without the earlier plugin callback-sendability warnings. This is not a full Swift 6 language-mode compatibility claim. Existing Android/Flutter build-tool and XCTest deployment-target warnings remain.

Follow-up checks: Kotlin 3/3, Swift XCTest 3/3, and iOS simulator build passed after native lifecycle/isolation changes. The expanded playback/timeline suite passed 9/9 on Android hardware and 9/9 on iOS simulator. No real OS call/headphone/thermal matrix was added by these tests; those gaps remain above.

## Reproduce

From repository root:

```sh
dart format --output=none --set-exit-if-changed lib test pigeons example/lib example/integration_test
flutter analyze
flutter test
```

From `example/`:

```sh
flutter analyze
flutter test
flutter test integration_test/playback_integration_test.dart -d <device-id> --no-uninstall
flutter test integration_test/playback_integration_test.dart -d <android-phone-id> --no-uninstall --dart-define=VN_SOAK_SECONDS=60
flutter test integration_test/plugin_integration_test.dart -d <device-id> --no-uninstall
flutter run --route=/playback -d <device-id>
flutter build ios --simulator -t lib/main.dart
```

Native tests: `./gradlew :vn_editor:testDebugUnitTest` from `example/android/`; `xcodebuild -workspace Runner.xcworkspace -scheme Runner -destination 'id=<simulator-id>' -only-testing:RunnerTests test` from `example/ios/`. Xcode may shut down the original simulator while running cloned test devices; boot the intended simulator again before Flutter integration tests. Do not run different Android test targets/defines simultaneously against the same build output.
