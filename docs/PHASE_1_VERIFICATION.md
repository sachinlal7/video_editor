# Phase 1 — project and timeline engine

Implementation and verification record, 2026-10-14.

Status: **complete for the Phase 1 data-engine scope**. Playback, timeline UI and rendered media remain in later phases.

## Executed results

| Check | Result |
| --- | --- |
| Formatting and package analysis | Pass; no analyzer issues |
| Package unit/widget/regression tests | 69 passed |
| Example analysis and tests | No issues; 2 passed |
| Android API 36 emulator integration | 3 passed; APK build succeeded |
| iPhone 16 / iOS 26.5 simulator integration | 3 passed; iOS build succeeded |
| Android separate-process save/relaunch | Write and read launches both passed |
| iOS separate-process save/relaunch | Write and read launches both passed |

Coverage includes invalid ranges/rates/transforms/parameters, wrong/missing references, duplicate IDs, collisions, dangling transitions, source-removal guards, failed transaction rollback, bounded history, mixed-edit round trips and undo/redo, v1 migration, unsupported/corrupt schemas, missing directories, failed atomic replacement, oversized documents, and queue recovery. Initial restart attempts failed because the test runner uninstalled the app; the corrected durable-directory tests use `--no-uninstall` and pass.

## Scope delivered

- Immutable project/source data and ordered video, audio, image, text, and sticker tracks.
- Integer-microsecond source/timeline ranges, rational playback speeds and rational frame rates. Frame lookup/snapping is calculated independently from the origin, not by accumulating rounded frame durations.
- Clip/track addition and removal, source trim, split, within/across-track moves, speed, volume, overlay content, position, scale, rotation, opacity, and static display duration.
- Per-placement filters/effects with immutable parameters, upsert/removal commands, and validated transition definitions at adjacent cuts. These are data only; no rendering is claimed.
- Explicit source-reference removal: refuse in-use sources by default, or remove their placements and dependent transitions when explicitly requested. No command deletes source media files.
- One Cubit state owner, immutable project snapshots, atomic command transactions, and bounded 100-step undo/redo. All successful edits are undoable; failed commands do not change project/history. Undo history is session-local and is not persisted.
- Schema-v2 JSON and explicit migration from the first increment's v1 schema. New fields include images, transforms, adjustments, transitions and rational timebase. Migration preserves existing references, source ranges, rates, volume, and text; it does not rewrite files until an explicit save.
- Asynchronous atomic project-file replacement, serialized operations per file owner, 16 MiB document limit and off-isolate JSON work. No additional dependency was introduced.
- The public-API example edits, undoes/redoes, saves, closes and reopens a project with media references, images, text, stickers, transforms and adjustments.

## Defined semantics

- Intervals are half-open `[start, end)`. Trim arguments are source time; move arguments are timeline time. Speed changes retain the source range/start and do not ripple other clips.
- Clips on one track cannot overlap; layers use separate tracks. Cross-track moves require matching kinds. Track order defines layer order for future rendering.
- Static placements use a virtual source interval. `SetStillDuration` resizes their display interval without claiming a decoded media duration. Speed/audio-volume changes on static media and visual adjustments on audio tracks are rejected.
- `EditorTransform` uses normalized canvas center coordinates, positive source-relative scales, radians and opacity in `[0,1]`. Off-canvas coordinates are allowed; every value must be finite.
- `EditorFrameRate(30000, 1001)` expresses NTSC exactly. The legacy `frameRate: 29.97` means exactly that decimal rate, not an inferred NTSC rate. When supplying both `frameRate` and `timebase`, they must agree. Time/frame indices and rational components are bounded to exactly representable JSON integers; frame rates above microsecond resolution are rejected.
- Frame boundaries round to the nearest microsecond, ties forward. Source mapping rounds down and resulting clip durations round up once. Splits must map to an exact source microsecond; incompatible speed/frame combinations are rejected instead of silently shifting ranges.
- Filter/effect IDs are unique per placement; replacing one retains its order. Use `execute(SetClipFilter(...))` / `execute(SetClipEffect(...))` for project edits. The older native `applyEffect()` entry point remains unavailable until native effects arrive.
- A transition is centered on an adjacent cut: floor(duration/2) before, remainder after. Duration must fit both clips. Edits that would leave dangling or invalid transitions fail; remove the transition first in an atomic transaction. Native compositing is Phase 7/8 work.
- Source paths are preserved, including relative paths; loading a project does not open or validate the referenced media. Native metadata/decoder validation belongs to Phase 2. Temporal placements sharing a source must agree on its caller-declared duration.

## Verification commands

From the package: `flutter analyze`, `flutter test`, and `dart format --output=none --set-exit-if-changed lib test example/lib example/test example/integration_test`.

From `example/`: `flutter analyze`, `flutter test`, and `flutter test integration_test/plugin_integration_test.dart -d <device>`.

The process-restart test is run in two separate Flutter test invocations on the same device, with a fresh matching run ID:

```sh
flutter test integration_test/project_restart_test.dart -d <device> --no-uninstall --dart-define=VN_TEST_PHASE=write --dart-define=VN_TEST_RUN=<unique-id>
flutter test integration_test/project_restart_test.dart -d <device> --no-uninstall --dart-define=VN_TEST_PHASE=read --dart-define=VN_TEST_RUN=<same-unique-id>
```

The second launch reads the first launch's document, verifies its content, initializes the native plugin, performs an edit/undo, and removes only that test document. The test uses the app-owned documents/files directory. `--no-uninstall` is essential: the Flutter integration runner otherwise uninstalls the app and deletes its data between invocations. Initial restart attempts exposed that test-harness behavior; the corrected test preserves the installation. Hosts should obtain their durable document directory through their platform directory provider.

## Known limits

- Physical devices, forced termination/power-loss recovery, minimum-OS runtimes and media performance are not claimed by these data-engine checks.
- One file owner per document path is required for ordered saves. Cross-process writers, autosave, orphan-temp cleanup after a crash, and OS eviction of temporary directories are not implemented. Atomic replacement is not a guarantee against all storage/power failures.
- No native playback, decoded media validation, timeline controls, rendered effects/transitions, keyframe animation, or export is introduced. These remain in their designated roadmap phases.
- Native Kotlin/Swift implementation files were unchanged; their standalone unit suites were not rerun. The actual bridge/lifecycle is exercised by the platform integration suites.
