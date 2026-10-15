import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vn_editor/vn_editor.dart';
import 'package:vn_editor/src/platform/vn_editor_api.g.dart';
import 'package:vn_editor_example/playback_example.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final api = VnEditorHostApi();
  Future<EditorController> create(
    WidgetTester tester, {
    bool timeline = false,
  }) async {
    final file = await copySampleVideo();
    final editor = EditorController(
      project: EditorProject(
        id: 'GPU tests',
        width: timeline ? 1280 : 640,
        height: timeline ? 720 : 360,
        frameRate: 30,
        videoClips: [VideoClip(id: 'source', sourcePath: file.path)],
        tracks: timeline
            ? [
                EditorTrack(
                  id: 'video',
                  kind: EditorTrackKind.video,
                  clips: [
                    TimelineClip(
                      id: 'clip',
                      mediaId: 'source',
                      sourceDurationUs: 8000000,
                      sourceInUs: 2000000,
                      sourceOutUs: 6000000,
                      timelineStartUs: 500000,
                      speed: PlaybackRate(2),
                    ),
                  ],
                ),
              ]
            : [],
      ),
    );
    await editor.initialize();
    addTearDown(editor.close);
    await tester.pumpWidget(
      MaterialApp(
        home: VnEditor(project: editor.project, controller: editor),
      ),
    );
    if (timeline) {
      await editor.prepareTimeline();
    } else {
      await editor.openMedia(file.path);
    }
    await editor.seek(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 700));
    return editor;
  }

  Future<List<double>> sample(
    WidgetTester tester, {
    String? diagnostic,
    double aspect = 16 / 9,
  }) async {
    await tester.pump(const Duration(milliseconds: 600));
    String? captured;
    for (var attempt = 0; attempt < 40 && captured == null; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      try {
        captured = await api.capturePreviewFrame();
      } on PlatformException catch (error) {
        if (error.code != 'no-preview' && error.code != 'capture-failed') {
          rethrow;
        }
      }
    }
    expect(
      captured,
      isNotNull,
      reason: 'Native preview must render a capturable frame',
    );
    final path = captured!;
    if (diagnostic != null && const bool.fromEnvironment('CAPTURE_GPU')) {
      await File(path).copy('${Directory.systemTemp.path}/$diagnostic.png');
    }
    final codec = await ui.instantiateImageCodec(
      await File(path).readAsBytes(),
      targetWidth: 64,
    );
    final frame = await codec.getNextFrame();
    expect(
      frame.image.height,
      closeTo(64 / aspect, 1),
      reason: 'Native surface must fit the display-oriented canvas',
    );
    final data = (await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final values = <double>[];
    for (var y = 8; y < 28; y++) {
      for (var x = 6; x < 58; x++) {
        final i = (y * 64 + x) * 4;
        values.addAll([
          data.getUint8(i) / 255,
          data.getUint8(i + 1) / 255,
          data.getUint8(i + 2) / 255,
        ]);
      }
    }
    frame.image.dispose();
    codec.dispose();
    await File(path).delete();
    return values;
  }

  double chroma(List<double> values) {
    var total = 0.0;
    for (var i = 0; i < values.length; i += 3) {
      total +=
          (values[i] - values[i + 1]).abs() +
          (values[i + 1] - values[i + 2]).abs();
    }
    return total / (values.length / 3);
  }

  testWidgets(
    'GPU effects render actual decoded video; intensity and removal restore color',
    (tester) async {
      final editor = await create(tester);
      expect(
        await editor.supportedEffects(),
        EditorEffectRegistry.definitions.map((d) => d.id).toList(),
      );
      final baseline = chroma(await sample(tester));
      expect(baseline, greaterThan(.2));
      await editor.applyEffect(EditorEffect(id: 'test', effectId: 'grayscale'));
      final gray = chroma(await sample(tester));
      expect(
        gray,
        lessThan(.06),
        reason: 'Real preview pixels must become monochrome',
      );
      await editor.applyEffect(
        EditorEffect(id: 'test', effectId: 'grayscale', intensity: 0),
      );
      expect(chroma(await sample(tester)), closeTo(baseline, .08));
      for (final definition in EditorEffectRegistry.definitions) {
        await editor.applyEffect(definition.create(instanceId: 'test'));
        await editor.play();
        await tester.pump(const Duration(milliseconds: 150));
        await editor.pause();
        await editor.seek(const Duration(seconds: 1));
        expect(
          (await sample(tester)).any((v) => v > .05),
          isTrue,
          reason: definition.id,
        );
        expect(
          editor.state.playback.status,
          isNot(EditorPlaybackStatus.failed),
        );
      }
      await editor.removeEffect('test');
      expect(chroma(await sample(tester)), closeTo(baseline, .08));
    },
  );

  testWidgets(
    'filtered MP4 matches monochrome preview and never overwrites output',
    (tester) async {
      final editor = await create(tester);
      await editor.applyEffect(
        EditorEffect(id: 'proof', effectId: 'grayscale'),
      );
      final before = chroma(await sample(tester));
      expect(before, lessThan(.06));
      final directory = await Directory.systemTemp.createTemp('vn-gpu-proof-');
      addTearDown(() => directory.delete(recursive: true));
      final output = '${directory.path}/proof.mp4';
      final media = editor.state.media!;
      final settings = EditorExportSettings(
        outputPath: output,
        width: media.width,
        height: media.height,
      );
      expect(await editor.export(settings), output);
      expect(await File(output).length(), greaterThan(1000));
      await expectLater(
        editor.export(settings),
        throwsA(isA<PlatformException>()),
      );
      await editor.openMedia(output);
      await editor.seek(const Duration(seconds: 1));
      expect(chroma(await sample(tester)), closeTo(before, .06));
      expect(
        editor.state.media!.duration.inMilliseconds,
        closeTo(media.duration.inMilliseconds, 150),
      );
    },
  );

  testWidgets(
    'invalid GPU definitions leave preview usable; export cancellation recovers',
    (tester) async {
      final editor = await create(tester);
      for (final effect in [
        NativeEffectConfiguration(
          effectId: 'missing',
          parameters: {},
          intensity: 1,
          instanceId: 'bad',
        ),
        NativeEffectConfiguration(
          effectId: 'blur',
          parameters: {'radius': 99},
          intensity: 1,
          instanceId: 'bad',
        ),
        NativeEffectConfiguration(
          effectId: 'lut',
          parameters: {'preset': .5},
          intensity: 1,
          instanceId: 'bad',
        ),
        NativeEffectConfiguration(
          effectId: 'grain',
          parameters: {},
          intensity: double.nan,
          instanceId: 'bad',
        ),
      ]) {
        await expectLater(
          api.applyEffect(effect),
          throwsA(isA<PlatformException>()),
        );
      }
      expect(chroma(await sample(tester)), greaterThan(.2));
      final directory = await Directory.systemTemp.createTemp('vn-gpu-cancel-');
      addTearDown(() => directory.delete(recursive: true));
      final media = editor.state.media!;
      final output = '${directory.path}/cancel.mp4';
      for (final settings in [
        EditorExportSettings(
          outputPath: output,
          width: media.width,
          height: media.height,
          frameRate: 24,
        ),
        EditorExportSettings(
          outputPath: output,
          width: media.width,
          height: media.height,
          videoBitrate: 1000000,
        ),
        EditorExportSettings(
          outputPath: output,
          width: media.width ~/ 2,
          height: media.height ~/ 2,
        ),
      ]) {
        await expectLater(
          editor.export(settings),
          throwsA(isA<PlatformException>()),
        );
        expect(await File(output).exists(), isFalse);
      }
      final exporting = editor.export(
        EditorExportSettings(
          outputPath: output,
          width: media.width,
          height: media.height,
        ),
      );
      final failure = expectLater(exporting, throwsA(isA<PlatformException>()));
      await expectLater(
        editor.cancelExport('${directory.path}/wrong.mp4'),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        editor.export(
          EditorExportSettings(
            outputPath: '${directory.path}/duplicate.mp4',
            width: media.width,
            height: media.height,
          ),
        ),
        throwsA(isA<PlatformException>()),
      );
      await editor.cancelExport(output);
      await failure;
      expect(await File(output).exists(), isFalse);
      await editor.applyEffect(EditorEffect(id: 'okay', effectId: 'grayscale'));
      expect(chroma(await sample(tester)), lessThan(.06));
    },
  );

  testWidgets(
    'every GPU stage matches a trimmed, sped-up timeline proof export',
    (tester) async {
      final editor = await create(tester, timeline: true);
      final directory = await Directory.systemTemp.createTemp(
        'vn-gpu-catalog-',
      );
      addTearDown(() => directory.delete(recursive: true));
      for (final definition in EditorEffectRegistry.definitions) {
        await editor.editEffect(
          'clip',
          definition.create(
            instanceId: 'editor-adjustment',
            parameters: definition.id == 'color'
                ? {'brightness': .2, 'saturation': .4}
                : const {},
          ),
        );
        await editor.seek(const Duration(milliseconds: 1000));
        final preview = await sample(
          tester,
          diagnostic: '${definition.id}-preview',
        );
        final output = '${directory.path}/${definition.id}.mp4';
        await editor.export(
          EditorExportSettings(outputPath: output, width: 1280, height: 720),
        );
        await editor.openMedia(output);
        await editor.seek(const Duration(milliseconds: 1000));
        final encoded = await sample(
          tester,
          diagnostic: '${definition.id}-export',
        );
        var error = 0.0;
        for (var i = 0; i < encoded.length; i++) {
          error += (encoded[i] - preview[i]).abs();
        }
        debugPrint(
          '${definition.id} RGB mean absolute error: ${error / encoded.length}',
        );
        expect(
          error / encoded.length,
          lessThan(.08),
          reason: '${definition.id} preview/export RGB error',
        );
        expect(editor.state.media!.duration.inMilliseconds, closeTo(2500, 150));
        await editor.prepareTimeline();
      }
      await editor.seek(const Duration(milliseconds: 200));
      expect(
        (await sample(tester)).reduce((a, b) => a + b) / 3120,
        lessThan(.03),
        reason: 'Leading gap stays black',
      );
      await editor.editEffect(
        'clip',
        EditorEffect(id: 'editor-adjustment', effectId: 'grayscale'),
      );
      await editor.seek(const Duration(seconds: 1));
      expect(chroma(await sample(tester)), lessThan(.06));
      editor.undo();
      await editor.prepareTimeline();
      await editor.seek(const Duration(seconds: 1));
      expect(chroma(await sample(tester)), greaterThan(.2));
    },
  );

  testWidgets('ordered stages and in-place updates preserve order', (
    tester,
  ) async {
    final editor = await create(tester);
    await editor.applyEffect(EditorEffect(id: 'gray', effectId: 'grayscale'));
    await editor.applyEffect(
      EditorEffect(
        id: 'tint',
        effectId: 'color',
        parameters: {'temperature': 1},
      ),
    );
    expect(chroma(await sample(tester)), greaterThan(.12));
    await editor.applyEffect(
      EditorEffect(id: 'gray', effectId: 'grayscale', intensity: .5),
    );
    expect(chroma(await sample(tester)), greaterThan(.12));
    await editor.removeEffect('gray');
    await editor.applyEffect(EditorEffect(id: 'gray', effectId: 'grayscale'));
    expect(chroma(await sample(tester)), lessThan(.06));
  });

  testWidgets(
    'portrait and rotation survive GPU proof export with audio policy',
    (tester) async {
      final editor = await create(tester);
      final directory = await Directory.systemTemp.createTemp(
        'vn-gpu-portrait-',
      );
      addTearDown(() => directory.delete(recursive: true));
      for (final name in ['silent.mp4', 'rotated.mp4']) {
        final file = await copySampleVideo(name);
        final original = await editor.openMedia(file.path);
        await editor.applyEffect(
          EditorEffect(id: 'portrait', effectId: 'grayscale'),
        );
        await editor.seek(const Duration(seconds: 1));
        final aspect = original.width / original.height;
        final preview = await sample(tester, aspect: aspect);
        expect(preview.any((v) => v > .05), isTrue);
        expect(chroma(preview), lessThan(.06));
        final output = '${directory.path}/$name';
        await editor.export(
          EditorExportSettings(
            outputPath: output,
            width: original.width,
            height: original.height,
          ),
        );
        final encoded = await editor.openMedia(output);
        expect(encoded.width, original.width);
        expect(encoded.height, original.height);
        expect(encoded.hasAudio, original.hasAudio);
        expect(
          encoded.duration.inMilliseconds,
          closeTo(original.duration.inMilliseconds, 150),
        );
        debugPrint('$name proof frame rate: ${encoded.frameRate}');
        await editor.seek(const Duration(seconds: 1));
        final rendered = await sample(tester, aspect: aspect);
        expect(rendered.any((v) => v > .05), isTrue);
        expect(chroma(rendered), lessThan(.06));
      }
    },
  );
}
