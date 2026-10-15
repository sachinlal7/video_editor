import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vn_editor/vn_editor.dart';
import 'package:vn_editor_example/playback_example.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('200-clip timeline scroll with bounded native previews', (
    tester,
  ) async {
    final source = await copySampleVideo();
    final project = EditorProject(
      id: 'Timeline profile',
      width: 640,
      height: 360,
      frameRate: 30,
      videoClips: [VideoClip(id: 'source', sourcePath: source.path)],
      tracks: [
        EditorTrack(
          id: 'Video',
          kind: EditorTrackKind.video,
          clips: [
            for (var i = 0; i < 200; i++)
              TimelineClip(
                id: 'Clip $i',
                mediaId: 'source',
                sourceDurationUs: 8000000,
                sourceOutUs: 1000000,
                timelineStartUs: i * 1000000,
              ),
          ],
        ),
      ],
    );
    final editor = EditorController(project: project);
    await editor.initialize();
    await editor.openMedia(source.path);
    addTearDown(editor.close);
    await tester.pumpWidget(
      MaterialApp(
        home: VnEditor(project: project, controller: editor),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    final tracks = find.byWidgetPredicate(
      (w) =>
          w is SingleChildScrollView &&
          w.scrollDirection == Axis.horizontal &&
          w.controller != null,
    );
    expect(tracks, findsOneWidget);
    await binding.watchPerformance(() async {
      for (var i = 0; i < 12; i++) {
        await tester.fling(tracks, Offset(i < 6 ? -260 : 260, 0), 600);
        await tester.pumpAndSettle();
      }
    }, reportKey: 'timeline_scroll');
    expect(editor.project, same(project));
    expect(editor.state.canUndo, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await editor.close();
  });
}
