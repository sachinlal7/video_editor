# Phase 0 verification

Verified locally on 2026-10-14 with Flutter 3.47.7 / Dart 3.13.5.

## Completion checklist

- [x] Android/iOS plugin and separate host example using a path dependency.
- [x] Public editor, controller, project, clip/overlay, effect, and export contracts.
- [x] BLoC/Cubit state owner, pure-Dart domain models/port, Pigeon transport adapter.
- [x] Kotlin and Swift lifecycle handlers; explicit errors for future-phase commands.
- [x] Generated typed command, metadata, playback, error, and export contracts.
- [x] Declared platform/toolchain requirements and dependency/asset inventory.
- [x] Original roadmap preserved; project rules updated for native-first, lightweight design and testing.

## Executed checks

| Check | Result |
| --- | --- |
| Dart formatting | Pass |
| Package `flutter analyze` | No issues |
| Package `flutter test` | 28 passed |
| Example `flutter analyze` | No issues |
| Example `flutter test` | 1 passed |
| Android debug APK build | Pass |
| iOS simulator build, normal `lib/main.dart` target | Pass |
| Kotlin native unit tests | 2 passed |
| Swift RunnerTests | 2 passed |
| Android API 36 emulator integration | 2 passed |
| iPhone 18 Pro / iOS 27 simulator integration | 2 passed |

Unit coverage includes invalid project/effect/export parameters, defensive immutable collections, finite-number checks, initialization deduplication, synchronous/asynchronous initialization failure and retry, initialization-versus-close races, idempotent disposal, disposal failures, commands before initialization/after close, blank identifiers, invalid seek, native error propagation, missing plugin, competing controller ownership, generated codec round trips, disabled export, widget retry, and externally owned controller preservation.

Integration coverage initializes the actual native plugin, checks unavailable playback and invalid seek, closes/reopens it, and opens the editor shell through the host example. Native unit tests independently verify lifecycle and non-finite frame-rate rejection on each platform.

## Limits and follow-up gates

- Physical Android device was detected (Android 13). Installation was rejected with `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`; no security settings were bypassed. Physical-device validation is not claimed.
- No physical iOS device was tested. Declared Android 24 / iOS 15 minima were not runtime-tested; the simulator/emulator coverage above is the actual tested matrix.
- iOS integration uses Swift Package Manager. CocoaPods packaging is supplied but was not separately linted or built.
- Swift tests passed with Xcode XCTest deployment-target warnings; Android builds emitted Flutter-toolchain Kotlin/Gradle warnings. These did not fail builds or tests.
- Playback, timing events, timelines, effects, overlays, persistence, and export are future phases. This is not media correctness, performance, release-size, or release-publication certification.
- Real-device decoding, codecs, A/V sync, memory, battery/thermal behavior, permissions, inaccessible/corrupt media, storage failures, and export cancellation require dedicated tests as those features are implemented.

The controller does not invent playback positions from command acknowledgements. Generated event contracts and `onExportComplete` remain reserved until their native features exist. The example disables export and states the current scope explicitly.
