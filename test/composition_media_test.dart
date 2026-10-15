import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_editor/vn_editor.dart';
import 'package:vn_editor/src/controller/media_strip_loader.dart';
import 'package:vn_editor/src/controller/timeline_cubit.dart';
import 'package:vn_editor/src/models/editor_media_strip.dart';
import 'package:vn_editor/src/timeline/editor_composition.dart';
import 'fake_editor_platform.dart';
import 'timeline_view_test.dart' show timelineProject;

void main() {
  test('pause wins while play is waiting for a rebuilt timeline', () async {
    final platform = FakeEditorPlatform();
    final editor = EditorController.withPlatform(
      project: timelineProject(),
      platform: platform,
    );
    await editor.initialize();
    await editor.prepareTimeline();
    editor.execute(
      const EditTimelineClip(clipId: 'First', sourceInUs: 2000000),
    );
    final gate = Completer<void>();
    platform.compositionGate = gate.future;
    final playing = editor.play();
    await editor.pause();
    gate.complete();
    await playing;
    expect(platform.playCalls, 0);
    await editor.close();
  });

  test('failed composition can be explicitly prepared again', () async {
    final platform = FakeEditorPlatform();
    final editor = EditorController.withPlatform(
      project: timelineProject(),
      platform: platform,
    );
    await editor.initialize();
    await editor.prepareTimeline();
    platform.events.add(
      const EditorPlayback(
        status: EditorPlaybackStatus.failed,
        errorMessage: 'decoder failed',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await editor.prepareTimeline();
    expect(platform.compositionCalls, 2);
    await editor.close();
  });

  test(
    'composition preparation coalesces, edits invalidate, play rebuilds',
    () async {
      final platform = FakeEditorPlatform();
      final editor = EditorController.withPlatform(
        project: timelineProject(),
        platform: platform,
      );
      await editor.initialize();
      final gate = Completer<void>();
      platform.compositionGate = gate.future;
      final first = editor.prepareTimeline();
      final second = editor.prepareTimeline();
      expect(platform.compositionCalls, 1);
      gate.complete();
      await Future.wait([first, second]);
      expect(editor.state.isTimeline, isTrue);
      editor.execute(
        const EditTimelineClip(clipId: 'First', sourceInUs: 2000000),
      );
      expect(editor.state.timelineDirty, isTrue);
      await editor.play();
      expect(platform.compositionCalls, 2);
      expect(editor.state.timelineDirty, isFalse);
      editor.undo();
      await editor.prepareTimeline();
      expect(platform.compositionCalls, 3);
      await editor.openMedia('/sample.mp4');
      expect(editor.state.isTimeline, isFalse);
      await editor.close();
    },
  );

  test(
    'edit and close during preparation cannot publish a stale plan',
    () async {
      for (final close in [false, true]) {
        final platform = FakeEditorPlatform();
        final editor = EditorController.withPlatform(
          project: timelineProject(),
          platform: platform,
        );
        await editor.initialize();
        final gate = Completer<void>();
        platform.compositionGate = gate.future;
        final pending = expectLater(editor.prepareTimeline(), throwsStateError);
        if (close) {
          await editor.close();
        } else {
          editor.execute(
            const EditTimelineClip(clipId: 'First', sourceInUs: 2000000),
          );
        }
        gate.complete();
        await pending;
        if (!close) {
          expect(editor.state.media, isNull);
          expect(editor.state.timelineDirty, isTrue);
          await editor.prepareTimeline();
          expect(editor.state.media, isNotNull);
        }
        await editor.close();
      }
    },
  );

  test(
    'composition clock and seeking work in gaps without selection',
    () async {
      final platform = FakeEditorPlatform();
      final editor = EditorController.withPlatform(
        project: timelineProject(),
        platform: platform,
      );
      final timeline = TimelineCubit(editor);
      await editor.initialize();
      await editor.prepareTimeline();
      platform.events.add(
        const EditorPlayback(
          status: EditorPlaybackStatus.playing,
          position: Duration(milliseconds: 1500),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(timeline.state.positionUs, 1500000);
      await timeline.scrub(1000000);
      expect(platform.lastSeek, const Duration(seconds: 1));
      await timeline.close();
      await editor.close();
    },
  );

  test('unsupported compositions are rejected before native mutation', () {
    final project = timelineProject();
    expect(
      () => EditorComposition(
        EditorProject.empty(width: 640, height: 360, frameRate: 30),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => EditorComposition(
        project.copyWith(
          tracks: [
            project.tracks.first,
            EditorTrack(
              id: 'Layer',
              kind: EditorTrackKind.video,
              clips: [
                project.tracks.first.clips.first.copyWith(id: 'Layer clip'),
              ],
            ),
          ],
        ),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => EditorComposition(
        project.copyWith(
          tracks: [
            project.tracks.first.withClips([
              project.tracks.first.clips.first.copyWith(speed: PlaybackRate(8)),
            ]),
          ],
        ),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => EditorComposition(
        project.copyWith(
          tracks: [
            project.tracks.first.withClips([
              project.tracks.first.clips.first.copyWith(
                transform: EditorTransform(scaleX: 2),
              ),
            ]),
          ],
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test(
    'preview queue bounds concurrency and cancels queued/active work',
    () async {
      final platform = FakeEditorPlatform();
      final gate = Completer<EditorMediaStrip>();
      platform.stripGate = gate.future;
      final loader = MediaStripLoader(platform);
      final a = loader.load('/a', 0, 1000000);
      final b = loader.load('/b', 0, 1000000);
      final c = loader.load('/c', 0, 1000000);
      final aResult = expectLater(a.result.future, throwsStateError);
      final cResult = expectLater(c.result.future, throwsStateError);
      expect(platform.stripCalls, 2);
      loader.cancel(a);
      loader.cancel(c);
      gate.complete(EditorMediaStrip(thumbnails: [], peaks: [.5]));
      await Future.wait([aResult, cResult, b.result.future]);
      expect(platform.stripCalls, 2);
      expect(platform.cancelledStrips, [a.id]);
      await loader.close();
      expect(() => loader.load('/a', 0, 10), throwsStateError);
      await platform.dispose();
    },
  );

  test(
    'reorder preserves span/gap, is one undo and boundary moves are no-ops',
    () async {
      final platform = FakeEditorPlatform();
      final editor = EditorController.withPlatform(
        project: timelineProject(),
        platform: platform,
      );
      editor.execute(
        AddTimelineClip(
          trackId: 'Video',
          clip: TimelineClip(
            id: 'Second',
            mediaId: 'source',
            sourceDurationUs: 5000000,
            sourceOutUs: 1000000,
            timelineStartUs: 6000000,
          ),
        ),
      );
      final before = editor.project;
      editor.execute(const ReorderTimelineClip('First', earlier: false));
      expect(editor.project.tracks.first.clips.map((c) => c.id), [
        'Second',
        'First',
      ]);
      expect(editor.project.tracks.first.clips.first.timelineStartUs, 2000000);
      expect(editor.project.tracks.first.clips.last.timelineStartUs, 4000000);
      expect(editor.project.durationUs, 7000000);
      editor.undo();
      expect(editor.project, same(before));
      editor.execute(const ReorderTimelineClip('First', earlier: true));
      expect(editor.project, same(before));
      final timeline = TimelineCubit(editor);
      timeline.select('First');
      timeline.move(timeline.selected!, 4000000);
      expect(timeline.state.error, contains('overlap'));
      expect(editor.project, same(before));
      await timeline.close();
      await editor.close();
    },
  );
}
