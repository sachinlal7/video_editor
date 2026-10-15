import 'dart:async';
import 'package:flutter/widgets.dart';
import '../models/editor_playback.dart';
import '../models/editor_effect.dart';
import '../models/editor_export.dart';
import '../models/editor_media.dart';
import '../models/editor_project.dart';
import 'vn_editor_api.g.dart';
import '../domain/editor_platform.dart';
import '../models/editor_media_strip.dart';
import '../timeline/editor_composition.dart';
import '../effects/editor_effect_registry.dart';

final class PigeonEditorPlatform
    with WidgetsBindingObserver
    implements EditorPlatform, VnEditorFlutterApi {
  PigeonEditorPlatform({VnEditorHostApi? api})
    : _api = api ?? VnEditorHostApi();

  final VnEditorHostApi _api;
  static PigeonEditorPlatform? _owner;
  static int _nextSession = 0;
  final _playback = StreamController<EditorPlayback>.broadcast();
  int _requestId = 0;
  final String _sessionId =
      '${DateTime.now().microsecondsSinceEpoch}-${_nextSession++}';
  @override
  Stream<EditorPlayback> get playback => _playback.stream;
  @override
  String? get previewSessionId => identical(_owner, this) ? _sessionId : null;

  @override
  Future<void> onPlaybackStateChanged(NativePlaybackEvent event) async {
    if (!identical(_owner, this) ||
        event.sessionId != _sessionId ||
        event.requestId != _requestId ||
        _playback.isClosed) {
      return;
    }
    _playback.add(
      EditorPlayback(
        status: EditorPlaybackStatus.values[event.status.index],
        position: Duration(milliseconds: event.positionMilliseconds),
        bufferedPosition: Duration(
          milliseconds: event.bufferedPositionMilliseconds,
        ),
        errorMessage: event.errorMessage,
      ),
    );
  }

  @override
  Future<void> onExportProgress(NativeExportEvent event) async {}
  @override
  Future<void> onError(NativeEditorError error) async {}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && identical(_owner, this)) {
      // Native players also handle interruptions; never auto-resume on return.
      unawaited(_api.pause().catchError((Object _) {}));
    }
  }

  @override
  Future<void> initialize(EditorProject project) async {
    if (_playback.isClosed) throw StateError('The native adapter is disposed.');
    if (_owner != null) {
      throw StateError(
        'Only one native editor may be active per Flutter engine.',
      );
    }
    _owner = this;
    VnEditorFlutterApi.setUp(this);
    WidgetsBinding.instance.addObserver(this);
    try {
      await _api.initialize(
        NativeProjectConfiguration(
          projectId: project.id,
          width: project.width,
          height: project.height,
          frameRate: project.frameRate,
          sessionId: _sessionId,
        ),
      );
    } catch (_) {
      VnEditorFlutterApi.setUp(null);
      WidgetsBinding.instance.removeObserver(this);
      _owner = null;
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    if (!identical(_owner, this)) {
      await _playback.close();
      return;
    }
    WidgetsBinding.instance.removeObserver(this);
    try {
      await _api.disposeEditor();
    } finally {
      VnEditorFlutterApi.setUp(null);
      _owner = null;
      await _playback.close();
    }
  }

  @override
  Future<EditorMediaMetadata> openMedia(String path) async {
    final metadata = await _api.openMedia(path, ++_requestId);
    return _metadata(metadata);
  }

  EditorMediaMetadata _metadata(NativeMediaMetadata metadata) =>
      EditorMediaMetadata(
        path: metadata.path,
        duration: Duration(milliseconds: metadata.durationMilliseconds),
        width: metadata.width,
        height: metadata.height,
        hasAudio: metadata.hasAudio,
        frameRate: metadata.frameRate,
      );

  @override
  Future<EditorMediaMetadata> openComposition(
    EditorComposition composition,
  ) async => _metadata(
    await _api.openComposition([
      for (final clip in composition.clips)
        NativeTimelineSegment(
          path: composition.paths[clip.mediaId]!,
          sourceInUs: clip.sourceInUs,
          sourceOutUs: clip.sourceOutUs,
          startUs: clip.timelineStartUs,
          durationUs: clip.durationUs,
          speed: clip.speed.numerator / clip.speed.denominator,
          volume: clip.volume,
          effects: EditorEffectRegistry.chain(
            clip.filters,
            clip.effects,
          ).map(_effect).toList(),
        ),
    ], ++_requestId),
  );

  @override
  Future<EditorMediaStrip> loadMediaStrip(
    String path,
    int startUs,
    int endUs,
    int thumbnailCount,
    int requestId,
  ) async {
    final strip = await _api.loadMediaStrip(
      path,
      startUs,
      endUs,
      thumbnailCount,
      requestId,
    );
    return EditorMediaStrip(thumbnails: strip.thumbnails, peaks: strip.peaks);
  }

  @override
  Future<void> cancelMediaStrip(int requestId) =>
      _api.cancelMediaStrip(requestId);

  @override
  Future<void> play() => _api.play();

  @override
  Future<void> pause() => _api.pause();

  @override
  Future<void> seek(Duration position) => _api.seekTo(position.inMilliseconds);

  @override
  Future<void> applyEffect(EditorEffect effect) =>
      _api.applyEffect(_effect(effect));

  NativeEffectConfiguration _effect(EditorEffect effect) =>
      NativeEffectConfiguration(
        instanceId: effect.id,
        effectId: effect.effectId,
        parameters: effect.parameters,
        intensity: effect.intensity,
      );

  @override
  Future<void> removeEffect(String effectId) => _api.removeEffect(effectId);
  @override
  Future<List<String>> supportedEffects() => _api.supportedEffects();

  @override
  Future<String> startExport(EditorExportSettings settings) => _api.startExport(
    NativeExportConfiguration(
      outputPath: settings.outputPath,
      width: settings.width,
      height: settings.height,
      frameRate: settings.frameRate,
      videoBitrate: settings.videoBitrate,
      videoCodec: settings.videoCodec,
      container: settings.container,
    ),
  );

  @override
  Future<void> cancelExport(String exportId) => _api.cancelExport(exportId);
}
