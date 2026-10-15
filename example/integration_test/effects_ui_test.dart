import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vn_editor_example/playback_example.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final brightness in Brightness.values) {
    testWidgets('native effect controls $brightness', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const PlaybackExample(),
        ),
      );
      for (
        var i = 0;
        i < 150 && find.byKey(const ValueKey('Fast cut')).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.byKey(const ValueKey('Fast cut')));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byTooltip('Clip effects'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Color grade LUT'), findsOneWidget);
      expect(find.text('LUT: Vintage'), findsOneWidget);
      debugPrint('PHASE4_CAPTURE_${brightness.name}');
      const capture = bool.fromEnvironment('CAPTURE_UI');
      if (capture) await tester.pump(const Duration(seconds: 20));
      await tester.tap(find.byTooltip('Close effects'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
