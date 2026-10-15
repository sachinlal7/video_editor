import 'dart:async';
import 'package:bloc/bloc.dart';
import '../models/editor_playback.dart';
import 'package:flutter/foundation.dart';

import '../models/editor_effect.dart';
import '../effects/editor_effect_registry.dart';
import '../models/editor_export.dart';
import '../models/editor_media.dart';
import '../models/editor_project.dart';
import '../platform/editor_platform.dart';
import '../domain/editor_platform.dart';
import '../timeline/editor_command.dart';
import '../timeline/editor_composition.dart';
import 'media_strip_loader.dart';

enum EditorLifecycleState { idle, initializing, ready, failed, disposed }

/// Immutable state emitted by [EditorController].
final class EditorState {
  const EditorState({
    this.lifecycle = EditorLifecycleState.idle,
    this.lastError,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.project,
    this.canUndo = false,
    this.canRedo = false,
    this.playback = const EditorPlayback(),
    this.media,
    this.isTimeline = false,
    this.timelineDirty = false,
  });

  final EditorLifecycleState lifecycle;
  final Object? lastError;
  final bool isPlaying;
  final Duration position;
  final EditorProject? project;
  final bool canUndo;
  final bool canRedo;
  final EditorPlayback playback;
  final EditorMediaMetadata? media;
  final bool isTimeline;
  final bool timelineDirty;

  EditorState copyWith({
    EditorLifecycleState? lifecycle,
    Object? lastError,
    bool clearError = false,
    bool? isPlaying,
    Duration? position,
    EditorProject? project,
    bool? canUndo,
    bool? canRedo,
    EditorPlayback? playback,
    EditorMediaMetadata? media,
    bool clearMedia = false,
    bool? isTimeline,
    bool? timelineDirty,
  }) => EditorState(
    lifecycle: lifecycle ?? this.lifecycle,
    lastError: clearError ? null : lastError ?? this.lastError,
    isPlaying: isPlaying ?? this.isPlaying,
    position: position ?? this.position,
    project: project ?? this.project,
    canUndo: canUndo ?? this.canUndo,
    canRedo: canRedo ?? this.canRedo,
    playback: playback ?? this.playback,
    media: clearMedia ? null : media ?? this.media,
    isTimeline: isTimeline ?? this.isTimeline,
    timelineDirty: timelineDirty ?? this.timelineDirty,
  );
}

/// The editor's single state owner and command gateway.
///
/// The UI observes this BLoC-compatible Cubit while media work is delegated to
/// the platform layer. Host applications do not need to adopt BLoC themselves.
final class EditorController extends Cubit<EditorState> {
  EditorController({required EditorProject project})
    : _platform = PigeonEditorPlatform(),
      super(EditorState(project: project));

  @visibleForTesting
  EditorController.withPlatform({
    required EditorProject project,
    required EditorPlatform platform,
  }) : _platform = platform,
       super(EditorState(project: project));

  EditorProject get project => state.project!;
  static const historyLimit = 100;
  final _undo = <EditorProject>[];
  final _redo = <EditorProject>[];
  final EditorPlatform _platform;
  Future<void>? _initialization;
  Future<void>? _closing;
  StreamSubscription<EditorPlayback>? _playbackSubscription;
  int _mediaRequest = 0;
  int _playIntent = 0;
  Future<void>? _timelineLoading;
  bool _editingEffect = false;
  @internal
  late final mediaStrips = MediaStripLoader(_platform);

  /// Used only by the package's native preview widget.
  @internal
  String? get previewSessionId => _platform.previewSessionId;

  /// Data edits do not require a native player. Timeline preview is invalidated
  /// by edits and rebuilt on demand; media frames never cross platform channels.
  void execute(EditorCommand command) {
    _ensureNotDisposed();
    final next = command.apply(project);
    if (identical(next, project)) return;
    // Project identity/configuration is fixed for the lifetime of a controller.
    if (next.id != project.id ||
        next.width != project.width ||
        next.height != project.height ||
        next.frameRate != project.frameRate ||
        next.timebase.numerator != project.timebase.numerator ||
        next.timebase.denominator != project.timebase.denominator) {
      throw ArgumentError('Commands cannot replace project configuration.');
    }
    _undo.add(project);
    if (_undo.length > historyLimit) _undo.removeAt(0);
    _redo.clear();
    _emitProject(next);
  }

