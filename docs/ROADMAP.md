# VN Editor SDK roadmap

This repository implements a reusable Flutter video-editing SDK with a VN-like editing capability set. It does not copy VN's proprietary source, assets, or effects.

## Architecture boundary

Flutter owns the public SDK, editor UI, timeline interaction, project state, serialization, and orchestration. Android and iOS own decoded media, time-critical playback, frame compositing, device resources, and export. Pigeon carries typed commands and coarse events only; video frames stay native.

Optional FFmpeg support may be evaluated for suitable offline conversion or audio/video processing. It must not become the per-interaction preview engine, and its distribution and codec licenses must be reviewed before adoption.

## Phase checklist

- [x] Phase 0: SDK foundation
- [x] Phase 1: Project and timeline engine
- [ ] Phase 2: Native video playback
- [ ] Phase 3: Timeline UI
- [ ] Phase 4: GPU effects and filters
- [ ] Phase 5: Stickers and text
- [ ] Phase 6: Audio editor
- [ ] Phase 7: Transitions and advanced editing
- [ ] Phase 8: Export engine
- [ ] Phase 9: Production optimization
- [ ] Phase 10: Package release

Progress: **2 of 11 phases fully signed off**. Phases 2–4 are implemented and have the recorded functional verification, with hardware/release qualification pending. Phases 5–10 (six phases) are not started. An unchecked phase is not an assertion that no code exists.

## Phase 0: SDK foundation

Goal: any Flutter application can depend on this package and open the editor without copying implementation code.

### 0.1 Package structure

- One Flutter plugin package named `vn_editor`, supporting Android and iOS.
- A separate `example/` application consumes the package through a path dependency.
- Dart internals are grouped by API, controller, models, timeline, preview, effects, stickers, audio, export, persistence, and platform bridge.
- Kotlin and Swift native code have explicit playback, renderer, and export boundaries.
- Shader and licensed asset directories exist without bundling placeholder binaries.

### 0.2 Public API

The initial, provisional 0.x entry library exposes `VnEditor`, `EditorController`, `EditorProject`, clip and overlay models, effect models, and export settings/results. Native implementation classes and generated bridge types remain private.

### 0.3 Platform bridge

Pigeon generates typed Dart, Kotlin, and Swift bindings for lifecycle, media, playback, effect, and export commands plus playback, export-progress, and error events. Media metadata is a typed command result. Event contracts are generated; their runtime delivery starts with the implementing feature phase. No decoded frame or large image buffer crosses this bridge.

### 0.4 Constraints and licensing

- Tested baseline: Flutter 3.47.7 and Dart 3.13.5.
- Declared Dart constraint: `>=3.13.5 <4.0.0`.
- Declared Flutter constraint: `>=3.47.7`.
- Android: API 24+, Kotlin, Java 17 toolchain.
- iOS: iOS 15+, Swift 5 language mode (Swift Package Manager tools 5.9+).
- Package source: MIT licensed.
- No FFmpeg binaries, codecs, fonts, stickers, LUTs, or third-party media assets are bundled in Phase 0.
- Every future binary or asset requires a recorded source, redistribution terms, and attribution before inclusion.

### Completion evidence

- Package and example project generated for Android and iOS.
- Public API and lifecycle-safe controller implemented.
- Pigeon bindings generated and registered on Kotlin and Swift.
- Example app opens the editor package.
- Positive and negative API, widget, controller, and bridge tests pass.
- `flutter analyze` and `flutter test` pass for the package and example.

Detailed test evidence and known limitations: [PHASE_0_VERIFICATION.md](PHASE_0_VERIFICATION.md). Dependency decisions: [DEPENDENCIES.md](DEPENDENCIES.md). The full original brief is retained in [ROADMAP_SOURCE.txt](ROADMAP_SOURCE.txt).

Phase 0 delivered initialization/disposal and the editor shell. Phase 1 delivers the data-only editing engine below. Phase 2 implements native single-source playback and event-driven media state. Phase 4 adds native GPU effects and a bounded verification exporter. This is not a production-ready video editor or a package publication.

## Phase 1 and later

### Phase 1: project and timeline engine

Implement immutable project data, tracks, integer/rational time, trim, split, move, speed, volume, overlays, command-based undo/redo, versioned persistence, and migrations.

Completed: immutable video/audio/image/text/sticker tracks; exact source/timeline mapping and rational frame timing; trim/split/move/speed/volume/overlay/transform/filter/effect commands; safe source removal; transition data; atomic transactions and bounded undo/redo; schema-v2 persistence with v1 migration. The example exercises edit → undo/redo → save → close → reopen on both platforms, including separate-process restart checks. See [PHASE_1_VERIFICATION.md](PHASE_1_VERIFICATION.md) for evidence, semantics and limits.

