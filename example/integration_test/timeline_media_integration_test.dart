import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vn_editor/vn_editor.dart';
import 'package:vn_editor/src/platform/vn_editor_api.g.dart';
import 'package:vn_editor_example/playback_example.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> until(WidgetTester tester, bool Function() ready) async {
    final clock = Stopwatch()..start();
    while (!ready() && clock.elapsed < const Duration(seconds: 20)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(ready(), isTrue, reason: 'Native condition timed out');
  }

  Future<EditorController> create(WidgetTester tester) async {
    final file = await copySampleVideo();
    final rotated = await copySampleVideo('rotated.mp4');
    final project = EditorProject(
      id: 'Timeline media tests',
      width: 640,
      height: 360,
      frameRate: 30,
      videoClips: [
        VideoClip(id: 'a', sourcePath: file.path),
        VideoClip(id: 'b', sourcePath: rotated.path),
      ],
      tracks: [
        EditorTrack(
          id: 'video',
          kind: EditorTrackKind.video,
          clips: [
            TimelineClip(
              id: 'First',
              mediaId: 'a',
              sourceDurationUs: 8000000,
              sourceInUs: 1000000,
              sourceOutUs: 3000000,
            ),
            TimelineClip(
              id: 'Second',
              mediaId: 'b',
              sourceDurationUs: 8000000,
              sourceInUs: 4000000,
              sourceOutUs: 8000000,
              timelineStartUs: 2500000,
              speed: PlaybackRate(2),
              volume: 0,
            ),
          ],
        ),
      ],
    );
    final editor = EditorController(project: project);
    await editor.initialize();
    addTearDown(editor.close);
    await tester.pumpWidget(
      MaterialApp(
        home: VnEditor(project: project, controller: editor),
      ),
    );
    return editor;
  }

  testWidgets(
    'real JPEG thumbnails, PCM peaks, silent/audio-only sources and cache reuse',
    (tester) async {
      final editor = await create(tester);
      final api = VnEditorHostApi();
      final path = editor.project.videoClips.first.sourcePath;
      final data = await api.loadMediaStrip(path, 0, 2000000, 3, 10001);
      expect(data.thumbnails, hasLength(3));
      expect(data.peaks, hasLength(128));
      expect(data.peaks.any((p) => p > .01), isTrue);
      expect(data.peaks.every((p) => p.isFinite && p >= 0 && p <= 1), isTrue);
      for (final path in data.thumbnails) {
        final codec = await ui.instantiateImageCodec(
          await File(path).readAsBytes(),
        );
        final frame = await codec.getNextFrame();
        expect(frame.image.width, lessThanOrEqualTo(160));
        expect(frame.image.height, lessThanOrEqualTo(90));
        frame.image.dispose();
        codec.dispose();
      }
      final cached = await api.loadMediaStrip(path, 0, 2000000, 3, 10002);
      expect(cached.thumbnails, data.thumbnails);
      final silent = await copySampleVideo('silent.mp4');
      final silentData = await api.loadMediaStrip(
        silent.path,
        0,
        1000000,
        2,
        10003,
      );
      expect(silentData.thumbnails, hasLength(2));
      expect(silentData.peaks, isEmpty);
      final audio = await copySampleVideo('audio.m4a');
      final audioData = await api.loadMediaStrip(
        audio.path,
        0,
        1000000,
        0,
        10004,
      );
      expect(audioData.thumbnails, isEmpty);
      expect(audioData.peaks.any((p) => p > 0), isTrue);
      for (var i = 0; i < 18; i++) {
        await api.loadMediaStrip(
          path,
          i * 10000,
          i * 10000 + 200000,
          1,
          11000 + i,
        );
      }
      expect(
        await File(data.thumbnails.first).exists(),
        isFalse,
        reason: 'Least-recently-used thumbnail files must be evicted',
      );
      final remaining = await File(data.thumbnails.first).parent.list().length;
      expect(remaining, lessThanOrEqualTo(16 * 8));
      await editor.close();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(await File(data.thumbnails.first).exists(), isFalse);
    },
  );

  testWidgets('preview validation, cancellation, corruption and recovery', (
    tester,
  ) async {
    final editor = await create(tester);
    final api = VnEditorHostApi();
    final path = editor.project.videoClips.first.sourcePath;
    for (final range in [
      (0, 0, 1),
      (-1, 1000, 1),
      (0, 1000, 9),
      (0, 99000000, 1),
    ]) {
      await expectLater(
        api.loadMediaStrip(path, range.$1, range.$2, range.$3, 20001),
        throwsA(isA<PlatformException>()),
      );
    }
    final corrupt = await copySampleVideo('corrupt.mp4');
    await expectLater(
      api.loadMediaStrip(corrupt.path, 0, 1000000, 2, 20002),
      throwsA(isA<PlatformException>()),
    );
    await expectLater(
      api.loadMediaStrip('/missing-file.mp4', 0, 1000000, 2, 20003),
      throwsA(isA<PlatformException>()),
    );
    final long = await copySampleVideo('long.mp4');
    final pending = api.loadMediaStrip(long.path, 0, 599000000, 8, 20004);
    final expectation = expectLater(
      pending,
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'operation-cancelled',
        ),
      ),
    );
    await api.cancelMediaStrip(20004);
    await expectation;
    expect(
      (await api.loadMediaStrip(path, 0, 1000000, 1, 20005)).thumbnails,
      hasLength(1),
    );
    await editor.close();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'native cut composition plays trim, gap, second source, speed, end and replay',
    (tester) async {
      final editor = await create(tester);
      await editor.prepareTimeline();
      expect(editor.state.isTimeline, isTrue);
      expect(editor.state.media!.duration.inMilliseconds, 4500);
      await editor.play();
      await until(tester, () => editor.state.position.inMilliseconds >= 2800);
      expect(editor.state.isPlaying, isTrue);
      await editor.pause();
      await editor.seek(const Duration(milliseconds: 2250));
      await until(
        tester,
        () => (editor.state.position.inMilliseconds - 2250).abs() < 150,
      );
      await editor.seek(const Duration(milliseconds: 3200));
      await until(
        tester,
        () => (editor.state.position.inMilliseconds - 3200).abs() < 150,
      );
      await editor.play();
      await until(
        tester,
        () => editor.state.playback.status == EditorPlaybackStatus.ended,
      );
      expect(editor.state.position.inMilliseconds, closeTo(4500, 100));
      await editor.play();
      await until(
        tester,
        () =>
            editor.state.isPlaying &&
            editor.state.position.inMilliseconds < 1500,
      );
      await editor.pause();
      editor.execute(
        const EditTimelineClip(clipId: 'Second', sourceOutUs: 6000000),
      );
      expect(editor.state.timelineDirty, isTrue);
      await editor.prepareTimeline();
      expect(editor.state.media!.duration.inMilliseconds, 3500);
      editor.undo();
      await editor.prepareTimeline();
      expect(editor.state.media!.duration.inMilliseconds, 4500);
      await editor.openMedia(editor.project.videoClips.first.sourcePath);
      expect(editor.state.isTimeline, isFalse);
      expect(editor.state.media!.duration.inMilliseconds, closeTo(8000, 100));
      await editor.close();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('composition rejects invalid native source ranges and recovers', (
    tester,
  ) async {
    final editor = await create(tester);
    final api = VnEditorHostApi();
    await expectLater(
      api.openComposition([
        NativeTimelineSegment(
          path: editor.project.videoClips.first.sourcePath,
          sourceInUs: 0,
          sourceOutUs: 20000000,
          startUs: 0,
          durationUs: 20000000,
          speed: 1,
          volume: 1,
        ),
      ], 30001),
      throwsA(isA<PlatformException>()),
    );
    await editor.prepareTimeline();
    expect(editor.state.media!.duration.inMilliseconds, 4500);
    await editor.close();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'composition close cancels pending prepare and releases ownership',
    (tester) async {
      final editor = await create(tester);
      final preparing = editor.prepareTimeline();
      final failure = expectLater(
        preparing,
        throwsA(anyOf(isA<PlatformException>(), isA<StateError>())),
      );
      await editor.close();
      await failure;
      await tester.pumpWidget(const SizedBox.shrink());
      final next = await create(tester);
      await next.prepareTimeline();
      expect(next.state.media!.duration.inMilliseconds, 4500);
      await next.close();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
