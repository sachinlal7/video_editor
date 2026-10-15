import 'package:flutter_test/flutter_test.dart';
import 'package:vn_editor/vn_editor.dart';

import 'fake_editor_platform.dart';

EditorProject timelineProject() => EditorProject(
  id: 'timeline',
  width: 1920,
  height: 1080,
  frameRate: 29.97,
  videoClips: const [VideoClip(id: 'video', sourcePath: 'media/video.mp4')],
  audioClips: const [AudioClip(id: 'audio', sourcePath: 'media/audio.m4a')],
  tracks: [EditorTrack(id: 'video-track', kind: EditorTrackKind.video)],
);

TimelineClip placement({
  String id = 'clip',
  int start = 0,
  PlaybackRate? speed,
}) => TimelineClip(
  id: id,
  mediaId: 'video',
  sourceDurationUs: 10000000,
  sourceInUs: 1000000,
  sourceOutUs: 9000000,
  timelineStartUs: start,
  speed: speed ?? PlaybackRate.normal,
);

void main() {
  group('integer time and rational rates', () {
    test('normalizes speed and maps source/timeline without accumulation', () {
      final speed = PlaybackRate(6, 4);
      expect(speed.numerator, 3);
      expect(speed.denominator, 2);
      final clip = placement(start: 2000000, speed: PlaybackRate(2));
      expect(clip.durationUs, 4000000);
      expect(clip.timelineEndUs, 6000000);
      expect(clip.sourceTimeAt(3000000), 3000000);
      expect(() => clip.sourceTimeAt(6000000), throwsRangeError);
      expect(() => clip.sourceTimeAt(1999999), throwsRangeError);
    });

    test('uses exact intermediates for long sources and rounds once', () {
      final rate = PlaybackRate(30000, 1001);
      const length = 8000000000000;
      final expected =
          (BigInt.from(length) * BigInt.from(1001) + BigInt.from(29999)) ~/
          BigInt.from(30000);
      expect(rate.timelineDuration(length), expected.toInt());
      expect(PlaybackRate(3, 2).timelineDuration(5), 4);
    });

    test('rejects invalid rates, time ranges, volume, and overflow', () {
      for (final pair in [(0, 1), (-1, 1), (1, 0), (1, -1)]) {
        expect(() => PlaybackRate(pair.$1, pair.$2), throwsArgumentError);
      }
      final clip = placement();
      expect(() => clip.copyWith(sourceInUs: -1), throwsArgumentError);
      expect(() => clip.copyWith(sourceInUs: 9000000), throwsArgumentError);
      expect(() => clip.copyWith(sourceOutUs: 10000001), throwsArgumentError);
      expect(() => clip.copyWith(timelineStartUs: -1), throwsArgumentError);
      for (final volume in [-1.0, 1.1, double.nan, double.infinity]) {
        expect(() => clip.copyWith(volume: volume), throwsArgumentError);
      }
      expect(
        () => clip.copyWith(timelineStartUs: 9007199254740991),
        throwsArgumentError,
      );
      expect(
        () => PlaybackRate(1, 9007199254740991).timelineDuration(2),
        throwsArgumentError,
      );
      expect(() => PlaybackRate.normal.sourceOffset(-1), throwsArgumentError);
    });
  });

  group('tracks and references', () {
    test('reused sources cannot claim conflicting durations', () {
      expect(
        () => timelineProject().copyWith(
          tracks: [
            EditorTrack(
              id: 'a',
              kind: EditorTrackKind.video,
              clips: [placement()],
            ),
            EditorTrack(
              id: 'b',
              kind: EditorTrackKind.video,
              clips: [
                TimelineClip(
                  id: 'other',
                  mediaId: 'video',
                  sourceDurationUs: 20000000,
                  sourceOutUs: 1000000,
                ),
              ],
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('audio sources and tracks use the same editing rules', () async {
      final controller = EditorController.withPlatform(
        project: timelineProject(),
        platform: FakeEditorPlatform(),
      );
      try {
        controller.execute(
          EditorTransaction([
            const AddAudioSource(
              AudioClip(id: 'voice', sourcePath: 'media/voice.m4a'),
            ),
            AddTrack(
              EditorTrack(id: 'voice-track', kind: EditorTrackKind.audio),
            ),
            AddTimelineClip(
              trackId: 'voice-track',
              clip: TimelineClip(
                id: 'voice-clip',
                mediaId: 'voice',
                sourceDurationUs: 2000000,
                sourceOutUs: 2000000,
              ),
            ),
            const EditTimelineClip(clipId: 'voice-clip', volume: 0),
          ]),
        );
        expect(controller.project.tracks.last.clips.single.volume, 0);
        controller.undo();
        expect(controller.project.tracks, hasLength(1));
        expect(controller.project.audioClips, hasLength(1));
      } finally {
        await controller.close();
      }
    });
    test('sorts immutable snapshots and permits adjacent intervals', () {
      final clips = [placement(id: 'right', start: 8000000), placement()];
      final track = EditorTrack(
        id: 't',
        kind: EditorTrackKind.video,
        clips: clips,
      );
      clips.clear();
      expect(track.clips.map((c) => c.id), ['clip', 'right']);
      expect(() => track.clips.clear(), throwsUnsupportedError);
      expect(() => timelineProject().tracks.clear(), throwsUnsupportedError);
    });

    test(
      'rejects overlap, duplicate IDs, missing sources and wrong media kind',
      () {
        expect(
          () => EditorTrack(
            id: 't',
            kind: EditorTrackKind.video,
            clips: [
              placement(),
              placement(id: 'b', start: 1),
            ],
          ),
          throwsArgumentError,
        );
        expect(
          () => EditorTrack(
            id: 't',
            kind: EditorTrackKind.video,
            clips: [placement(), placement(start: 8000000)],
          ),
          throwsArgumentError,
        );
        final project = timelineProject();
        expect(
          () => project.copyWith(
            tracks: [
              EditorTrack(
                id: 't',
                kind: EditorTrackKind.audio,
                clips: [placement()],
              ),
            ],
          ),
          throwsArgumentError,
        );
        expect(
          () => project.copyWith(
            videoClips: [],
            tracks: [
              EditorTrack(
                id: 't',
                kind: EditorTrackKind.video,
                clips: [placement()],
              ),
            ],
          ),
          throwsArgumentError,
        );
        expect(
          () => project.copyWith(
            videoClips: [...project.videoClips, ...project.videoClips],
          ),
          throwsArgumentError,
        );
        expect(
          () =>
              project.copyWith(tracks: [...project.tracks, ...project.tracks]),
          throwsArgumentError,
        );
        expect(
          () => project.copyWith(
            tracks: [
              EditorTrack(
                id: 'a',
                kind: EditorTrackKind.video,
                clips: [placement()],
              ),
              EditorTrack(
                id: 'b',
                kind: EditorTrackKind.video,
                clips: [placement()],
              ),
            ],
          ),
          throwsArgumentError,
        );
      },
    );

    test('separate tracks allow overlapping layers and reuse one source', () {
      final project = timelineProject().copyWith(
        tracks: [
          EditorTrack(
            id: 'a',
            kind: EditorTrackKind.video,
            clips: [placement()],
          ),
          EditorTrack(
            id: 'b',
            kind: EditorTrackKind.video,
            clips: [placement(id: 'other', start: 1)],
          ),
        ],
      );
      expect(project.videoClips, hasLength(1));
      expect(project.durationUs, 8000001);
    });
  });

  group('editing and history', () {
    late EditorController controller;
    setUp(() {
      controller = EditorController.withPlatform(
        project: timelineProject(),
        platform: FakeEditorPlatform(),
      );
      controller.execute(
        AddTimelineClip(trackId: 'video-track', clip: placement()),
      );
    });
    tearDown(() => controller.close());
    TimelineClip current() => controller.project.tracks.single.clips.single;

    test(
      'trim, move, speed, volume, undo and redo preserve exact snapshots',
      () {
        final before = controller.project;
        controller.execute(
          EditTimelineClip(
            clipId: 'clip',
            sourceInUs: 2000000,
            sourceOutUs: 8000000,
            timelineStartUs: 1000000,
            speed: PlaybackRate(2),
            volume: 0.25,
          ),
        );
        final after = controller.project;
        expect(current().durationUs, 3000000);
        expect(current().sourceTimeAt(2000000), 4000000);
        expect(current().volume, 0.25);
        expect(controller.state.project, same(after));
        controller.undo();
        expect(controller.project, same(before));
        expect(controller.state.canRedo, isTrue);
        controller.redo();
        expect(controller.project, same(after));
      },
    );

    test('split keeps source continuity, duration, rate and volume', () {
      controller.execute(
        EditTimelineClip(
          clipId: 'clip',
          speed: PlaybackRate(3, 2),
          volume: 0.5,
        ),
      );
      final duration = controller.project.durationUs;
      controller.execute(
        const SplitTimelineClip(
          clipId: 'clip',
          atUs: 2000000,
          rightClipId: 'right',
        ),
      );
      final clips = controller.project.tracks.single.clips;
      expect(clips[0].sourceOutUs, clips[1].sourceInUs);
      expect(clips[0].timelineEndUs, clips[1].timelineStartUs);
      expect(controller.project.durationUs, duration);
      expect(clips[1].volume, 0.5);
      controller.undo();
      expect(controller.project.tracks.single.clips, hasLength(1));
      controller.redo();
      expect(controller.project.tracks.single.clips, hasLength(2));
    });

    test(
      'rejects endpoint, duplicate-ID and nonrepresentable splits atomically',
      () {
        final before = controller.project;
        for (final time in [-1, 0, 8000000]) {
          expect(
            () => controller.execute(
              SplitTimelineClip(
                clipId: 'clip',
                atUs: time,
                rightClipId: 'right',
              ),
            ),
            throwsArgumentError,
          );
        }
        expect(
          () => controller.execute(
            const SplitTimelineClip(
              clipId: 'clip',
              atUs: 1000000,
              rightClipId: 'clip',
            ),
          ),
          throwsArgumentError,
        );
        expect(controller.project, same(before));
        controller.execute(
          EditTimelineClip(clipId: 'clip', speed: PlaybackRate(1, 3)),
        );
        expect(
          () => controller.execute(
            const SplitTimelineClip(
              clipId: 'clip',
              atUs: 1,
              rightClipId: 'right',
            ),
          ),
          throwsArgumentError,
        );
      },
    );

    test('failed edits preserve project and redo history', () {
      controller.execute(const EditTimelineClip(clipId: 'clip', volume: 0.5));
      controller.undo();
      final before = controller.project;
      expect(
        () => controller.execute(
          const EditTimelineClip(clipId: 'missing', volume: 0.3),
        ),
        throwsArgumentError,
      );
      expect(
        () => controller.execute(
          AddTimelineClip(
            trackId: 'video-track',
            clip: placement(id: 'overlap', start: 1),
          ),
        ),
        throwsArgumentError,
      );
      expect(controller.project, same(before));
      expect(controller.state.canRedo, isTrue);
      controller.execute(const EditTimelineClip(clipId: 'clip', volume: 0.2));
      expect(controller.state.canRedo, isFalse);
    });

    test(
      'speed expansion rejects overlap instead of moving adjacent clips',
      () {
        controller.execute(
          AddTimelineClip(
            trackId: 'video-track',
            clip: placement(id: 'next', start: 8000000),
          ),
        );
        final before = controller.project;
        expect(
          () => controller.execute(
            EditTimelineClip(clipId: 'clip', speed: PlaybackRate(1, 2)),
          ),
          throwsArgumentError,
        );
        expect(controller.project, same(before));
      },
    );

    test('transactions have one undo entry and roll back on failure', () {
      final before = controller.project;
      controller.execute(
        EditorTransaction([
          const EditTimelineClip(clipId: 'clip', volume: 0.1),
          const EditTimelineClip(clipId: 'clip', timelineStartUs: 20),
        ]),
      );
      controller.undo();
      expect(controller.project, same(before));
      expect(
        () => controller.execute(
          EditorTransaction([
            const RemoveTimelineClip('clip'),
            const RemoveTrack('missing'),
          ]),
        ),
        throwsArgumentError,
      );
      expect(controller.project, same(before));
      expect(controller.state.canRedo, isTrue);
    });

    test('remove clip and track are undoable, sources are retained', () {
      controller.execute(const RemoveTimelineClip('clip'));
      expect(controller.project.durationUs, 0);
      controller.undo();
      controller.execute(const RemoveTrack('video-track'));
      expect(controller.project.tracks, isEmpty);
      expect(controller.project.videoClips, hasLength(1));
      controller.undo();
      expect(current().id, 'clip');
    });

    test('history is bounded and closed controller rejects edits', () async {
      for (var i = 0; i < 110; i++) {
        controller.execute(
          EditTimelineClip(clipId: 'clip', timelineStartUs: i),
        );
      }
      var undone = 0;
      while (controller.state.canUndo) {
        controller.undo();
        undone++;
      }
      expect(undone, EditorController.historyLimit);
      controller.undo();
      await controller.close();
      expect(controller.state.canRedo, isFalse);
      expect(
        () => controller.execute(const RemoveTrack('video-track')),
        throwsStateError,
      );
      expect(controller.undo, throwsStateError);
      expect(controller.redo, throwsStateError);
    });

    test('empty transaction does not add history or clear redo', () {
      controller.undo();
      controller.execute(EditorTransaction([]));
      expect(controller.state.canUndo, isFalse);
      expect(controller.state.canRedo, isTrue);
    });
  });
}
