# vn_editor

A lightweight, reusable Flutter video-editor SDK foundation for Android and iOS.

Phase 0 establishes the initial Dart API and a generated Pigeon bridge. Phase 1 is complete: video/audio/image/overlay timeline data, transforms, filter/effect commands, undo/redo, and versioned project save/load. Flutter owns the editor experience and project orchestration; Kotlin and Swift own media playback, rendering, and export as those phases are implemented.

Phase 2 native single-video playback is implemented using Android Media3 and iOS AVPlayer. Android device/emulator and iOS simulator checks pass; the phase's physical-iOS verification gate is still open. See [playback evidence and limits](docs/PHASE_2_VERIFICATION.md).

Phase 3 implementation now includes native thumbnails, real audio waveforms, timeline editing and cut-composition playback. Android hardware and iOS simulator verification is recorded; physical-iPhone and release qualification remain open under the user-approved sequencing exception. See [timeline verification and limits](docs/PHASE_3_VERIFICATION.md).

Phase 4 adds 13 native GPU stages, four package-authored LUT grades, persistent clip adjustments with undo/redo, host-themed controls, and a bounded foreground export for preview/export verification. See [effect API and limits](docs/EFFECTS.md) and [verification](docs/PHASE_4_VERIFICATION.md). Full export jobs and controls remain Phase 8.

## Requirements

- Flutter 3.47.7 or newer (tested baseline)
- Dart 3.13.5 or newer
- Android API 24 or newer
- iOS 15 or newer

## Add the package

```yaml
dependencies:
  vn_editor:
    git:
      url: https://github.com/sachinlal7/video_editor.git
```

## Open the editor

```dart
final project = EditorProject.empty(
  id: 'My project',
  width: 1080,
  height: 1920,
  frameRate: 30,
);

await Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => VnEditor(
      project: project,
      onExportComplete: (result) {
        debugPrint(result.path);
      },
    ),
  ),
);
```

The 0.x API is provisional. Only one native editor can be active per Flutter engine; close it before opening another. A controller created by `VnEditor` is owned and closed by the widget; callers must close an externally supplied controller. Data-only timeline edits can run without native initialization. Rendered effects are supported within the renderer-v1 limits below.

The `onExportComplete` callback and export events are reserved for later phases. Unimplemented native commands throw `PlatformException` with code `feature-unavailable`. Export stays disabled in the example.

State uses BLoC's Cubit internally. Widgets delegate to the controller, which uses a domain port implemented by the native Pigeon adapter; domain models have no Flutter imports. Host apps can use any state-management approach.

See [docs/ROADMAP.md](docs/ROADMAP.md) for architecture, phase order, and completion criteria.

## Native single-video playback

```dart
final controller = EditorController(project: project);
await controller.initialize();
final metadata = await controller.openMedia('/absolute/app-owned/video.mp4');
await controller.play();
await controller.pause();
await controller.seek(const Duration(seconds: 2));
// Mount VnEditor(project: project, controller: controller) for built-in controls,
// or EditorPreview(controller: controller) for a preview with your own controls.
// Observe controller.stream / controller.state.playback for native source time.
// When the host screen closes:
await controller.close();
```

Accepts absolute local file paths and `file://` URLs, not remote URLs, Android content URIs, or iOS Photos identifiers. The host imports/copies authorized media into a readable local file first. Open resolves when a finite video is ready; playback does not start automatically. Audio-only files are rejected. Supported codecs depend on the OS/device; H.264/AAC MP4 is covered by the test suite.

Only one preview per controller is supported. After `openMedia`, positions are **source-video milliseconds**, independent of timeline edits. After `prepareTimeline`, positions are **edited-project milliseconds**, including gaps and speed changes. Seeking outside `[0, duration]` fails. Native playback owns A/V timing; Flutter does not advance the clock. Backgrounding pauses and never auto-resumes. Android handles audio focus/noisy routes; iOS pauses for interruptions/headphone removal but intentionally leaves the host's `AVAudioSession` category/mixing/silent-switch policy unchanged.

From `example/`, run `flutter run --route=/playback -d <device-id>`, or tap **Play sample video** on the home screen. Synthetic media is example-only; the SDK bundles no media or codec binary.

## Timeline data and saving

Use `EditorController.execute(command)` for edits, then `undo()` and `redo()`. `controller.project` and `controller.state.project` expose the same immutable current snapshot. Media and overlay definitions are reusable; `TimelineClip` places them on typed tracks with integer microsecond ranges, rational playback/frame rates, transforms and adjustments. Use `TimelineClip.still` for images/text/stickers and `SetStillDuration` to change their display duration.

`EditorProjectFile(path).save(controller.project)` writes a versioned document. Load with `EditorProjectFile(path).load()` and supply the returned project to a new controller. Use one file owner per path for ordered saves; provide an existing app-owned directory. Save errors propagate to the caller. Source paths remain references; media files and undo history are not embedded. Schema v1 documents migrate to v2 when loaded; a subsequent save writes v2. Unknown future schemas fail explicitly.

See the executable [timeline example](example/lib/timeline_example.dart) and [Phase 1 verification](docs/PHASE_1_VERIFICATION.md) for exact data semantics. Preview supports only the rendered subset described below; data-only commands do not imply support for rendering effects or overlays.

## Timeline UI and native composition

