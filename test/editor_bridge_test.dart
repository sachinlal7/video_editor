import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_editor/src/platform/editor_platform.dart';
import 'package:vn_editor/src/platform/vn_editor_api.g.dart';
import 'package:vn_editor/vn_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final project = EditorProject.empty(width: 1080, height: 1920, frameRate: 30);
  final channels = <BasicMessageChannel<Object?>>[];

  void handle(String method, Future<Object?> Function(Object?) handler) {
    final channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.vn_editor.VnEditorHostApi.$method',
      VnEditorHostApi.pigeonChannelCodec,
    );
    channels.add(channel);
    messenger.setMockDecodedMessageHandler<Object?>(channel, handler);
  }

  tearDown(() {
    for (final channel in channels) {
      messenger.setMockDecodedMessageHandler(channel, null);
    }
    channels.clear();
  });

  test('Pigeon encodes project configuration and releases once', () async {
    var releases = 0;
    handle('initialize', (message) async {
      final config =
          (message! as List<Object?>).single! as NativeProjectConfiguration;
      expect(config.width, 1080);
      expect(config.frameRate, 30);
      return [null];
    });
    handle('disposeEditor', (_) async {
      releases++;
      return [null];
    });
    final platform = PigeonEditorPlatform();
    await platform.initialize(project);
    await platform.dispose();
    await platform.dispose();
    expect(releases, 1);
  });

  test('failed competing editor cannot dispose the active editor', () async {
    var releases = 0;
    handle('initialize', (_) async => [null]);
    handle('disposeEditor', (_) async {
      releases++;
      return [null];
    });
    final active = PigeonEditorPlatform();
    final other = PigeonEditorPlatform();
    await active.initialize(project);
    await expectLater(other.initialize(project), throwsStateError);
    await other.dispose();
    expect(releases, 0);
    await active.dispose();
    await expectLater(other.initialize(project), throwsStateError);
    final replacement = PigeonEditorPlatform();
    await replacement.initialize(project);
    await replacement.dispose();
    expect(releases, 2);
  });

  test('missing plugin fails explicitly and releases Dart ownership', () async {
    final platform = PigeonEditorPlatform();
    await expectLater(
      platform.initialize(project),
      throwsA(isA<PlatformException>()),
    );
    handle('initialize', (_) async => [null]);
    handle('disposeEditor', (_) async => [null]);
    await platform.initialize(project);
    await platform.dispose();
  });

  test('native errors preserve stable error codes', () async {
    handle(
      'play',
      (_) async => ['feature-unavailable', 'Playback is not available.', null],
    );
    await expectLater(
      PigeonEditorPlatform().play(),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'feature-unavailable',
        ),
      ),
    );
  });

  test('metadata and events round-trip through the generated codec', () {
    const codec = VnEditorHostApi.pigeonChannelCodec;
    final metadata = NativeMediaMetadata(
      path: '/test.mp4',
      durationMilliseconds: 5000,
      width: 1920,
      height: 1080,
      hasAudio: true,
      frameRate: 29.97,
    );
    expect(codec.decodeMessage(codec.encodeMessage(metadata)), metadata);
    final event = NativePlaybackEvent(
      status: NativePlaybackStatus.paused,
      positionMilliseconds: 1000,
      bufferedPositionMilliseconds: 2000,
    );
    expect(codec.decodeMessage(codec.encodeMessage(event)), event);
    final progress = NativeExportEvent(
      exportId: 'job',
      progress: 0.5,
      isComplete: false,
    );
    expect(codec.decodeMessage(codec.encodeMessage(progress)), progress);
  });

  test(
    'rejects stale media and session events and unregisters on dispose',
    () async {
      handle('initialize', (_) async => [null]);
      handle('disposeEditor', (_) async => [null]);
      handle(
        'openMedia',
        (_) async => [
          NativeMediaMetadata(
            path: '/video.mp4',
            durationMilliseconds: 5000,
            width: 640,
            height: 360,
            hasAudio: true,
          ),
        ],
      );
      final platform = PigeonEditorPlatform();
      await platform.initialize(project);
      await platform.openMedia('/video.mp4');
      final received = <EditorPlayback>[];
      final subscription = platform.playback.listen(received.add);
      final session = platform.previewSessionId!;
      Future<void> send(String id, int request) =>
          platform.onPlaybackStateChanged(
            NativePlaybackEvent(
              sessionId: id,
              requestId: request,
              status: NativePlaybackStatus.playing,
              positionMilliseconds: 1200,
              bufferedPositionMilliseconds: 3000,
            ),
          );
      await send('old-session', 1);
      await send(session, 0);
      await send(session, 1);
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
      expect(received.single.position.inMilliseconds, 1200);
      await platform.dispose();
      await send(session, 1);
      expect(received, hasLength(1));
      await subscription.cancel();
    },
  );
}
