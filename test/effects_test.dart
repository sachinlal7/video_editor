import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vn_editor/vn_editor.dart';
import 'package:vn_editor/src/api/editor_effect_panel.dart';
import 'package:vn_editor/src/timeline/editor_composition.dart';
import 'fake_editor_platform.dart';
import 'timeline_view_test.dart' show timelineProject;

void main() {
  test(
    'generated catalog agrees with source, defaults and parameter bounds',
    () {
      final source = jsonDecode(
        File('shaders/catalog.json').readAsStringSync(),
      );
      expect(EditorEffectRegistry.definitions.length, 13);
      expect(
        (source as List).map((d) => d['id']),
        EditorEffectRegistry.definitions.map((d) => d.id),
      );
      expect(
        EditorEffectRegistry.definitions.map((d) => d.id).toSet().length,
        13,
      );
      for (final definition in EditorEffectRegistry.definitions) {
        EditorEffectRegistry.validate(definition.create());
        for (final p in definition.parameters.entries) {
          for (final v in [p.value.min, p.value.max, p.value.defaultValue]) {
            expect(
              () => definition.create(parameters: {p.key: v}),
              returnsNormally,
            );
          }
          for (final v in [
            p.value.min - 1,
            p.value.max + 1,
            double.nan,
            double.infinity,
          ]) {
            expect(
              () => definition.create(parameters: {p.key: v}),
              throwsArgumentError,
            );
          }
        }
        expect(
          () => definition.create(parameters: {'unknown': 1}),
          throwsArgumentError,
        );
        expect(() => definition.create(intensity: -1), throwsArgumentError);
      }
      expect(
        () => EditorEffectRegistry.definition('unknown'),
        throwsUnsupportedError,
      );
      expect(
        () => EditorEffectRegistry.definition(
          'lut',
        ).create(parameters: {'preset': .5}),
        throwsArgumentError,
      );
    },
  );

  test('filters precede effects, chain is bounded and immutable', () {
    final filter = EditorFilter(id: 'grade', name: 'Grade', shaderId: 'lut');
    final effect = EditorEffect(id: 'v', effectId: 'vignette');
    final chain = EditorEffectRegistry.chain([filter], [effect]);
    expect(chain.map((e) => e.effectId), ['lut', 'vignette']);
    expect(() => chain.clear(), throwsUnsupportedError);
    expect(
      () => EditorEffectRegistry.chain([], List.filled(9, effect)),
      throwsUnsupportedError,
    );
    final edited = SetClipEffect(
      clipId: 'First',
      effect: effect,
    ).apply(timelineProject());
    expect(() => EditorComposition(edited), returnsNormally);
    final restored = const EditorProjectCodec().decode(
      const EditorProjectCodec().encode(edited),
    );
    expect(
      restored.tracks.first.clips.first.effects.first.effectId,
      'vignette',
    );
  });

  test('effect edit owns one history action; removal is idempotent', () async {
    final platform = FakeEditorPlatform();
    final editor = EditorController.withPlatform(
      project: timelineProject(),
      platform: platform,
    );
    addTearDown(editor.close);
    await editor.initialize();
    await editor.editEffect('First', null);
    expect(editor.state.canUndo, isFalse);
    await editor.editEffect(
      'First',
      EditorEffect(id: 'editor-adjustment', effectId: 'grayscale'),
    );
    expect(platform.compositionCalls, 1);
    expect(
      editor.project.tracks.first.clips.first.effects.single.effectId,
      'grayscale',
    );
    editor.undo();
    expect(editor.project.tracks.first.clips.first.effects, isEmpty);
    expect(editor.state.canUndo, isFalse);
    editor.redo();
    await editor.editEffect('First', null);
    expect(editor.project.tracks.first.clips.first.effects, isEmpty);
  });

  test(
    'invalid and competing edits cannot mutate history; close cancels seek',
    () async {
      final platform = FakeEditorPlatform();
      final editor = EditorController.withPlatform(
        project: timelineProject(),
        platform: platform,
      );
      await editor.initialize();
      await expectLater(
        editor.editEffect('First', EditorEffect(id: 'x', effectId: 'missing')),
        throwsUnsupportedError,
      );
      expect(editor.state.canUndo, isFalse);
      final gate = Completer<void>();
      platform.compositionGate = gate.future;
      final pending = editor.editEffect(
        'First',
        EditorEffect(id: 'x', effectId: 'grayscale'),
      );
      final failure = expectLater(pending, throwsStateError);
      await expectLater(
        editor.editEffect('First', EditorEffect(id: 'y', effectId: 'vignette')),
        throwsStateError,
      );
      await editor.close();
      gate.complete();
      await failure;
      expect(platform.seekCalls, 0);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'effect panel respects $brightness and 200% text, one slider commit',
      (tester) async {
        final editor = EditorController.withPlatform(
          project: timelineProject(),
          platform: FakeEditorPlatform(),
        );
        addTearDown(() => tester.runAsync(editor.close));
        await tester.runAsync(editor.initialize);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: EditorEffectPanel(controller: editor, clipId: 'First'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Monochrome').last);
        await tester.pumpAndSettle();
        expect(
          editor.project.tracks.first.clips.first.effects.single.effectId,
          'grayscale',
        );
        final slider = tester.widget<Slider>(find.byType(Slider).first);
        slider.onChanged!(.2);
        slider.onChanged!(.4);
        expect(
          editor.project.tracks.first.clips.first.effects.single.intensity,
          1,
        );
        slider.onChangeEnd!(.4);
        await tester.pumpAndSettle();
        expect(
          editor.project.tracks.first.clips.first.effects.single.intensity,
          .4,
        );
        editor.undo();
        expect(
          editor.project.tracks.first.clips.first.effects.single.intensity,
          1,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(editor.close);
      },
    );
  }
}
