/// Native source-media time, not the edited project timeline.
enum EditorPlaybackStatus {
  idle,
  loading,
  ready,
  playing,
  paused,
  ended,
  failed,
}

final class EditorPlayback {
  const EditorPlayback({
    this.status = EditorPlaybackStatus.idle,
    this.position = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.errorMessage,
  });

  final EditorPlaybackStatus status;
  final Duration position;
  final Duration bufferedPosition;
  final String? errorMessage;
  bool get isPlaying => status == EditorPlaybackStatus.playing;
}
