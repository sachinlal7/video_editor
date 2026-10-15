# Phase 3 verification — timeline media and composition

Date: 2026-10-15. **Requested implementation delivered; Android hardware and iOS simulator checks passed. Physical-iPhone and release qualification remain open.** The user has no physical iPhone and explicitly approved proceeding under that limitation. This is not a production-release waiver. No Phase 4 work has started.

## Delivered

- Public `EditorTimeline`, integrated into `VnEditor` and the example: ruler, native-clock playhead, scrolling, bounded zoom, visible clip culling, selection, trim, long-press move, frame-step actions, neighbor reorder, undo/redo and tap/drag scrubbing.
- One committed history entry per edit gesture. Cursor/selection/zoom do not mutate the project. Invalid overlaps/transitions fail atomically.
- Native JPEG thumbnails and real source-range PCM waveform peaks. Android uses MediaMetadataRetriever/MediaExtractor/MediaCodec; iOS uses AVAssetImageGenerator/AVAssetReader. Silent sources have no fabricated peaks; audio-only extraction is supported.
- Two active extraction jobs, at most 32 queued Dart requests, a 16-result native session LRU, cancellation/retry and disposal cleanup. UI requests six representative thumbnails per clip; native input permits at most eight, bounded to 160×90. Waveforms contain 128 normalized peak bins. Paths and small peak arrays cross Pigeon, not decoded video frames.
- `EditorController.prepareTimeline()` opens a paused cut-only composition. Media3 clipped playlists and AVFoundation compositions handle source switching, trims, black/silent gaps, constant 0.25–4× speed and clip volume. Native events/seeking use edited-project time in timeline mode; `openMedia` retains source-time semantics.
- Preparation is coalesced. Edits/undo invalidate and pause the old plan; the next play/seek rebuilds it. Pause, source replacement, edits and close cannot publish stale preparation or resume a superseded play intent.
- Host light/dark theme, inherited typography, selected/unselected foreground roles, large-text compact/tablet layouts, loading/retry feedback and semantic frame-step alternatives. No new runtime dependency or authored SDK media asset.

`TimelineCubit` owns transient timeline interactions; `EditorController` owns project/history and the extraction queue; native services own decoders, players and cache files. Widgets cancel their extraction requests on removal and never close a supplied controller.

## Actual verification

| Check | Result |
| --- | --- |
| Dart format, package analysis | Passed; no analysis issues |
| Package tests | **97 passed** |
| Example analysis and widget tests | No issues; **2 passed** |
| Playback + timeline-media integration, Xiaomi 21091116I / Android 13 | **14 passed** on final code |
| Same integration, iPhone 16 simulator / iOS 26.5 | **14 passed** on final code |
| Native Kotlin tests | **5 passed** |
| Swift XCTest on simulator | **5 passed** |
| Android profile-mode 200-clip scrolling probe | Passed; metrics below |
| Normal example launch after final tests | Passed on Android hardware and iOS simulator |

Flutter 3.47.7, Dart 3.13.5 and Xcode 27 were used. Native unit tests preceded the last guarded native error-path changes; final integration runs rebuilt and exercised the final sources. The final color fix was followed by full package/example and both integration suites. Existing build-tool/deployment warnings and synchronous AVFoundation metadata deprecations remain; extraction executes off the UI thread. This is not a Swift 6 language-mode certification.

### Added coverage

- Real JPEG decoding/dimension bounds; finite, normalized, nonzero PCM bins; silent and audio-only media.
- Cache path reuse, eviction after eighteen distinct requests, bounded file count and session-file removal on close.
- Invalid ranges/counts, missing/corrupt files, cancelling long-media extraction, failure/retry, queue concurrency, queued/active cancellation and late completion after widget disposal.
- Actual native media-duration validation, malformed compositions, close during preparation, replacement ownership and failed-prepare retry.
- Two-source playback through a gap, speed/volume configuration, project-time seeking into gap/second clip/end, end/replay, edit-triggered rebuild, undo and return to source playback. These functional checks do not establish measured A/V sync or acoustic volume accuracy.
- Pause while play awaits rebuild, edit/close during prepare, duplicate preparation, unsupported layers/effects/transforms/rates, seeking without selection, atomic reorder/move and undo.
- Loading/retry colors, custom-theme selected foreground, long-press move/undo, 200% text on compact light/dark layouts and 1024×768 / 768×1024 tablet-sized widget viewports. Widget dimensions are not tablet-device certification.

The previous nine real-media playback/interaction tests still pass on both targets, including lifecycle, replacement, rotation metadata, distant seeks and repeated ownership. Automated lifecycle events do not replace real phone-call/headphone/background stress tests.

## Profile evidence

Android **profile mode**, physical Xiaomi, 200 one-second placements referencing the small synthetic source, with twelve horizontal flings. Project identity/history were asserted unchanged. Full collector output: [phase3-android-profile.json](verification/phase3-android-profile.json).

