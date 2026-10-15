import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vn_editor/vn_editor.dart';

import 'fake_editor_platform.dart';
import 'phase_one_fixture.dart';

void main() {
  const codec = EditorProjectCodec();
  group('timebase', () {
    test('NTSC frames are derived independently without accumulated drift', () {
      final rate = EditorFrameRate(30000, 1001);
      expect(rate.timeAtFrame(1), 33367);
      expect(rate.timeAtFrame(30000), 1001000000);
      for (final frame in [0, 1, 2, 100, 1000000]) {
        expect(rate.frameAtTime(rate.timeAtFrame(frame)), frame);
        expect(rate.snap(rate.timeAtFrame(frame)), rate.timeAtFrame(frame));
      }
      expect(EditorFrameRate.fromDouble(29.97).denominator, 100);
      expect(EditorFrameRate(60, 2).numerator, 30);
    });

    test(
      'rejects invalid/unrepresentable rates, times, and mismatched config',
      () {
        for (final rate in [
          0.0,
          -1.0,
          double.nan,
          double.infinity,
          1000001.0,
          1e-300,
        ]) {
          expect(() => EditorFrameRate.fromDouble(rate), throwsArgumentError);
        }
        expect(() => EditorFrameRate(1, 0), throwsArgumentError);
        expect(
          () => EditorFrameRate(1).timeAtFrame(9007199254740991),
          throwsArgumentError,
        );
        expect(() => EditorFrameRate(30).snap(-1), throwsArgumentError);
        expect(
          () => EditorProject.empty(
            width: 10,
            height: 10,
            frameRate: 29.97,
            timebase: EditorFrameRate(30000, 1001),
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('complete editing data', () {
    late EditorController controller;
    setUp(
      () => controller = EditorController.withPlatform(
        project: fullProject(),
        platform: FakeEditorPlatform(),
      ),
    );
    tearDown(() => controller.close());
    TimelineClip clip(String id) => controller.project.tracks
        .expand((t) => t.clips)
        .firstWhere((c) => c.id == id);

    test('overlay transform, content, timing and duration are undoable', () {
      final before = controller.project;
      final transform = EditorTransform(
        x: 0.9,
        y: 0.1,
        scaleX: 2,
        scaleY: 3,
        rotation: 1,
        opacity: 0.4,
      );
      controller.execute(
        EditorTransaction([
          const SetOverlayContent(
            id: 'text',
            kind: EditorTrackKind.text,
            value: 'Updated',
          ),
          EditTimelineClip(
            clipId: 'caption',
            timelineStartUs: 500000,
            transform: transform,
          ),
          const SetStillDuration(clipId: 'caption', durationUs: 3000000),
        ]),
      );
      expect(controller.project.textOverlays.single.text, 'Updated');
      expect(clip('caption').transform, transform);
      expect(clip('caption').timelineEndUs, 3500000);
      controller.undo();
      expect(controller.project, same(before));
      controller.redo();
      expect(clip('caption').durationUs, 3000000);
    });

    test(
      'all static definitions can be added, placed, and removed with undo',
      () {
        final before = controller.project;
        controller.execute(
          EditorTransaction([
            const AddImageSource(
              ImageClip(id: 'new-image', sourcePath: 'new.jpg'),
            ),
            const AddTextOverlay(TextOverlay(id: 'new-text', text: 'New')),
            const AddStickerOverlay(
              StickerOverlay(id: 'new-sticker', assetId: 'new.png'),
            ),
            AddTimelineClip(
              trackId: 'image',
              clip: TimelineClip.still(
                id: 'new-photo',
                mediaId: 'new-image',
                durationUs: 1000000,
                timelineStartUs: 1000000,
              ),
            ),
            const SetOverlayContent(
              id: 'new-sticker',
              kind: EditorTrackKind.sticker,
              value: 'other.png',
            ),
          ]),
        );
        controller.undo();
        expect(controller.project, same(before));
        controller.redo();
        expect(controller.project.stickerOverlays.last.assetId, 'other.png');
        controller.execute(
          const RemoveSource(mediaId: 'new-text', kind: EditorTrackKind.text),
        );
        expect(controller.project.textOverlays, hasLength(1));
        controller.undo();
        expect(controller.project.textOverlays, hasLength(2));
      },
    );

    test('cross-track move is atomic and rejects wrong kinds/collisions', () {
      controller.execute(
        AddTrack(EditorTrack(id: 'second-text', kind: EditorTrackKind.text)),
      );
      final before = controller.project;
      controller.execute(
        const MoveTimelineClip(
          clipId: 'caption',
          targetTrackId: 'second-text',
          timelineStartUs: 200,
        ),
      );
      expect(controller.project.tracks.last.clips.single.id, 'caption');
      controller.undo();
      expect(controller.project, same(before));
      expect(
        () => controller.execute(
          const MoveTimelineClip(
            clipId: 'caption',
            targetTrackId: 'audio',
            timelineStartUs: 0,
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => controller.execute(
          const MoveTimelineClip(
            clipId: 'left',
            targetTrackId: 'video',
            timelineStartUs: 1,
          ),
        ),
        throwsArgumentError,
      );
      expect(controller.project, same(before));
    });

    test(
      'filter/effect upsert preserves order, split copies them, removal undoes',
      () {
        final filter = EditorFilter(
          id: 'grade',
          name: 'Warm',
          shaderId: 'warm',
          parameters: {'gain': 0.2},
        );
        final effect = EditorEffect(
          id: 'grain',
          effectId: 'grain',
          parameters: {'size': 2},
        );
        controller.execute(SetClipFilter(clipId: 'photo', filter: filter));
        controller.execute(SetClipEffect(clipId: 'photo', effect: effect));
        controller.execute(
          SetClipFilter(
            clipId: 'photo',
            filter: EditorFilter(
              id: 'grade',
              name: 'Warm',
              shaderId: 'warm',
              intensity: 0.5,
            ),
          ),
        );
        expect(clip('photo').filters, hasLength(1));
        expect(clip('photo').filters.single.intensity, 0.5);
        controller.execute(
          const SplitTimelineClip(
            clipId: 'photo',
            atUs: 500000,
            rightClipId: 'photo-right',
          ),
        );
        expect(clip('photo-right').effects.single.effectId, 'grain');
        controller.execute(
          const RemoveClipAdjustment(clipId: 'photo', adjustmentId: 'grade'),
        );
        expect(clip('photo').filters, isEmpty);
        controller.undo();
        expect(clip('photo').filters, hasLength(1));
        expect(() => clip('photo').effects.clear(), throwsUnsupportedError);
        expect(
          () => clip('photo').effects.single.parameters.clear(),
          throwsUnsupportedError,
        );
      },
    );

    test(
      'source removal protects references and explicitly cascades transitions',
      () {
        final before = controller.project;
        expect(
          () => controller.execute(
            const RemoveSource(mediaId: 'video', kind: EditorTrackKind.video),
          ),
          throwsStateError,
        );
        controller.execute(
          const RemoveSource(
            mediaId: 'video',
            kind: EditorTrackKind.video,
            removePlacements: true,
          ),
        );
        expect(controller.project.videoClips, isEmpty);
        expect(controller.project.tracks.first.clips, isEmpty);
        expect(controller.project.tracks.first.transitions, isEmpty);
        controller.undo();
        expect(controller.project, same(before));
      },
    );

    test('transitions can be removed/replaced and cannot become dangling', () {
      final before = controller.project;
      expect(
        () => controller.execute(const RemoveTimelineClip('left')),
        throwsArgumentError,
      );
      controller.execute(
        const RemoveTransition(trackId: 'video', transitionId: 'cut'),
      );
      controller.execute(
        SetTransition(
          trackId: 'video',
          transition: EditorTransition(
            id: 'new',
            fromClipId: 'left',
            toClipId: 'right',
            effectId: 'wipe',
            durationUs: 100000,
          ),
        ),
      );
      expect(
        controller.project.tracks.first.transitions.single.effectId,
        'wipe',
      );
      controller.undo();
      controller.undo();
      expect(controller.project, same(before));
    });

    test('frame-snapped split preserves the project timebase', () {
      controller.execute(
        const SplitTimelineClipAtFrame(
          clipId: 'photo',
          frame: 10,
          rightClipId: 'next',
        ),
      );
      expect(
        clip('next').timelineStartUs,
        controller.project.timebase.timeAtFrame(10),
      );
      expect(clip('photo').timelineEndUs, clip('next').timelineStartUs);
    });

    test('invalid commands preserve both the project and history', () {
      final before = controller.project;
      final invalid = <EditorCommand>[
        const SetStillDuration(clipId: 'left', durationUs: 1),
        const SetStillDuration(clipId: 'caption', durationUs: 0),
        const SetOverlayContent(
          id: 'text',
          kind: EditorTrackKind.text,
          value: '',
        ),
        const SetOverlayContent(
          id: 'missing',
          kind: EditorTrackKind.sticker,
          value: 'x',
        ),
        const RemoveSource(mediaId: 'missing', kind: EditorTrackKind.image),
        const MoveTimelineClip(
          clipId: 'missing',
          targetTrackId: 'text',
          timelineStartUs: 0,
        ),
        const MoveTimelineClip(
          clipId: 'caption',
          targetTrackId: 'missing',
          timelineStartUs: 0,
        ),
        const RemoveClipAdjustment(clipId: 'photo', adjustmentId: 'missing'),
        const RemoveTransition(trackId: 'video', transitionId: 'missing'),
        EditTimelineClip(clipId: 'photo', speed: PlaybackRate(2)),
        const EditTimelineClip(clipId: 'caption', volume: 0),
        SetClipEffect(
          clipId: 'sound',
          effect: EditorEffect(id: 'x', effectId: 'blur'),
        ),
        SetTransition(
          trackId: 'video',
          transition: EditorTransition(
            id: 'bad',
            fromClipId: 'right',
            toClipId: 'left',
            effectId: 'x',
            durationUs: 1,
          ),
        ),
        SetTransition(
          trackId: 'video',
          transition: EditorTransition(
            id: 'cut',
            fromClipId: 'left',
            toClipId: 'right',
            effectId: 'x',
            durationUs: 3000000,
          ),
        ),
      ];
      for (final command in invalid) {
        expect(
          () => controller.execute(command),
          throwsArgumentError,
          reason: '$command',
        );
        expect(controller.project, same(before));
        expect(controller.state.canUndo, isFalse);
      }
    });

    test(
      'mixed edits round-trip through JSON and undo/redo in reverse order',
      () {
        final original = codec.encode(controller.project);
        final random = Random(42);
        for (var i = 0; i < 40; i++) {
          controller.execute(
            EditTimelineClip(
              clipId: 'caption',
              timelineStartUs: random.nextInt(1000000),
              transform: EditorTransform(
                x: random.nextDouble(),
                y: random.nextDouble(),
                scaleX: 0.1 + random.nextDouble(),
              ),
            ),
          );
          final encoded = codec.encode(controller.project);
          expect(codec.encode(codec.decode(encoded)), encoded);
        }
        final last = codec.encode(controller.project);
        for (var i = 0; i < 40; i++) {
          controller.undo();
        }
        expect(codec.encode(controller.project), original);
        for (var i = 0; i < 40; i++) {
          controller.redo();
        }
        expect(codec.encode(controller.project), last);
      },
    );
  });

  test(
    'transform and transition constructors reject nonfinite/invalid values',
    () {
      for (final make in <Object Function()>[
        () => EditorTransform(x: double.nan),
        () => EditorTransform(scaleX: 0),
        () => EditorTransform(scaleY: -1),
        () => EditorTransform(rotation: double.infinity),
        () => EditorTransform(opacity: 1.1),
        () => EditorTransform(opacity: -0.1),
        () => EditorTransition(
          id: '',
          fromClipId: 'a',
          toClipId: 'b',
          effectId: 'x',
          durationUs: 1,
        ),
        () => EditorTransition(
          id: 't',
          fromClipId: 'a',
          toClipId: 'a',
          effectId: 'x',
          durationUs: 1,
        ),
        () => EditorTransition(
          id: 't',
          fromClipId: 'a',
          toClipId: 'b',
          effectId: 'x',
          durationUs: 0,
        ),
      ]) {
        expect(make, throwsArgumentError);
      }
    },
  );

  test('v2 round-trips every supported field including adjustments', () {
    var project = fullProject();
    project = SetClipFilter(
      clipId: 'caption',
      filter: EditorFilter(
        id: 'f',
        name: 'Grade',
        shaderId: 'grade',
        intensity: 0.25,
        parameters: {'exposure': 1.2},
      ),
    ).apply(project);
    project = SetClipEffect(
      clipId: 'star',
      effect: EditorEffect(
        id: 'e',
        effectId: 'glow',
        intensity: 0.7,
        parameters: {'radius': 8},
      ),
    ).apply(project);
    final encoded = codec.encode(project);
    expect(codec.encode(codec.decode(encoded)), encoded);
  });

  test(
    'v1 fixture migrates preserving all original fields, and saves as v2',
    () async {
      final legacy = await File('test/fixtures/project_v1.json').readAsString();
      final migrated = codec.decode(legacy);
      expect(migrated.videoClips.single.sourcePath, 'media/original.mp4');
      expect(migrated.textOverlays.single.text, 'Legacy title');
      expect(migrated.timebase.numerator, 2997);
      final clip = migrated.tracks.single.clips.single;
      expect(clip.sourceInUs, 1000000);
      expect(clip.timelineStartUs, 2000000);
      expect(clip.durationUs, 4000000);
      expect(clip.volume, 0.5);
      expect(clip.transform, EditorTransform.identity);
      expect(clip.effects, isEmpty);
      final encoded = codec.encode(migrated);
      expect(jsonDecode(encoded)['schemaVersion'], 2);
      expect(codec.encode(codec.decode(encoded)), encoded);
    },
  );

  test('v2 rejects corrupt new fields and unknown future schemas', () {
    final mutations = <void Function(dynamic)>[
      (d) => d['schemaVersion'] = 3,
      (d) => d['project'].remove('timebase'),
      (d) => d['project']['timebase']['denominator'] = 0,
      (d) => d['project']['tracks'][0].remove('transitions'),
      (d) => d['project']['tracks'][0]['clips'][0]['transform']['scaleX'] = 0,
      (d) => d['project']['tracks'][0]['clips'][0]['effects'] = [null],
      (d) => d['project']['tracks'][0]['transitions'][0]['parameters'] = {
        'a': 'bad',
      },
      (d) => d['project']['imageClips'] = [],
    ];
    for (final mutate in mutations) {
      final doc = jsonDecode(codec.encode(fullProject()));
      mutate(doc);
      expect(() => codec.decode(jsonEncode(doc)), throwsFormatException);
    }
  });
}
