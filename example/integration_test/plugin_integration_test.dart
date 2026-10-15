import 'dart:io';

import 'package:flutter/services.dart';
import 'package:vn_editor/vn_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vn_editor_example/main.dart';
import 'package:vn_editor_example/timeline_example.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('timeline edits survive save, controller close, and reopen', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'vn-timeline-integration-',
    );
    try {
      final restored = await runTimelineExample(
        projectPath: '${directory.path}/project.json',
      );
      final reopened = EditorController(project: restored);
      try {
        await reopened.initialize();
        expect(reopened.project.tracks.first.clips, hasLength(2));
        expect(reopened.project.durationUs, 5000000);
        expect(reopened.project.tracks.first.clips.last.volume, 0.5);
        expect(reopened.project.tracks.last.clips.single.transform.y, 0.8);
        expect(reopened.project.tracks.last.clips.single.durationUs, 2000000);
        expect(
          reopened.project.tracks[1].clips.single.filters.single.intensity,
          0.5,
        );
        expect(
          reopened.project.tracks[3].clips.single.effects.single.effectId,
          'glow',
        );
        expect(reopened.state.canUndo, isFalse);
      } finally {
        await reopened.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });

  testWidgets('native lifecycle, unsupported commands, and reopen', (
    tester,
  ) async {
    final project = EditorProject.empty(
      width: 1080,
      height: 1920,
      frameRate: 30,
    );
    final controller = EditorController(project: project);
    await controller.initialize();
    expect(controller.state.lifecycle, EditorLifecycleState.ready);
    await expectLater(
      controller.play(),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'no-media'),
      ),
    );
    await expectLater(
      controller.seek(const Duration(milliseconds: -1)),
      throwsArgumentError,
    );
    await controller.close();
    await controller.close();
    final reopened = EditorController(project: project);
    await reopened.initialize();
    await reopened.close();
  });

  testWidgets('host app opens the native-backed editor shell', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    expect(find.text('Portrait story'), findsOneWidget);
    expect(find.text('Your project is ready'), findsOneWidget);
    expect(
      find.text('Open a local video with controller.openMedia(path).'),
      findsOneWidget,
    );
  });
}