  void undo() {
    _ensureNotDisposed();
    if (_undo.isEmpty) return;
    _redo.add(project);
    _emitProject(_undo.removeLast());
  }

  void redo() {
    _ensureNotDisposed();
    if (_redo.isEmpty) return;
    _undo.add(project);
    _emitProject(_redo.removeLast());
  }

  void _emitProject(EditorProject project) {
    if (state.isTimeline) {
      _playIntent++;
      _mediaRequest++;
      // Pause the stale native plan; the next seek/play rebuilds exactly once.
      unawaited(_platform.pause().catchError((Object _) {}));
    }
    emit(
      state.copyWith(
        project: project,
        canUndo: _undo.isNotEmpty,
        canRedo: _redo.isNotEmpty,
        timelineDirty: state.isTimeline,
        isPlaying: state.isTimeline ? false : null,
      ),
    );
  }

  Future<void> initialize() {
    _ensureNotDisposed();
    return _initialization ??= _initializeOnce();
  }

  Future<void> _initializeOnce() async {
    emit(
      state.copyWith(
        lifecycle: EditorLifecycleState.initializing,
        clearError: true,
      ),
    );
    try {
      _playbackSubscription ??= _platform.playback.listen((playback) {
        if (_closing != null ||
            isClosed ||
            state.timelineDirty ||
            state.lifecycle == EditorLifecycleState.disposed) {
          return;
        }
        emit(
          state.copyWith(
            playback: playback,
            isPlaying: playback.isPlaying,
            position: playback.position,
            lastError: playback.errorMessage,
            clearError: playback.errorMessage == null,
          ),
        );
      });
      await Future<void>.sync(() => _platform.initialize(project));
      if (_closing != null) return;
      emit(
        state.copyWith(lifecycle: EditorLifecycleState.ready, clearError: true),
      );
    } catch (error) {
      if (_closing != null) rethrow;
      emit(
        state.copyWith(
          lifecycle: EditorLifecycleState.failed,
          lastError: error,
        ),
      );
      _initialization = null;
      rethrow;
    }
  }