### Phase 2: native video playback

Implement reliable single-clip playback, metadata, buffering, seeking, timestamps, audio sync, lifecycle cleanup, and native-time-as-source-of-truth on Android and iOS.

Implementation delivered: Media3/AVPlayer backends, native preview surfaces, metadata including display rotation, native source positions/buffering, play/pause/seek/end/replay, cancellation, decoder errors, app background handling, ownership and cleanup. The example plays bundled synthetic media using only the public API.

**Verification gate remains open:** Android physical-device and emulator playback plus iOS simulator playback are tested. The user has no physical iPhone; physical iOS media/memory/thermal/codec and measured A/V-sync checks remain required. On 2026-10-14 the user explicitly approved proceeding with Phase 3 while these checks remain pending. This is a sequencing exception, not Phase 2 sign-off or a production-release waiver. See [PHASE_2_VERIFICATION.md](PHASE_2_VERIFICATION.md).

### Phase 3: timeline UI

Implement the ruler, playhead, zoom, scroll, clip blocks, trim gestures, thumbnails, waveforms, selection, and playback synchronization without rebuilding project state every frame.

**Implementation delivered (2026-10-15); hardware qualification remains open:** public `EditorTimeline`, host light/dark theming, ruler and native-clock playhead, zoom/scroll/culling, clip selection, trim/move/reorder with frame-step alternatives, undo/redo, native JPEG thumbnails and PCM waveforms with bounded queues/caches/cancellation, and cut-only composition playback. Media3 and AVFoundation render trims, gaps, constant speed and volume on one video track; later-phase layers/effects/transitions/audio mixing are explicitly unsupported. No new runtime dependency.

Package/example tests, Android hardware and iOS simulator integration, native unit tests and an Android 200-clip profile probe are recorded in [PHASE_3_VERIFICATION.md](PHASE_3_VERIFICATION.md). Physical iPhone media/performance tests, broader codec/thermal/A/V-sync qualification and real screen-reader checks remain open. The checklist remains unchecked rather than implying release certification; the user-approved exception permits Phase 4 but does not waive those gates.

### Phase 4: GPU effects and filters

Implement a data-driven effect registry and matching preview/export semantics for color controls, LUTs, vignette, grain, blur, glow, glitch, light leaks, distortion and procedural animation.

Implemented: generated 13-stage registry/shared math, Android Media3/OpenGL ES and iOS AVFoundation/Metal rendering, four authored 17³ LUT grades, ordered chains/intensity, persistent adjustments and undo, host-themed clip controls, and minimal foreground proof export. See [EFFECTS.md](EFFECTS.md) for exact supported semantics and limits, and [PHASE_4_VERIFICATION.md](PHASE_4_VERIFICATION.md) for evidence and remaining checks.

Explicit user decisions: minimal filtered export is authorized now to verify matching results; the full export job engine stays in Phase 8. Two-clip transitions stay in Phase 7 despite the original Step 4 demo suggestion. Physical iPhone tests remain pending. When the Android phone became unavailable during final verification, the user approved finishing emulator/simulator checks and reconnecting it later; earlier Android hardware evidence must not be represented as validation of later fixes.

Hardware qualification, long-session memory/thermal/codec tests, broad device coverage and release-size measurements remain open; the phase checklist stays unchecked until those gates are satisfied. No Phase 5 implementation is started by this work.

### Phase 5: stickers and text

Implement typed overlays, licensed asset libraries, gestures, typography, timing, keyframes, easing, and matching export composition.

### Phase 6: audio editor

Implement music and voiceover tracks, trim, move, volume, mute, fades, waveform caching, extraction, mixing, sample-rate conversion, channel handling, and A/V synchronization.

### Phase 7: transitions and advanced editing

Implement two-frame transitions, transforms, speed ramps, picture-in-picture, chroma key, blur backgrounds, reverse playback, freeze frames, keyframes, and templates.

### Phase 8: export engine

Implement validated settings, native rendering and encoding, audio mixing, progress, cancellation, background behavior, error recovery, and preview/export parity.

### Phase 9: production optimization

Profile memory, startup, rendering, cache eviction, thermal behavior, long projects, variable-frame-rate sources, device compatibility, recovery, accessibility, and automated tests.

### Phase 10: package release

Finalize API docs, guides, example projects, changelog, semantic versioning, CI, license inventory, publication checks, and release artifacts.

