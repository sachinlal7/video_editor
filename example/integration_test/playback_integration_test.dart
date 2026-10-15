import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vn_editor/vn_editor.dart';
import 'package:vn_editor_example/playback_example.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> until(WidgetTester tester, bool Function() condition) async {
    final deadline = Stopwatch()..start();
    while (!condition() && deadline.elapsed < const Duration(seconds: 15)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      condition(),
      isTrue,
      reason: 'Native state did not arrive within 15 seconds.',
    );
  }

  Future<EditorController> create(WidgetTester tester) async {
    final controller = EditorController(
      project: EditorProject.empty(
        id: 'Playback tests',
        width: 640,
        height: 360,
        frameRate: 30,
      ),
    );
    await controller.initialize();
    addTearDown(controller.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorPreview(controller: controller)),
      ),
    );
    return controller;
  }

  testWidgets(
    'real video metadata, surface, native clock, pause, seek, end and replay',
    (tester) async {
      final controller = await create(tester);
      final file = await copySampleVideo();
      final media = await controller.openMedia(file.path);
      expect(media.width, 640);
      expect(media.height, 360);
      expect(media.hasAudio, isTrue);
      expect(media.duration.inMilliseconds, closeTo(8000, 100));
      expect(media.frameRate, closeTo(30, 0.1));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(EditorPreview), findsOneWidget);
      await controller.play();
      await until(
        tester,
        () =>
            controller.state.isPlaying &&
            controller.state.position.inMilliseconds > 500,
      );
      await controller.pause();
      await until(tester, () => !controller.state.isPlaying);
      final paused = controller.state.position;
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        (controller.state.position - paused).inMilliseconds.abs(),
        lessThan(250),
      );
      await controller.seek(const Duration(seconds: 4));
      await until(
        tester,
        () => (controller.state.position.inMilliseconds - 4000).abs() < 150,
      );
      await expectLater(
        controller.seek(const Duration(seconds: 99)),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'invalid-position',
          ),
        ),
      );
      await controller.seek(const Duration(milliseconds: 7500));
      await controller.play();
      await until(
        tester,
        () => controller.state.playback.status == EditorPlaybackStatus.ended,
      );
      expect(controller.state.isPlaying, isFalse);
      await controller.play();
      await until(
        tester,
        () =>
            controller.state.isPlaying &&
            controller.state.position.inMilliseconds < 2000,
      );
      await controller.pause();
      await controller.close();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'silent portrait and rotation metadata survive source replacement',
    (tester) async {
      final controller = await create(tester);
      final silent = await copySampleVideo('silent.mp4');
      final first = await controller.openMedia(silent.uri.toString());
      expect(first.hasAudio, isFalse);
      expect(first.width, 180);
      expect(first.height, 320);
      await controller.play();
      await until(tester, () => controller.state.position.inMilliseconds > 300);
      final rotated = await copySampleVideo('rotated.mp4');
      final second = await controller.openMedia(rotated.path);
      expect(second.width, 360);
      expect(second.height, 640);
      expect(second.hasAudio, isTrue);
      expect(controller.state.media!.path, rotated.path);
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.state.isPlaying, isFalse);
      expect(controller.state.position.inMilliseconds, lessThan(100));
      await controller.close();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('missing, invalid, corrupt files and no-media commands recover', (
    tester,
  ) async {
    final controller = await create(tester);
    await expectLater(
      controller.play(),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'no-media'),
      ),
    );
    final corrupt = await copySampleVideo('corrupt.mp4');
    final empty = await copySampleVideo('empty.mp4');
    final audio = await copySampleVideo('audio.m4a');
    for (final path in [
      'relative.mp4',
      'https://example.com/video.mp4',
      '${Directory.systemTemp.path}/missing.mp4',
      corrupt.path,
      empty.path,
      audio.path,
    ]) {
      await expectLater(
        controller.openMedia(path),
        throwsA(isA<PlatformException>()),
      );
      expect(controller.state.playback.status, EditorPlaybackStatus.failed);
      expect(controller.state.media, isNull);
    }
    final valid = await copySampleVideo();
    await controller.openMedia(valid.path);
    await controller.play();
    await until(tester, () => controller.state.isPlaying);
    await controller.close();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'replacement and close cancel pending opens and allow a new owner',
    (tester) async {
      final controller = await create(tester);
      final file = await copySampleVideo();
      final silent = await copySampleVideo('silent.mp4');
      final first = controller.openMedia(file.path);
      final cancelled = expectLater(
        first,
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'operation-cancelled',
          ),
        ),
      );
      await controller.openMedia(silent.path);
      await cancelled;
      expect(controller.state.media!.path, silent.path);
      final opening = controller.openMedia(file.path);
      final closingResult = expectLater(
        opening,
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'operation-cancelled',
          ),
        ),
      );
      await controller.close();
      await closingResult;
      final next = await create(tester);
      await next.openMedia(file.path);
      await next.play();
      await until(tester, () => next.state.isPlaying);
      await next.close();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'ten-minute source supports distant seek and end without Dart timers',
    (tester) async {
      final controller = await create(tester);
      final file = await copySampleVideo('long.mp4');
      final media = await controller.openMedia(file.path);
      expect(media.duration.inSeconds, 600);
      await controller.seek(const Duration(seconds: 599));
      await until(
        tester,
        () => (controller.state.position.inMilliseconds - 599000).abs() < 200,
      );
      await controller.play();
      await until(
        tester,
        () => controller.state.playback.status == EditorPlaybackStatus.ended,
      );
      await controller.close();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('app background pauses without automatic resume', (tester) async {
    final controller = await create(tester);
    await controller.openMedia((await copySampleVideo()).path);
    await controller.play();
    await until(tester, () => controller.state.isPlaying);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await until(tester, () => !controller.state.isPlaying);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.state.isPlaying, isFalse);
    await controller.close();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'repeated player release and recreation does not retain ownership',
    (tester) async {
      final file = await copySampleVideo();
      for (var i = 0; i < 10; i++) {
        final controller = await create(tester);
        await controller.openMedia(file.path);
        await controller.play();
        await until(tester, () => controller.state.isPlaying);
        await controller.close();
        expect(controller.state.isPlaying, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'public editor controls play, pause and seek the native preview',
    (tester) async {
      final controller = await create(tester);
      await controller.openMedia((await copySampleVideo()).path);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: VnEditor(project: controller.project, controller: controller),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Play'));
      await until(
        tester,
        () =>
            controller.state.isPlaying &&
            controller.state.position.inMilliseconds > 500,
      );
      await tester.tap(find.byTooltip('Pause'));
      await until(tester, () => !controller.state.isPlaying);
      await tester.tapAt(tester.getCenter(find.byType(Slider)));
      await until(
        tester,
        () => (controller.state.position.inMilliseconds - 4000).abs() < 250,
      );
      // Opt-in window for native screenshots and physical-device measurements.
      const hold = int.fromEnvironment('VN_PREVIEW_HOLD_SECONDS');
      if (hold > 0) await tester.pump(Duration(seconds: hold));
      await controller.close();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('timeline selection, trim, undo and mapped native seek', (
    tester,
  ) async {
    final controller = await create(tester);
    final file = await copySampleVideo();
    final media = await controller.openMedia(file.path);
    controller.execute(
      EditorTransaction([
        AddVideoSource(VideoClip(id: 'source', sourcePath: file.path)),
        AddTrack(
          EditorTrack(
            id: 'Video',
            kind: EditorTrackKind.video,
            clips: [
              TimelineClip(
                id: 'Test clip',
                mediaId: 'source',
                sourceDurationUs: media.duration.inMicroseconds,
                sourceOutUs: media.duration.inMicroseconds,
              ),
            ],
          ),
        ),
      ]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: VnEditor(project: controller.project, controller: controller),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Test clip'));
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('Test clip-start')),
      const Offset(48, 0),
    );
    await tester.pump();
    expect(
      controller.project.tracks.first.clips.first.sourceInUs,
      greaterThan(0),
    );
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(controller.project.tracks.first.clips.first.sourceInUs, 0);
    final ruler = tester.getTopLeft(
      find.byKey(const ValueKey('timeline-ruler')),
    );
    await tester.tapAt(ruler + const Offset(128, 24));
    await until(
      tester,
      () => (controller.state.position.inMilliseconds - 2000).abs() < 150,
    );
    await controller.close();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  const soak = int.fromEnvironment('VN_SOAK_SECONDS');
  if (soak > 0) {
    testWidgets('physical-device sustained playback probe', (tester) async {
      final controller = await create(tester);
      await controller.openMedia((await copySampleVideo('long.mp4')).path);
      await controller.play();
      await until(tester, () => controller.state.isPlaying);
      for (var second = 0; second < soak; second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(
        controller.state.position.inSeconds,
        greaterThanOrEqualTo(soak - 2),
      );
      expect(controller.state.isPlaying, isTrue);
      await controller.close();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
