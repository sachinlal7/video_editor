# VN Editor project rules

## Product direction

- Build and maintain `vn_editor` as a reusable Flutter package for Android and iOS, not as a one-off application.
- Follow [docs/ROADMAP.md](docs/ROADMAP.md) in phase order. Do not begin a later phase until the current phase has its documented completion evidence, except for an explicit user-approved sequencing exception recorded there. The user approved starting Phase 3 with Phase 2 physical-iOS/hardware sign-off pending; those checks remain release blockers.
- Keep the host-app API small and stable. Native Kotlin and Swift implementation details must remain private.
- Flutter owns editor UI, gestures, project state, undo/redo, persistence, and the public SDK API.
- Kotlin owns Android playback, metadata, frame processing, device resources, and export. Prefer Media3 and platform codecs where they fit.
- Swift owns iOS playback, composition, frame processing, device resources, and export. Prefer AVFoundation and Metal where they fit.
- Use Pigeon-generated APIs for low-frequency typed commands and events. Never move decoded video frames or large image buffers through Flutter platform channels per frame.
- Keep the package lightweight. Add a dependency only when its value, maintenance status, license, binary size, and platform impact are understood and documented.
- Do not make FFmpeg the interactive preview engine. If FFmpeg is introduced later, keep it optional and limited to jobs that suit its licensing and process model.

## Architecture and quality

- Maintain one owner for every workflow and side effect. UI delegates to controllers; controllers delegate to platform or domain services.
- Use BLoC/Cubit for editor state and clean dependency boundaries: presentation → controller → domain port ← native adapter. Keep domain models independent of Flutter and native transport. The example consumes the public package API; host applications need not adopt BLoC.
- Keep Phase 0 minimal: no redundant repository/use-case wrappers, media dependencies, or bundled codecs before their implementing phase.
- Keep source-media time distinct from edited timeline time. Use integer or rational time units for frame-sensitive work.
- Make all native resources lifecycle-safe and idempotently releasable.
- Keep preview and export effect definitions and parameter semantics aligned.
- Preserve public API compatibility unless a breaking change is explicitly planned and documented.
- Update tests, the example app, and the roadmap evidence with every completed phase.
- Validate changes with `dart format`, `flutter analyze`, `flutter test`, and the example app from its own directory. Run native unit/build checks when native code changes.
- Test negative paths, initialization/close races, retry, duplicate requests, ownership, invalid inputs, and unavailable features as well as successful paths. Record actual results, never inferred passes.
- Run integration checks on both Android and iOS. Real-device media, memory, thermal, and codec tests are mandatory when those features arrive; emulators do not establish performance. Respect device installation restrictions and report blocked checks.

## Phase tracking

- The canonical phase checklist and completion criteria live in [docs/ROADMAP.md](docs/ROADMAP.md).
- Preserve the original user brief in [docs/ROADMAP_SOURCE.txt](docs/ROADMAP_SOURCE.txt); the tracked roadmap records intentional implementation decisions and verification evidence.
- Mark a phase complete only after its code, documentation, example integration, and verification evidence are present.
- User-approved sequencing exception: Phase 4 may proceed with Android hardware and iOS simulator evidence while physical-iPhone qualification stays pending. Minimal foreground filtered export is authorized to verify parity; the full export engine remains Phase 8. This does not waive hardware or production-release gates.
- During final Phase 4 verification the Android phone became unavailable; the user explicitly approved continuing with Android emulator/iOS simulator tests and reconnecting the phone later. Record the earlier hardware run separately from the final emulator revision; hardware reconfirmation remains pending.

