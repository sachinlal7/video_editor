## Unreleased

### Phase 4 implementation (hardware qualification pending)

- Added a generated 13-stage GPU registry and shared shader semantics for Media3/OpenGL ES and AVFoundation/Metal; four package-authored 17³ LUTs, bounded blur/glow and time-based effects.
- Added persistent clip adjustments, native capability discovery, ordered stage updates, controller-owned rebuild/undo and host-themed adjustment controls.
- Added bounded foreground filtered MP4 proof export with cancellation and no-overwrite behavior. Full export jobs, progress, settings and UI remain Phase 8.
- Added native validation, actual-frame/renderer pixel checks, all-stage preview/export comparisons, negative export tests and light/dark UI verification.
- Fixed Android float-array uniform binding, paused effect refresh, composition replay, gap sizing and source/project preview aspect; fixed iOS Metal frame orientation and SDR conversion.
- No new Dart runtime dependencies or bundled codecs. Physical iPhone qualification and final Android hardware reconfirmation remain pending.

### Phase 3 implementation (hardware qualification pending)

- Added public `EditorTimeline` with ruler, bounded zoom, scrolling, clip selection, source-trim gestures, frame-step trim menu, and undo/redo.
- Added selected-open-source playhead projection and timeline seek mapping, with stale gesture/seek protection and isolated playhead repainting.
- Editor surfaces now follow the host's Material light/dark theme. Added large-text layout and real-device timeline interaction tests.
- Added native JPEG thumbnail extraction and real PCM waveform peaks, bounded worker queues/session LRU caches, cancellation, retry and cleanup. No new runtime dependencies.
- Added native cut-composition preview with trims, gaps, constant speed, volume and source switching; edited-project clock/seek, coalesced preparation, edit invalidation and stale-request protection.
- Added long-press moves, frame-step move/reorder actions and ruler scrubbing; one undo entry per gesture.
- Fixed iOS simulator composition pixel-format negotiation and selected media-strip foregrounds for custom host themes. Batched waveform drawing and isolated media-strip repainting.
- Added negative/lifecycle/media integration coverage and an Android 200-clip profile probe. Physical-iOS and broader release qualification remain required under the approved sequencing exception.

### Phase 2 implementation (physical iOS verification pending)

- Added Android Media3 and iOS AVPlayer single-source playback with native preview surfaces and source-time events.
- Added display-oriented metadata, play/pause/seek/end/replay, buffering, structured failures, cancellable opens, session isolation and lifecycle cleanup.
- Added public `EditorPreview`, playback state, accessible playback controls, and a real-media example.
- Added real-media integration tests on Android hardware/emulator and iOS simulator, including malformed input, replacement/disposal races and repeated ownership cycles.
- Kept decoding native: no frame buffers cross Pigeon, no additional Dart runtime dependencies or bundled codecs.
- Follow-up: native Android activity-pause safeguard and Swift main-actor isolation.

### Phase 1 complete

- Added immutable video/audio/image/text/sticker tracks, reusable source placements, integer time, rational speeds and rational frame snapping.
- Added trim, split, cross-track move, volume, speed, overlay content/transform/duration, filter/effect, source-removal and transition commands with atomic transactions.
- Added controller-owned bounded undo/redo and observable current project snapshots.
- Added schema-v2 serialization, explicit v1 migration and ordered, atomic file replacement with bounded loading.
- Added a full public-API save/reopen example and Android/iOS integration plus separate-process restart coverage.
- Tightened project validation for duplicate IDs, references and conflicting metadata. Phase 0 constructor signatures remain available; invalid projects now fail early.

## 0.1.0

- Added the Android/iOS Flutter plugin foundation.
- Added the initial editor, project, media, effect, and export API surface (0.x, provisional).
- Added lifecycle-safe controller ownership and input validation.
- Added generated Pigeon Dart, Kotlin, and Swift bridge contracts.
- Added the host integration example and positive/negative test coverage.