| Metric | Measured |
| --- | ---: |
| Frames | 646 |
| Average build / raster | 2.922 / 4.009 ms |
| 99th percentile build / raster | 9.770 / 8.064 ms |
| Worst build / raster | 11.600 / 15.503 ms |
| Missed build / raster budgets (collector's 16.7 ms threshold) | 0 / 0 |

This is one repeated-source scrolling probe, not a 4K, many-unique-source, high-refresh-rate, sustained-thermal, process-memory or codec benchmark. The profile run preceded the foreground-only change. It provides no APK/IPA size-delta claim. The initial attempt could not connect via DDS; the successful run used `--no-dds`. Failed attempts were not counted as passes.

## Issues found and corrected

- iOS simulator composition became ready but failed during playback because CoreAnimation rejected its pixel format. The simulator AVPlayerLayer now requests BGRA buffers; composition playback/seek/replay subsequently passed. Physical iOS retains its default layer format and still requires hardware validation.
- Repeated waveform draw calls and strip repainting increased raster cost. Peaks now use one batched path and loaded strips have a repaint boundary; the recorded final probe met its collector budget.
- Selected clip strips used the unselected foreground role. Loading, waveform, retry, missing-audio and image-error content now use the paired container foreground; a custom-theme regression test guards selection.
- Native file/preparation failures and invalid PCM format/buffer bounds are guarded. Cancellation and stale completion cannot retain editor/project ownership.
- Earlier first-slice fixes remain: compact large-text overflow, paused-source cursor projection, scaled track-label clearance, zoom-independent frame-step trimming/semantics and empty-track guidance.

## Visual/design evidence

Final normal-example captures: [Android hardware, host dark theme](verification/phase3-complete-android.png) and [iOS simulator, host light theme](verification/phase3-complete-ios.png). These are unmodified app captures, not generated mockups. The two-cut example contains a 0.5-second gap and a 2× second clip. Color-bar media provenance is recorded in [PHASE_2_FIXTURES.md](PHASE_2_FIXTURES.md).

The scoped finish review identified the selected-strip foreground mismatch. After the fix and recapture, the verdict was **ship** for that scored fix, not whole-phase release sign-off. Both device captures show unselected clips; selected-state confirmation comes from source inspection and the passing custom-theme widget test, not device imagery. The Simulator app could not be resolved by the desktop UI automation service, so no selected-state simulator capture is claimed.

The documentation pass confirmed an ordinary host-Material extension: no new fixed palette, font, DESIGN.md or sidecar is warranted. The surface contract remains in [PHASE_3_DESIGN.md](PHASE_3_DESIGN.md).

## Limits and open qualification gates

- Cut preview supports **one populated video track**, at most 256 clips / 24 hours and clips at least 1 ms long. Layered visuals, separate audio mixing, effects, transforms and transitions fail explicitly; their renderers belong to later phases. iOS composition targets SDR BT.709; HDR/preview-export parity is not claimed.
- Thumbnails are six representative frames, not frame-accurate zoom-adaptive tiles. Waveforms describe the source range, not a final mixed/effected soundtrack.
- Cache bounds are per session. Cancellation is cooperative between native work units; blocking decoder/image calls may finish before observing it. Crash-orphan cache files rely on OS cache cleanup. Android API 24–26 thumbnail fallback can transiently decode a full frame; low-memory/4K testing remains necessary.
- No physical iPhone is available. Physical-iOS codec/memory/thermal/audio tests, broader Android media/codec/A/V-sync/route-interruption qualification, unique-source stress, real tablet captures and VoiceOver/TalkBack checks remain open. Simulator performance is not device performance.
- Phase 2/3 release-signoff checkboxes remain open to preserve these gates. Requested Step 3 implementation and available Android/iOS simulator functional checks are delivered; no later phase was started.

## Reproduce

From the package root: `dart format lib test pigeons`, `flutter analyze`, `flutter test --timeout 45s`.

From `example/`: `flutter analyze`, `flutter test`, then:

```sh
flutter test integration_test/playback_integration_test.dart integration_test/timeline_media_integration_test.dart -d <device-id> --no-uninstall
flutter drive --profile --no-dds --driver=test_driver/integration_test.dart --target=integration_test/timeline_performance_test.dart -d <android-device-id>
flutter run --route=/playback -d <device-id>
```

Native Android: `./gradlew :vn_editor:testDebugUnitTest` from `example/android/`.

Native iOS: first `flutter build ios --simulator -t lib/main.dart` from `example/`, then `xcodebuild -workspace Runner.xcworkspace -scheme Runner -destination 'id=<simulator-id>' -only-testing:RunnerTests FLUTTER_TARGET=lib/main.dart test` from `example/ios/`. Regenerating the normal target avoids a stale, deleted integration-test launcher. Xcode can shut down the original simulator while creating test clones; boot it before subsequent Flutter runs. Run Android targets sequentially to avoid shared APK-output races.
