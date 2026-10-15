# GPU effects, renderer v1

`vn_editor` remains a reusable Flutter package. Dart owns immutable edits and undo/redo; Media3/OpenGL ES and AVFoundation/Metal own decoded frames. No video frames cross Pigeon. `shaders/catalog.json` and `shaders/effect_body.glsl` generate both native definitions with `dart run tool/generate_effects.dart`; run `dart format lib/src/effects/catalog.g.dart` afterward.

## Catalog

| ID | Parameters (range; default) |
| --- | --- |
| color | brightness -1..1; 0, contrast 0..2; 1, saturation 0..2; 1, temperature/tint -1..1; 0, exposure -2..2 stops; 0 |
| grayscale | none |
| vignette | amount 0..1; .6 |
| grain | amount 0 to 0.3; .08 |
| blur | radius 0..12 output pixels; 4 |
| glow | amount 0..1; .4, radius 0..12 pixels; 4 |
| sharpen | amount 0..2; .5 |
| chromatic | amount 0..12 pixels; 3 |
| distortion | amount -0.5 to 0.5; .15 |
| glitch | amount 0 to 0.2; .04, speed 0..3; 1 |
| lightLeak | amount 0..1; .3, speed 0..3; .5 |
| pulse | amount 0 to 0.3; .1, speed 0..3; 1 |
| lut | integer preset 0..3; 0 (warm, cool, vintage, cinema) |

The four 17³ trilinear LUTs are authored by this package's generator under MIT, not copied creative assets. Each native asset is 78,608 bytes. Blur/glow use a bounded nine-tap kernel, not an unbounded convolution.

Stages run in stored order: filters, then effects, at most eight per clip. Each stage mixes its input with its processed output using intensity 0..1. Parameters are finite and range-checked in Dart and native code; unknown IDs/parameters and fractional LUT IDs fail explicitly. Color math uses encoded SDR RGB, not linear-light HDR grading. UV origin is top-left. Grain, glitch, light leak and pulse are procedural time-based effects; arbitrary keyframes and two-input transitions are not implemented here. Native clock and render presentation times drive animation, never Dart timers. Seek/export comparisons allow compression/decoder rounding, not bit identity.

## Public API

```dart
final supported = await controller.supportedEffects();
final grade = EditorEffectRegistry.definition('lut').create(
  instanceId: 'editor-adjustment', parameters: {'preset': 2}, intensity: .8,
);
await controller.editEffect('clip-id', grade); // one undo entry + native rebuild
controller.undo();
await controller.prepareTimeline();
```

`SetClipEffect`/`SetClipFilter` also support data-only edits; `prepareTimeline`, seek or play rebuilds a dirty timeline. These definitions persist in project JSON. `editEffect` validates the prospective render plan before changing history; competing edits fail. A native decode failure leaves the committed edit available for retry/undo. It keeps a cursor inside the edited clip, or seeks that clip's start when the cursor was elsewhere.

`applyEffect`/`removeEffect` affect only an opened single-source preview and its proof export, not persisted project data. Updating an instance preserves its stage order. Source replacement clears these temporary effects. Timeline effects must use project commands. The built-in panel edits one named adjustment; hosts can build full stack controls using the public model/registry.

## Minimal verification export (not the Phase 8 job engine)

After opening media or preparing a timeline, call `controller.export(EditorExportSettings(outputPath: newAbsolutePath, width: currentMedia.width, height: currentMedia.height))`. The result is the completed local path. `cancelExport(outputPath)` cancels that active job; wrong job paths fail. Existing files are never overwritten.

- Foreground only; up to 60 seconds, even current-render dimensions up to 1920 per side and 1080p pixel area, SDR H.264/AAC MP4. The accepted frame-rate setting is 30: Android uses a 30 fps ceiling and retains lower source rates; iOS composes at 30 fps. Exact configurable cadence belongs to Phase 8.
- Native encoder quality is used. The existing default `videoBitrate: 12000000` is reserved, **not a promised output bitrate**; nondefault bitrate/rate settings are rejected. Configurable encoder settings, progress, background jobs, broader codecs and the editor Export button remain Phase 8.
- One export at a time, two-minute deadline, cancellation/disposal cleanup. Android reserves the final path exclusively and copies on a worker because emulated storage disallows hard links. Do not consume the file before the future completes; this is not a crash-recoverable job store.
- Preview and export share the native render plan, effect definitions and shader math. iOS uses the same custom compositor, Android the same Media3 composition with Transformer.

The internal frame-capture bridge is test instrumentation: one PNG file path per requested capture, never per-frame channel traffic. Tests delete these cache files. Android captures the actual SurfaceView; iOS uses AVAssetImageGenerator with the player's videoComposition, so its pixel assertions verify the renderer, not AVPlayerLayer screen presentation. Screen captures separately verify presentation.

## Gates still open

Physical iPhone GPU/codec/memory/thermal/A/V-sync tests remain pending by explicit user agreement. The final Android hardware reconfirmation also remains pending after the phone disconnected; the user approved finishing on the emulator. Simulator/emulator passes do not certify hardware performance. HDR, wide-gamut parity, cross-device bit identity, long-session thermal behavior, all supported OS versions and release binary-size qualification are not established. Two-frame transitions and arbitrary keyframes remain Phase 7; overlays remain Phase 5.

API references: [Media3 effects](https://developer.android.com/media/media3/transformer/transformations), [CompositionPlayer](https://developer.android.com/reference/androidx/media3/transformer/CompositionPlayer), [Media3 output frame-rate ceiling](https://developer.android.com/reference/androidx/media3/transformer/EditedMediaItem.Builder#setFrameRate(int)), [AVVideoCompositing](https://developer.apple.com/documentation/avfoundation/avvideocompositing).
