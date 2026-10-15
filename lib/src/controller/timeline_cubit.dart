import 'dart:async';

import 'package:bloc/bloc.dart';

import '../models/editor_project.dart';
import '../timeline/editor_command.dart';
import '../timeline/editor_timeline.dart';
import 'editor_controller.dart';

/// Transient timeline presentation state. The editor alone owns project edits.
final class TimelineViewState {
  const TimelineViewState({
    required this.project,
    this.selectedId,
    this.pixelsPerSecond = 64,
    this.positionUs = 0,
    this.error,
  });
  final EditorProject project;
  final String? selectedId;
  final double pixelsPerSecond;
  final int positionUs;
  final String? error;
}

final class TimelineCubit extends Cubit<TimelineViewState> {
  TimelineCubit(this.editor)
    : super(TimelineViewState(project: editor.project)) {
    _subscription = editor.stream.listen(_editorChanged);
  }

  final EditorController editor;
  late final StreamSubscription<EditorState> _subscription;
  int _seekGeneration = 0;

  TimelineClip? get selected {
    for (final track in state.project.tracks) {
      for (final clip in track.clips) {
        if (clip.id == state.selectedId) return clip;
      }
    }
    return null;
  }

  void _update({
    EditorProject? project,
    String? selection,
    bool clearSelection = false,
    double? zoom,
    int? position,
    String? error,
  }) {
    if (isClosed) return;
    final next = project ?? state.project;
    emit(
      TimelineViewState(
        project: next,
        selectedId: clearSelection ? null : selection ?? state.selectedId,
        pixelsPerSecond: zoom ?? state.pixelsPerSecond,
        positionUs: (position ?? state.positionUs).clamp(0, next.durationUs),
        error: error,
      ),
    );
  }

  void _editorChanged(EditorState value) {
    if (value.lifecycle == EditorLifecycleState.disposed) return;
    final project = value.project!;
    final exists = project.tracks.any(
      (t) => t.clips.any((c) => c.id == state.selectedId),
    );
    var position = state.positionUs;
    final clip = selected;
    if (value.isTimeline && !value.timelineDirty) {
      position = value.position.inMicroseconds;
    } else if (!value.isTimeline &&
        identical(project, state.project) &&
        clip != null &&
        _matchesOpenVideo(clip)) {
      final offset = value.position.inMicroseconds - clip.sourceInUs;
      if (offset >= 0 && value.position.inMicroseconds <= clip.sourceOutUs) {
        position = clip.timelineStartUs + clip.speed.timelineDuration(offset);
      }
    }
    if (!identical(project, state.project)) _seekGeneration++;
    _update(
      project: project,
      clearSelection: !exists,
      position: position,
      error: state.error,
    );
  }

  bool _matchesOpenVideo(TimelineClip clip) => state.project.videoClips.any(
    (source) =>
        source.id == clip.mediaId &&
        source.sourcePath == editor.state.media?.path,
  );

  void select(String id) {
    if (!state.project.tracks.any((t) => t.clips.any((c) => c.id == id))) {
      throw ArgumentError('Unknown clip: $id');
    }
    _seekGeneration++;
    _update(selection: id);
    _editorChanged(editor.state);
  }

  void zoom(double value) {
    if (!value.isFinite) throw ArgumentError('Zoom must be finite.');
    _update(zoom: value.clamp(16, 256));
  }

  void previewCursor(int positionUs) => _update(position: positionUs);

  void move(TimelineClip original, int deltaUs) {
    if (selected != original ||
        !editor.project.tracks.any(
          (t) => t.clips.any((c) => identical(c, original)),
        )) {
      return;
    }
    final start = state.project.timebase.snap(
      (original.timelineStartUs + deltaUs).clamp(0, maxTimelineValue),
    );
    if (start == original.timelineStartUs) return;
    try {
      editor.execute(
        EditTimelineClip(clipId: original.id, timelineStartUs: start),
      );
      _update();
    } on ArgumentError {
      _update(
        error: 'Move would overlap another clip or invalidate a transition.',
      );
    } on StateError {
      _update(error: 'The editor is closed.');
    }
  }

  void reorder(bool earlier) {
    final clip = selected;
    if (clip == null) return;
    try {
      editor.execute(ReorderTimelineClip(clip.id, earlier: earlier));
      _update();
    } on ArgumentError {
      _update(error: 'Remove transitions before reordering these clips.');
    } on StateError {
      _update(error: 'The editor is closed.');
    }
  }

  Future<void> scrub(int positionUs) async {
    final generation = ++_seekGeneration;
    final media = editor.state.media;
    final position = positionUs.clamp(0, state.project.durationUs);
    _update(position: position);
    if (editor.state.isTimeline) {
      try {
        await editor.pause();
        if (!isClosed && generation == _seekGeneration) {
          await editor.seek(Duration(microseconds: position));
        }
      } catch (_) {
        _update(error: 'Timeline seek failed. Prepare the timeline again.');
      }
      return;
    }
    final clip = selected;
    if (clip == null ||
        !_matchesOpenVideo(clip) ||
        position < clip.timelineStartUs ||
        position >= clip.timelineEndUs) {
      return;
    }
    try {
      await editor.pause();
      if (isClosed ||
          generation != _seekGeneration ||
          selected != clip ||
          !identical(media, editor.state.media)) {
        return;
      }
      await editor.seek(Duration(microseconds: clip.sourceTimeAt(position)));
    } catch (_) {
      if (generation == _seekGeneration) {
        _update(
          error: 'Could not seek. Reopen the source video and try again.',
        );
      }
    }
  }

  /// Each gesture is one command. External edits invalidate its original clip.
  void trim(
    TimelineClip original, {
    required bool start,
    required int deltaUs,
  }) {
    if (selected != original ||
        deltaUs == 0 ||
        !editor.project.tracks.any(
          (t) => t.clips.any((c) => identical(c, original)),
        )) {
      return;
    }
    try {
      final snapped = state.project.timebase.snap(deltaUs.abs());
      final delta = original.speed.sourceOffset(snapped) * deltaUs.sign;
      final inUs = start
          ? (original.sourceInUs + delta).clamp(0, original.sourceOutUs - 1)
          : original.sourceInUs;
      final outUs = start
          ? original.sourceOutUs
          : (original.sourceOutUs + delta).clamp(
              original.sourceInUs + 1,
              original.sourceDurationUs,
            );
      if (inUs == original.sourceInUs && outUs == original.sourceOutUs) return;
      // Source trims preserve placement start, matching the domain command.
      editor.execute(
        EditTimelineClip(
          clipId: original.id,
          sourceInUs: inUs,
          sourceOutUs: outUs,
        ),
      );
    } on ArgumentError {
      _update(
        error: 'Trim would overlap another clip or invalidate a transition.',
      );
    } on StateError {
      _update(error: 'The editor is closed. Reopen it to make changes.');
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await super.close();
  }
}