  Future<EditorMediaMetadata> openMedia(String path) async {
    _ensureReady();
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'path', 'Must not be empty.');
    }
    _playIntent++;
    return _open(() => _platform.openMedia(path), timeline: false);
  }

  /// Prepare the current single-track cut/effect timeline, paused.
  /// Unsupported later-phase features fail explicitly, before replacing media.
  Future<void> prepareTimeline() {
    _ensureReady();
    if (_timelineLoading != null) return _timelineLoading!;
    if (state.isTimeline &&
        !state.timelineDirty &&
        state.media != null &&
        state.playback.status != EditorPlaybackStatus.failed) {
      return Future.value();
    }
    final plan = EditorComposition(project);
    final future = _open(
      () => _platform.openComposition(plan),
      timeline: true,
    ).then<void>((_) {});
    _timelineLoading = future;
    return future.whenComplete(() {
      if (identical(_timelineLoading, future)) _timelineLoading = null;
    });
  }

  Future<EditorMediaMetadata> _open(
    Future<EditorMediaMetadata> Function() open, {
    required bool timeline,
  }) async {
    final request = ++_mediaRequest;
    emit(
      state.copyWith(
        clearMedia: true,
        clearError: true,
        isPlaying: false,
        position: Duration.zero,
        playback: const EditorPlayback(status: EditorPlaybackStatus.loading),
        isTimeline: timeline,
        timelineDirty: false,
      ),
    );
    try {
      final media = await open();
      if (_closing == null && !isClosed && request == _mediaRequest) {
        emit(state.copyWith(media: media));
      } else {
        throw StateError(
          'Playback preparation was replaced, edited or closed.',
        );
      }
      return media;
    } catch (error) {
      if (_closing == null && !isClosed && request == _mediaRequest) {
        emit(
          state.copyWith(
            lastError: error,
            playback: const EditorPlayback(status: EditorPlaybackStatus.failed),
            isPlaying: false,
          ),
        );
      }
      rethrow;
    }
  }

  Future<void> play() async {
    _ensureReady();
    final intent = ++_playIntent;
    if (state.isTimeline && state.timelineDirty) await prepareTimeline();
    if (_closing != null || isClosed || intent != _playIntent) return;
    await _platform.play();
  }

  Future<void> pause() async {
    _ensureReady();
    _playIntent++;
    await _platform.pause();
  }

  Future<void> seek(Duration position) async {
    _ensureReady();
    _playIntent++;
    if (position.isNegative) {
      throw ArgumentError.value(position, 'position', 'Must not be negative.');
    }
    if (state.isTimeline && state.timelineDirty) await prepareTimeline();
    await _platform.seek(position);
  }

  Future<void> applyEffect(EditorEffect effect) async {
    _ensureReady();
    EditorEffectRegistry.validate(effect);
    await _platform.applyEffect(effect);
  }

  Future<void> removeEffect(String effectId) async {
    _ensureReady();
    if (effectId.trim().isEmpty) {
      throw ArgumentError.value(effectId, 'effectId', 'Must not be empty.');
    }
    await _platform.removeEffect(effectId);
  }

  Future<String> export(EditorExportSettings settings) async {
    _ensureReady();
    if (state.isTimeline && state.timelineDirty) await prepareTimeline();
    return _platform.startExport(settings);
  }

  /// Device/backend-supported renderer-v1 IDs. HDR effects are not supported.
  Future<List<String>> supportedEffects() {
    _ensureReady();
    return _platform.supportedEffects();
  }

  /// Commit one effect edit, rebuild the native plan and restore the cursor.
  Future<void> editEffect(
    String clipId,
    EditorEffect? effect, {
    String instanceId = 'editor-adjustment',
  }) async {
    _ensureReady();
    if (_editingEffect) {
      throw StateError('An effect edit is already in progress.');
    }
    if (effect != null) EditorEffectRegistry.validate(effect);
    final clip = project.tracks
        .expand((t) => t.clips)
        .firstWhere((c) => c.id == clipId);
    if (effect == null &&
        !clip.effects.any((e) => e.id == instanceId) &&
        !clip.filters.any((e) => e.id == instanceId)) {
      return;
    }
    final cursorUs = state.isTimeline ? state.position.inMicroseconds : -1;
    final position = Duration(
      microseconds:
          cursorUs >= clip.timelineStartUs && cursorUs < clip.timelineEndUs
          ? cursorUs
          : clip.timelineStartUs,
    );
    final command = effect == null
        ? RemoveClipAdjustment(clipId: clipId, adjustmentId: instanceId)
        : SetClipEffect(clipId: clipId, effect: effect);
    EditorComposition(command.apply(project));
    _editingEffect = true;
    try {
      execute(command);
      await prepareTimeline();
      await seek(
        Duration(
          microseconds: position.inMicroseconds.clamp(0, project.durationUs),
        ),
      );
    } finally {
      _editingEffect = false;
    }
  }

  Future<void> cancelExport(String exportId) async {
    _ensureReady();
    if (exportId.trim().isEmpty) {
      throw ArgumentError.value(exportId, 'exportId', 'Must not be empty.');
    }
    await _platform.cancelExport(exportId);
  }

  void _ensureReady() {
    _ensureNotDisposed();
    if (state.lifecycle != EditorLifecycleState.ready) {
      throw StateError('EditorController must be initialized before use.');
    }
  }

  void _ensureNotDisposed() {
    if (isClosed || state.lifecycle == EditorLifecycleState.disposed) {
      throw StateError('EditorController has been disposed.');
    }
  }

  @override
  // super.close() is awaited in _closeOnce, including its error path.
  // ignore: must_call_super
  Future<void> close() => _closing ??= _closeOnce();

  Future<void> _closeOnce() async {
    _playIntent++;
    _undo.clear();
    _redo.clear();
    emit(
      state.copyWith(
        lifecycle: EditorLifecycleState.disposed,
        isPlaying: false,
        playback: const EditorPlayback(),
        canUndo: false,
        canRedo: false,
      ),
    );
    try {
      // Release after pending initialization so it cannot resurrect native state.
      try {
        await _initialization;
      } catch (_) {
        // Initialization failure is reported by initialize(); still release.
      }
      await mediaStrips.close();
      await _platform.dispose();
    } finally {
      await _playbackSubscription?.cancel();
      await super.close();
    }
  }
}
