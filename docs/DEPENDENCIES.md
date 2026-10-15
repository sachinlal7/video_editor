# Dependency and asset inventory

Reviewed against locally resolved package manifests and license files on 2026-10-14.

| Component | Role | License / distribution |
| --- | --- | --- |
| Package-authored source | Public SDK, native adapters, example | MIT; repository LICENSE |
| Flutter SDK 3.47.7 | UI and platform embedding | BSD-3-Clause; preserve SDK and bundled third-party notices |
| bloc 9.2.1 | Cubit state ownership | MIT; sole additional direct Dart runtime dependency |
| Pigeon 29.0.8 | Development-only bridge generator | BSD-3-Clause; generated headers retained, generator version pinned |
| flutter_test, integration_test, flutter_lints | Development-only verification | Flutter/Dart tooling; not package runtime dependencies |
| Kotlin test / Android build tools | Native build and test only | Toolchain dependencies, not a bundled media SDK |

No Media3, FFmpeg, custom codec binaries, network SDK, analytics, image library, or external font/asset bundle is added in Phase 0. The asset and shader folders contain documentation only. Native playback/render/export dependencies will be selected and reviewed in their own phases.

Flutter's license registry supplies installed runtime package notices to host applications; hosts should expose those notices in their normal license screen. Before release, audit the exact resolved transitive dependency and native binary inventory again. This foundation inventory is not a certification of future codec or asset redistribution rights.

## Weight policy

Phase 1 adds no third-party dependencies: timing, immutable data, JSON, asynchronous file I/O, and worker isolates use Dart's standard libraries. The existing Cubit remains the sole editor state owner. Test-only directory lookup does not add a directory-provider plugin to the SDK.

- Keep media frames, GPU textures, decoding, and encoding native.
- Only typed commands, metadata, and coarse events cross the bridge.
- Use the existing Cubit and a domain port; no extra state, DI, or repository framework.
- Pigeon-generated channels use callback-based asynchronous operations without adding a Kotlin coroutine dependency.
- No APK/IPA size or frame-rate target is claimed from debug builds. Measure release-size delta and real-device media performance when a media backend exists.

## Phase 2 native playback decision

- Android adds only `androidx.media3:media3-exoplayer:1.11.1`, Apache-2.0, maintained by AndroidX. Version checked against the [official release notes](https://developer.android.com/jetpack/androidx/releases/media3). Its resolved Media3 modules are common, container, datasource, decoder, extractor and database. No Media3 UI, streaming extensions, transformer, software-codec extension, or FFmpeg dependency is added.
- The seven downloaded Media3 AAR archives total 3,434,381 bytes. This is a dependency-download measurement, **not** an APK delta: transitive support libraries, dexing, shrinking and compression affect the host artifact. Release APK/IPA size and performance certification remain pending.
- The resolved Maven POM identifies Apache-2.0. Hosts distributing Android builds must preserve applicable AndroidX/transitive license and notice obligations; Flutter's Dart license registry alone does not inventory native Maven dependencies. Re-audit the release dependency graph and include native notices before publication.
- iOS uses system AVFoundation, AVPlayerLayer and UIKit; no third-party iOS media framework is shipped. The host retains its audio-session policy.
- Flutter uses existing platform-view APIs. Android hybrid composition was selected after a device screenshot exposed a missing initial paused frame with texture-composed AndroidView; iOS uses a native AVPlayerLayer. Measure composition cost on supported low-end devices before release.
- Pigeon event methods also use callback generation, avoiding a coroutine dependency. Media state is sampled around 5 Hz while playing (plus state changes); Android polling stops when paused/ended. No pixel buffers cross the bridge.
- The example includes approximately 3.5 MiB of synthetic fixtures, including a ten-minute, low-resolution test file. They are declared only in the example's pubspec, never as SDK assets. See [fixture provenance](PHASE_2_FIXTURES.md). FFmpeg was a developer workstation fixture-generation tool only, not an app dependency.

## Phase 3 native timeline decision

No new Dart, Android or iOS runtime dependency. Android reuses Media3 for clipped composition playback and platform MediaMetadataRetriever/MediaExtractor/MediaCodec for JPEG thumbnails and PCM peaks. iOS uses AVFoundation composition, AVAssetImageGenerator and AVAssetReader with system JPEG encoding. Flutter draws only the UI, representative JPEG files and small waveform peak arrays; no continuous frame transport is added. The Android profile result in [Phase 3 verification](PHASE_3_VERIFICATION.md) is not an APK/IPA size or codec-performance certification.

## Phase 4 GPU and proof-export decision

Android adds Media3 `effect` and `transformer` 1.11.1, Apache-2.0, matching ExoPlayer. Transformer supplies the shared CompositionPlayer/encoder pipeline; effect supplies native OpenGL processing. Resolved new Media3 AARs: effect 402,882 bytes, transformer 506,251, muxer 109,910 (1,019,043 bytes total). This is archive download size, not a release APK delta. Transitives include Kotlin coroutines/Guava adapters; callback Pigeon bindings themselves still do not require coroutine APIs. Inventory native notices again before release. CompositionPlayer is experimental and pinned; regression tests cover replay, gaps and source switching.

iOS adds only system Metal/CoreImage alongside AVFoundation, no external framework. The authored LUT atlas adds 78,608 bytes per native target; shaders and math are repository-authored MIT assets. There is no added Dart runtime dependency, FFmpeg runtime or bundled codec. Actual release-size and low-end GPU/thermal qualification remain pending.
