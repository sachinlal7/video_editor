import 'dart:async';
import 'package:vn_editor/src/models/editor_playback.dart';
import 'package:vn_editor/src/models/editor_effect.dart';
import 'package:vn_editor/src/models/editor_export.dart';
import 'package:vn_editor/src/models/editor_media.dart';
import 'package:vn_editor/src/models/editor_project.dart';
import 'package:vn_editor/src/domain/editor_platform.dart';
import 'package:vn_editor/src/models/editor_media_strip.dart';
import 'package:vn_editor/src/timeline/editor_composition.dart';

final class FakeEditorPlatform implements EditorPlatform {
  final events = StreamController<EditorPlayback>.broadcast();
  @override
  Stream<EditorPlayback> get playback => events.stream;
  @override
  String? get previewSessionId => null;
  int initializeCalls = 0;
  int disposeCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  int seekCalls = 0;
  int openMediaCalls = 0;
  int applyEffectCalls = 0;
  int removeEffectCalls = 0;
  int exportCalls = 0;
  int cancelExportCalls = 0;

  Future<void>? initializationGate;
  Future<void>? playGate;
  Object? disposeError;
  Object? initializeError;
  Object? synchronousInitializeError;
  Object? playError;
  Duration? lastSeek;
  int compositionCalls = 0;
  Future<void>? compositionGate;
  final cancelledStrips = <int>[];
  Future<EditorMediaStrip>? stripGate;
  int stripCalls = 0;

  @override
  Future<EditorMediaMetadata> openComposition(
    EditorComposition composition,
  ) async {
    compositionCalls++;
    await compositionGate;
    return EditorMediaMetadata(
      path: 'vn-editor:timeline',
      duration: Duration(microseconds: composition.clips.last.timelineEndUs),
      width: 640,
      height: 360,
      hasAudio: true,
    );
  }

  @override
  Future<EditorMediaStrip> loadMediaStrip(
    String path,
    int startUs,
    int endUs,
    int thumbnailCount,
    int requestId,
  ) async {
    stripCalls++;
    return await stripGate ?? EditorMediaStrip(thumbnails: [], peaks: []);
  }

  @override
  Future<void> cancelMediaStrip(int requestId) async {
    cancelledStrips.add(requestId);
  }

  @override
  Future<void> initialize(EditorProject project) {
    initializeCalls++;
    if (synchronousInitializeError case final error?) throw error;
    return _finishInitialization();
  }

  Future<void> _finishInitialization() async {
    await initializationGate;
    if (initializeError case final error?) throw error;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await events.close();
    if (disposeError case final error?) throw error;
  }

  @override
  Future<EditorMediaMetadata> openMedia(String path) async {
    openMediaCalls++;
    return EditorMediaMetadata(
      path: path,
      duration: const Duration(seconds: 5),
      width: 1920,
      height: 1080,
      hasAudio: true,
      frameRate: 30,
    );
  }

  @override
  Future<void> play() async {
    playCalls++;
    await playGate;
    if (playError case final error?) throw error;
  }

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> seek(Duration position) async {
    seekCalls++;
    lastSeek = position;
  }

  @override
  Future<void> applyEffect(EditorEffect effect) async => applyEffectCalls++;

  @override
  Future<void> removeEffect(String effectId) async => removeEffectCalls++;
  @override
  Future<List<String>> supportedEffects() async => [
    'color',
    'grayscale',
    'vignette',
  ];

  @override
  Future<String> startExport(EditorExportSettings settings) async {
    exportCalls++;
    return 'export-1';
  }

  @override
  Future<void> cancelExport(String exportId) async => cancelExportCalls++;
}
