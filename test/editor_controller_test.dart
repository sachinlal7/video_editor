import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vn_editor/vn_editor.dart';

import 'fake_editor_platform.dart';

void main() {
  late EditorProject project;
  late FakeEditorPlatform platform;
  late EditorController controller;

  setUp(() {
    project = EditorProject.empty(
      id: 'test',
      width: 1080,
      height: 1920,
      frameRate: 30,
    );
    platform = FakeEditorPlatform();
    controller = EditorController.withPlatform(
      project: project,
      platform: platform,
    );
  });

  tearDown(() async {
    await controller.close();
  });

  test('initializes exactly once and becomes ready', () async {
    await Future.wait(<Future<void>>[
      controller.initialize(),
      controller.initialize(),
    ]);
    expect(platform.initializeCalls, 1);
    expect(controller.state.lifecycle, EditorLifecycleState.ready);
  });

  test('records initialization failure and allows retry', () async {
    platform.initializeError = StateError('native failed');
    await expectLater(controller.initialize(), throwsStateError);
    expect(controller.state.lifecycle, EditorLifecycleState.failed);
    expect(controller.state.lastError, isA<StateError>());

    platform.initializeError = null;
    await controller.initialize();
    expect(platform.initializeCalls, 2);
    expect(controller.state.lifecycle, EditorLifecycleState.ready);
    expect(controller.state.lastError, isNull);
  });

  test('rejects commands before initialization', () {
    expect(controller.play, throwsStateError);
    expect(() => controller.openMedia('/video.mp4'), throwsStateError);
  });

  test('synchronous platform initialization failure can be retried', () async {
    platform.synchronousInitializeError = StateError('channel unavailable');
    await expectLater(controller.initialize(), throwsStateError);
    platform.synchronousInitializeError = null;
    await controller.initialize();
    expect(platform.initializeCalls, 2);
    expect(controller.state.lifecycle, EditorLifecycleState.ready);
  });

  test(
    'command acknowledgements do not invent native playback state',
    () async {
      await controller.initialize();
      platform.playError = StateError('decoder failed');
      await expectLater(controller.play(), throwsStateError);
      expect(controller.state.isPlaying, isFalse);

      platform.playError = null;
      await controller.play();
      expect(controller.state.isPlaying, isFalse);
      await controller.pause();
      expect(controller.state.isPlaying, isFalse);
    },
  );

  test('rejects negative seeks without calling native code', () async {
    await controller.initialize();
    await expectLater(
      controller.seek(const Duration(milliseconds: -1)),
      throwsArgumentError,
    );
    expect(platform.seekCalls, 0);
  });

  test('native events alone own source time and playback state', () async {
    await controller.initialize();
    platform.events.add(
      const EditorPlayback(
        status: EditorPlaybackStatus.playing,
        position: Duration(milliseconds: 1234),
        bufferedPosition: Duration(seconds: 4),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.isPlaying, isTrue);
    expect(controller.state.position.inMilliseconds, 1234);
    expect(controller.state.playback.bufferedPosition.inSeconds, 4);
    platform.events.add(
      const EditorPlayback(
        status: EditorPlaybackStatus.failed,
        errorMessage: 'Decode failed',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.isPlaying, isFalse);
    expect(controller.state.lastError, 'Decode failed');
    await controller.close();
    expect(platform.events.hasListener, isFalse);
  });

  test('delegates valid media and export commands', () async {
    await controller.initialize();
    final metadata = await controller.openMedia('/video.mp4');
    final exportId = await controller.export(
      EditorExportSettings(outputPath: '/out.mp4'),
    );
    await controller.cancelExport(exportId);

    expect(metadata.duration, const Duration(seconds: 5));
    expect(exportId, 'export-1');
    expect(platform.openMediaCalls, 1);
    expect(platform.exportCalls, 1);
    expect(platform.cancelExportCalls, 1);
  });

  test('rejects blank media, effect, and export identifiers', () async {
    await controller.initialize();
    await expectLater(controller.openMedia(' '), throwsArgumentError);
    await expectLater(controller.removeEffect(' '), throwsArgumentError);
    await expectLater(controller.cancelExport(' '), throwsArgumentError);
    expect(platform.openMediaCalls, 0);
    expect(platform.cancelExportCalls, 0);
  });

  test(
    'close waits for pending initialization and cannot become ready again',
    () async {
      final gate = Completer<void>();
      platform.initializationGate = gate.future;
      final starting = controller.initialize();
      final closing = controller.close();
      expect(identical(closing, controller.close()), isTrue);
      expect(platform.disposeCalls, 0);
      gate.complete();
      await starting;
      await closing;
      expect(controller.state.lifecycle, EditorLifecycleState.disposed);
      expect(platform.disposeCalls, 1);
    },
  );

  test('in-flight commands cannot emit after close', () async {
    await controller.initialize();
    final gate = Completer<void>();
    platform.playGate = gate.future;
    final playing = controller.play();
    await controller.close();
    gate.complete();
    await playing;
    expect(controller.state.lifecycle, EditorLifecycleState.disposed);
  });

  test('close still closes the stream when native release fails', () async {
    await controller.initialize();
    platform.disposeError = StateError('release failed');
    await expectLater(controller.close(), throwsStateError);
    expect(controller.isClosed, isTrue);
    platform.disposeError = null;
    // The same failing close future remains observable by callers.
    controller = EditorController.withPlatform(
      project: project,
      platform: FakeEditorPlatform(),
    );
  });

  test('disposes native ownership once and rejects later use', () async {
    await controller.initialize();
    await controller.close();
    await controller.close();

    expect(platform.disposeCalls, 1);
    expect(controller.initialize, throwsStateError);
  });
}
