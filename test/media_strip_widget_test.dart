import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_editor/vn_editor.dart';
import 'package:vn_editor/src/api/media_strip.dart';
import 'package:vn_editor/src/models/editor_media_strip.dart';
import 'fake_editor_platform.dart';
import 'timeline_view_test.dart' show timelineProject;

void main() {
  testWidgets('media strip renders loading, retry and late-disposal safely', (
    tester,
  ) async {
    final platform = FakeEditorPlatform();
    final editor = EditorController.withPlatform(
      project: timelineProject(),
      platform: platform,
    );
    final gate = Completer<EditorMediaStrip>();
    platform.stripGate = gate.future;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 96,
            child: MediaStrip(
              controller: editor,
              path: '/sample.mp4',
              startUs: 0,
              endUs: 1000000,
              video: true,
              foreground: Colors.purple,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Loading preview…'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Loading preview…')).style?.color,
      Colors.purple,
    );
    gate.completeError(StateError('decoder failed'));
    await tester.pump();
    expect(find.byTooltip('Preview unavailable. Retry'), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.refresh)).color,
      Colors.purple,
    );
    final retry = Completer<EditorMediaStrip>();
    platform.stripGate = retry.future;
    await tester.tap(find.byTooltip('Preview unavailable. Retry'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(platform.cancelledStrips, hasLength(1));
    retry.complete(EditorMediaStrip(thumbnails: [], peaks: [.2]));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.runAsync(editor.close);
  });

  testWidgets('selected media uses the host primary-container foreground', (
    tester,
  ) async {
    final editor = EditorController.withPlatform(
      project: timelineProject(),
      platform: FakeEditorPlatform(),
    );
    final colors = ColorScheme.fromSeed(seedColor: Colors.teal).copyWith(
      onPrimaryContainer: Colors.red,
      onSecondaryContainer: Colors.blue,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: colors),
        home: Scaffold(body: EditorTimeline(controller: editor)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<MediaStrip>(find.byType(MediaStrip)).foreground,
      colors.onSecondaryContainer,
    );
    await tester.tap(find.text('First'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MediaStrip>(find.byType(MediaStrip)).foreground,
      colors.onPrimaryContainer,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(editor.close);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(1024, 768), const Size(768, 1024)]) {
    testWidgets('tablet timeline fits $size with large text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final editor = EditorController.withPlatform(
        project: timelineProject(),
        platform: FakeEditorPlatform(),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: VnEditor(project: editor.project, controller: editor),
        ),
      );
      await tester.pumpAndSettle();
      final error = tester.takeException();
      expect(find.byType(EditorTimeline), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(editor.close);
      expect(error, isNull);
    });
  }
}