`VnEditor` includes the timeline and inherits the host `ThemeData`. To embed it separately, place `EditorTimeline(controller: controller)` in a bounded-height parent, such as `SizedBox(height: 280, child: EditorTimeline(controller: controller))`. The widget does not dispose the host controller.

Select a clip by tapping it or using **Select clip**. Drag a trim handle, or use **Trim selected clip** for frame-step actions at any zoom level. Long-press and drag to move; the move menu also offers frame-step moves and swapping with a neighbor. Trimming changes source bounds while preserving the placement start, matching `EditTimelineClip`; a gesture commits one undo entry. Invalid overlaps/transitions are rejected without changing the project. Zoom and selection are transient UI state, not persisted project data.

The ruler uses project time. Tap or drag it to scrub; a drag updates the cursor immediately and dispatches one native seek on release. In **Timeline** mode it seeks across cuts and gaps without requiring selection. In **Source** mode it maps only the selected placement of the already-open source, without seeking unrelated media.

```dart
// project contains one populated video track referencing readable local files.
await controller.initialize();
await controller.prepareTimeline(); // paused, native composition ready
await controller.play();
await controller.seek(const Duration(milliseconds: 2500)); // project time
// Edits/undo pause and invalidate the plan; play/seek rebuild it as needed.
```

The toolbar's **Preview timeline** action uses the same API. Android uses Media3 CompositionPlayer; iOS uses AVFoundation composition. Both support sequential cuts, black/silent gaps, source trims, constant 0.25–4× speed, clip volume and validated GPU effect chains. Preview is limited to one populated video track, 256 clips and 24 hours, with clips at least 1 ms long. Transforms, two-frame transitions, layered visuals and separate audio mixing fail explicitly rather than being silently omitted. Renderer v1 targets encoded SDR RGB; HDR/wide-gamut parity is not certified.

Visible clips request six representative native JPEG thumbnails (up to 160×90) and 128 real PCM waveform peaks for the source range. These are not frame-accurate or zoom-adaptive thumbnail tiles. Silent sources have no fabricated waveform. Two concurrent extraction jobs, a bounded pending queue, 16-result session LRU caches, cancellation, retry and disposal cleanup keep the preview work bounded. Only file paths and small peak arrays cross Pigeon; decoded video frames stay native. Phase 3 added no runtime dependency; Phase 4's native Media3 additions are documented in the dependency inventory.

## GPU adjustments

Select a video clip and open **Clip effects**. Choose an effect or LUT, adjust intensity/parameters, and release a slider to commit one undoable edit. Controls inherit the host theme; the preview is not darkened by the adjustment sheet. The panel edits one adjustment; hosts can build stack controls using the public registry and project commands.

```dart
await controller.editEffect('clip-id',
  EditorEffectRegistry.definition('color').create(
    instanceId: 'editor-adjustment',
    parameters: {'exposure': .5, 'saturation': 1.2},
  ),
);
```

The native plan and shader definitions are shared with the minimal verification exporter. It accepts a new app-owned output path, current even render dimensions up to 1080p, the default 30 fps setting, and at most 60 seconds. Android retains source cadence below 30 fps; iOS composes at 30 fps. See [EFFECTS.md](docs/EFFECTS.md) before using it; it is not a background or production export job service.

## Regenerate platform bindings

After changing `pigeons/vn_editor_api.dart`:

```sh
dart run pigeon --input pigeons/vn_editor_api.dart
dart format lib/src/platform/vn_editor_api.g.dart
```

Commit the generated Dart, Kotlin, and Swift files together with the schema change.

## Verification

```sh
flutter analyze
flutter test

cd example
flutter analyze
flutter test
```

From `example/`, run `flutter test integration_test/plugin_integration_test.dart -d <device-id>` on Android and iOS. Native checks: `cd example/android && ./gradlew :vn_editor:testDebugUnitTest`; for Swift, first build `flutter build ios --simulator -t lib/main.dart` from `example/`, then run `xcodebuild -workspace Runner.xcworkspace -scheme Runner -destination 'id=<simulator-id>' -only-testing:RunnerTests test` from `example/ios/`.

Playback: `flutter test integration_test/playback_integration_test.dart -d <device-id> --no-uninstall`. Add `--dart-define=VN_SOAK_SECONDS=60` for the optional sustained-playback probe. See [Phase 2 verification](docs/PHASE_2_VERIFICATION.md) before interpreting debug runs as performance evidence.

Thumbnails, waveforms and composition: `flutter test integration_test/timeline_media_integration_test.dart -d <device-id> --no-uninstall`. Android profile probe: `flutter drive --profile --no-dds --driver=test_driver/integration_test.dart --target=integration_test/timeline_performance_test.dart -d <android-device-id>`. See [Phase 3 evidence](docs/PHASE_3_VERIFICATION.md) for measured results and remaining hardware gates.

See [Phase 0 verification](docs/PHASE_0_VERIFICATION.md) and [Phase 1 verification](docs/PHASE_1_VERIFICATION.md) for tested coverage and limitations. The latter includes the two-launch persistence test commands; use `--no-uninstall` to preserve app data between runs.

## Licensing

Package source, authored synthetic fixtures and generated LUTs are MIT licensed. Android Media3 is Apache-2.0; iOS uses system frameworks. No FFmpeg binaries, codec bundles, fonts or stickers are bundled. See [the dependency inventory](docs/DEPENDENCIES.md) for native dependencies, size caveats, and redistribution obligations.
