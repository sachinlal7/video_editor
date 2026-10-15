import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vn_editor/vn_editor.dart';
import 'package:vn_editor_example/timeline_example.dart';

// Run twice with --no-uninstall and the same VN_TEST_RUN. The Flutter test
// runner otherwise uninstalls the app (and its saved data) between launches.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('VN_TEST_PHASE');
  const run = String.fromEnvironment('VN_TEST_RUN');

  testWidgets('project survives a separate app launch: $phase', (tester) async {
    expect(['write', 'read'], contains(phase));
    expect(RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(run), isTrue);
    // Test-only sandbox lookup; host apps should use their directory provider.
    expect(Platform.isIOS || Platform.isAndroid, isTrue);
    final documents = Directory(
      '${Directory.systemTemp.parent.path}/${Platform.isIOS ? 'Documents' : 'files'}',
    );
    expect(
      await documents.exists(),
      isTrue,
      reason: 'Expected app-owned document directory.',
    );
    final path = '${documents.path}/vn-editor-restart-$run.json';
    if (phase == 'write') {
      expect(await File(path).exists(), isFalse, reason: 'Use a fresh run ID.');
      await runTimelineExample(projectPath: path);
    } else {
      final loaded = await EditorProjectFile(path).load();
      final controller = EditorController(project: loaded);
      try {
        await controller.initialize();
        expect(loaded.durationUs, 5000000);
        expect(loaded.tracks.last.clips.single.transform.y, 0.8);
        expect(loaded.tracks[1].clips.single.filters.single.intensity, 0.5);
        expect(loaded.tracks[3].clips.single.effects.single.effectId, 'glow');
        expect(controller.state.canUndo, isFalse);
        controller.execute(
          const SetOverlayContent(
            id: 'title-source',
            kind: EditorTrackKind.text,
            value: 'Reopened',
          ),
        );
        controller.undo();
        expect(controller.project.textOverlays.single.text, 'My story');
      } finally {
        await controller.close();
      }
      await File(path).delete();
    }
  });
}
