import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_editor/src/controller/timeline_cubit.dart';
import 'package:vn_editor/vn_editor.dart';

import 'fake_editor_platform.dart';

EditorProject timelineProject() => EditorProject(
  id: 'Timeline tests',
  width: 640,
  height: 360,
  frameRate: 30,
  videoClips: const [VideoClip(id: 'source', sourcePath: '/sample.mp4')],
  tracks: [
    EditorTrack(
      id: 'Video',
      kind: EditorTrackKind.video,
      clips: [
        TimelineClip(
          id: 'First',
          mediaId: 'source',
          sourceDurationUs: 5000000,
          sourceInUs: 1000000,
          sourceOutUs: 4000000,
          timelineStartUs: 2000000,
        ),
      ],
    ),
  ],
);

void main() {
  late FakeEditorPlatform platform;
  late EditorController editor;
  late TimelineCubit timeline;

  setUp(() {
    platform = FakeEditorPlatform();
    editor = EditorController.withPlatform(
      project: timelineProject(),
      platform: platform,
    );
    timeline = TimelineCubit(editor);
  });
  tearDown(() async {
    await timeline.close();
    await editor.close();
  });

  test('selection validates IDs and zoom is bounded', () {
    expect(() => timeline.select('missing'), throwsArgumentError);
    timeline.select('First');
    timeline.zoom(10000);
    expect(timeline.state.pixelsPerSecond, 256);
    timeline.zoom(-1);
    expect(timeline.state.pixelsPerSecond, 16);
    expect(() => timeline.zoom(double.nan), throwsArgumentError);
  });

  test(
    'one trim creates one undo and stale gestures cannot overwrite edits',
    () async {
      timeline.select('First');
      final original = timeline.selected!;
      timeline.trim(original, start: true, deltaUs: 500000);
      expect(editor.project.tracks.first.clips.first.sourceInUs, 1500000);
      timeline.trim(original, start: true, deltaUs: 1000000);
      expect(editor.project.tracks.first.clips.first.sourceInUs, 1500000);
      editor.undo();
      expect(editor.project.tracks.first.clips.first.sourceInUs, 1000000);
      expect(editor.state.canUndo, isFalse);
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('trim bounds stay nonempty; removing selection clears it', () async {
    timeline.select('First');
    timeline.trim(timeline.selected!, start: true, deltaUs: 10000000);
    final trimmed = editor.project.tracks.first.clips.first;
    expect(trimmed.sourceInUs, trimmed.sourceOutUs - 1);
    editor.execute(const RemoveTimelineClip('First'));
    await Future<void>.delayed(Duration.zero);
    expect(timeline.selected, isNull);
    expect(timeline.state.selectedId, isNull);
    expect(timeline.state.positionUs, 0);
  });

  test(
    'timeline seek maps source in and placement offset; gaps do not seek',
    () async {
      await editor.initialize();
      await editor.openMedia('/sample.mp4');
      timeline.select('First');
      await timeline.scrub(3000000);
      expect(platform.lastSeek, const Duration(seconds: 2));
      expect(platform.pauseCalls, 1);
      await timeline.scrub(1000000);
      expect(platform.seekCalls, 1);
      platform.events.add(
        const EditorPlayback(
          status: EditorPlaybackStatus.playing,
          position: Duration(milliseconds: 2500),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(timeline.state.positionUs, 3500000);
      expect(editor.state.canUndo, isFalse);
    },
  );

  test('latest scrub wins before native seek dispatch', () async {
    await editor.initialize();
    await editor.openMedia('/sample.mp4');
    timeline.select('First');
    final a = timeline.scrub(3000000);
    final b = timeline.scrub(4000000);
    await Future.wait([a, b]);
    expect(platform.seekCalls, 1);
    expect(platform.lastSeek, const Duration(seconds: 3));
  });

  test(
    'selecting a paused open source immediately projects its current time',
    () async {
      await editor.initialize();
      await editor.openMedia('/sample.mp4');
      platform.events.add(
        const EditorPlayback(
          status: EditorPlaybackStatus.paused,
          position: Duration(seconds: 3),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      timeline.select('First');
      expect(timeline.state.positionUs, 4000000);
    },
  );

  test(
    'colliding trim reports an error without changing project or history',
    () async {
      editor.execute(
        AddTimelineClip(
          trackId: 'Video',
          clip: TimelineClip(
            id: 'Next',
            mediaId: 'source',
            sourceDurationUs: 5000000,
            sourceOutUs: 1000000,
            timelineStartUs: 5000000,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      timeline.select('First');
      final before = editor.project;
      timeline.trim(timeline.selected!, start: false, deltaUs: 1000000);
      expect(editor.project, same(before));
      expect(timeline.state.error, contains('overlap'));
      editor.undo();
      expect(editor.project.tracks.first.clips.length, 1);
      expect(editor.state.canUndo, isFalse);
    },
  );

  test(
    'another source is never sought using the selected clip mapping',
    () async {
      await editor.initialize();
      await editor.openMedia('/different.mp4');
      timeline.select('First');
      await timeline.scrub(3000000);
      expect(platform.seekCalls, 0);
    },
  );

  testWidgets(
    'select, trim gesture, undo and zoom work without owning editor',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: EditorTimeline(controller: editor),
            ),
          ),
        ),
      );
      await tester.tap(find.text('First'));
      await tester.pump();
      final handle = find.byKey(const ValueKey('First-start'));
      expect(handle, findsOneWidget);
      await tester.drag(handle, const Offset(40, 0));
      await tester.pump();
      expect(
        editor.project.tracks.first.clips.first.sourceInUs,
        greaterThan(1000000),
      );
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(editor.project.tracks.first.clips.first.sourceInUs, 1000000);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(editor.isClosed, isFalse);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('host $brightness theme and 200% text fit a compact editor', (
      tester,
    ) async {
      tester.view.reset();
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          builder: (_, child) => MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: VnEditor(project: editor.project, controller: editor),
        ),
      );
      await tester.pumpAndSettle();
      final error = tester.takeException();
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        isNull,
      );
      expect(find.byType(EditorTimeline), findsOneWidget);
      expect(
        tester.getRect(find.text('video · Video')).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const ValueKey('First'))).top,
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(editor.close);
      expect(error, isNull);
    });
  }

  testWidgets(
    'accessible trims use one frame at either zoom and announce boundary',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EditorTimeline(controller: editor)),
        ),
      );
      await tester.tap(find.text('First'));
      await tester.pump();
      for (var i = 0; i < 2; i++) {
        final node = tester.getSemantics(
          find.byKey(const ValueKey('First-start')),
        );
        expect(node.value, i == 0 ? '0:01.00' : '0:01.03');
        tester.binding.performSemanticsAction(
          SemanticsActionEvent(
            type: SemanticsAction.increase,
            nodeId: node.id,
            viewId: tester.view.viewId,
          ),
        );
        await tester.pump();
        expect(
          editor.project.tracks.first.clips.first.sourceInUs,
          1000000 + (i + 1) * editor.project.timebase.timeAtFrame(1),
        );
        await tester.tap(find.byTooltip('Zoom in'));
        await tester.pump();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    },
  );

  testWidgets('empty existing track explains the next action', (tester) async {
    editor.execute(const RemoveTimelineClip('First'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorTimeline(controller: editor)),
      ),
    );
    expect(find.text('Add clips to this track.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('long press move commits one edit and undo restores placement', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorTimeline(controller: editor)),
      ),
    );
    final original = editor.project;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('First')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(
      editor.project.tracks.first.clips.first.timelineStartUs,
      greaterThan(2000000),
    );
    editor.undo();
    await tester.pump();
    expect(editor.project, same(original));
    expect(editor.state.canUndo, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
