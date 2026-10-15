import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vn_editor/vn_editor.dart';
import 'package:vn_editor_example/timeline_example.dart';

void main() {
  test(
    'host example edits, undoes, saves and reopens through public API',
    () async {
      final directory = await Directory.systemTemp.createTemp('vn-host-test-');
      try {
        final restored = await runTimelineExample(
          projectPath: '${directory.path}/project.json',
        );
        expect(restored.tracks.first.clips, hasLength(2));
        expect(restored.durationUs, 5000000);
        final right = restored.tracks.first.clips.last;
        expect(right.sourceInUs, 5000000);
        expect(right.timelineStartUs, 3000000);
        expect(right.volume, 0.5);
        expect(restored.imageClips.single.sourcePath, 'media/photo.jpg');
        expect(restored.tracks.last.clips.single.transform.y, 0.8);
        expect(restored.tracks.last.clips.single.durationUs, 2000000);
        expect(restored.tracks[1].clips.single.filters.single.intensity, 0.5);
        expect(restored.tracks[3].clips.single.effects.single.effectId, 'glow');
        final reopened = EditorController(project: restored);
        expect(reopened.state.canUndo, isFalse);
        await reopened.close();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
