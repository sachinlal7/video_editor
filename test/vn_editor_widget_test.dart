import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_editor/vn_editor.dart';

import 'fake_editor_platform.dart';

void main() {
  final project = EditorProject.empty(
    id: 'Widget project',
    width: 1080,
    height: 1920,
    frameRate: 30,
  );

  testWidgets('shows the editor foundation after initialization', (
    tester,
  ) async {
    final controller = EditorController.withPlatform(
      project: project,
      platform: FakeEditorPlatform(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VnEditor(project: project, controller: controller),
      ),
    );
    await tester.pump();

    expect(find.text('Widget project'), findsOneWidget);
    expect(find.text('Your project is ready'), findsOneWidget);
    expect(
      find.text('Open a local video with controller.openMedia(path).'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Export'))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.isClosed, isFalse);
    await tester.runAsync(controller.close);
  });

  testWidgets('shows a recoverable error state when initialization fails', (
    tester,
  ) async {
    final platform = FakeEditorPlatform()
      ..initializeError = StateError('native unavailable');
    final controller = EditorController.withPlatform(
      project: project,
      platform: platform,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VnEditor(project: project, controller: controller),
      ),
    );
    await tester.pump();

    expect(find.text('The editor could not start.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    platform.initializeError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Your project is ready'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(controller.close);
  });
}
