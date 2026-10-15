import 'editor_media.dart';
import '../timeline/editor_timeline.dart';
import '../timeline/editor_frame_rate.dart';
import 'editor_transform.dart';

/// A complete editable project owned by the Dart editing engine.
final class EditorProject {
  EditorProject({
    required this.id,
    required this.width,
    required this.height,
    required this.frameRate,
    EditorFrameRate? timebase,
    List<VideoClip> videoClips = const [],
    List<ImageClip> imageClips = const [],
    List<AudioClip> audioClips = const [],
    List<TextOverlay> textOverlays = const [],
    List<StickerOverlay> stickerOverlays = const [],
    List<EditorTrack> tracks = const [],
  }) : timebase = timebase ?? EditorFrameRate.fromDouble(frameRate),
       videoClips = List.unmodifiable(videoClips),
       imageClips = List.unmodifiable(imageClips),
       audioClips = List.unmodifiable(audioClips),
       textOverlays = List.unmodifiable(textOverlays),
       stickerOverlays = List.unmodifiable(stickerOverlays),
       tracks = List.unmodifiable(tracks) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be empty.');
    }
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Project dimensions must be positive.');
    }
    validateTimelineInteger(width, 'width', positive: true);
    validateTimelineInteger(height, 'height', positive: true);
    if (!frameRate.isFinite || frameRate <= 0) {
      throw ArgumentError.value(
        frameRate,
        'frameRate',
        'Must be finite and greater than zero.',
      );
    }
    if ((this.timebase.framesPerSecond - frameRate).abs() > 1e-9) {
      throw ArgumentError('Frame rate and rational timebase must agree.');
    }
    final mediaIds = <String>{};
    for (final media in [...videoClips, ...audioClips, ...imageClips]) {
      final (String mediaId, String path) = switch (media) {
        VideoClip m => (m.id, m.sourcePath),
        AudioClip m => (m.id, m.sourcePath),
        ImageClip m => (m.id, m.sourcePath),
        _ => throw StateError('Unknown media type.'),
      };
      if (mediaId.trim().isEmpty ||
          path.trim().isEmpty ||
          !mediaIds.add(mediaId)) {
        throw ArgumentError(
          'Media IDs must be unique and media paths nonempty.',
        );
      }
    }
    final overlayIds = <String>{};
    for (final overlay in [...textOverlays, ...stickerOverlays]) {
      final (String overlayId, String value) = switch (overlay) {
        TextOverlay o => (o.id, o.text),
        StickerOverlay o => (o.id, o.assetId),
        _ => throw StateError('Unknown overlay type.'),
      };
      if (overlayId.trim().isEmpty ||
          value.trim().isEmpty ||
          !overlayIds.add(overlayId)) {
        throw ArgumentError(
          'Overlay IDs must be unique and contents nonempty.',
        );
      }
    }
    final trackIds = <String>{};
    final placementIds = <String>{};
    final sourceDurations = <String, int>{};
    final videoIds = videoClips.map((m) => m.id).toSet();
    final audioIds = audioClips.map((m) => m.id).toSet();
    final imageIds = imageClips.map((m) => m.id).toSet();
    final textIds = textOverlays.map((m) => m.id).toSet();
    final stickerIds = stickerOverlays.map((m) => m.id).toSet();
    for (final track in tracks) {
      if (!trackIds.add(track.id)) throw ArgumentError('Duplicate track ID.');
      final allowed = switch (track.kind) {
        EditorTrackKind.video => videoIds,
        EditorTrackKind.audio => audioIds,
        EditorTrackKind.image => imageIds,
        EditorTrackKind.text => textIds,
        EditorTrackKind.sticker => stickerIds,
      };
      for (final clip in track.clips) {
        if (track.kind == EditorTrackKind.audio &&
            (clip.filters.isNotEmpty ||
                clip.effects.isNotEmpty ||
                clip.transform != EditorTransform.identity)) {
          throw ArgumentError(
            'Visual adjustments cannot be applied to audio tracks.',
          );
        }
        final temporal =
            track.kind == EditorTrackKind.video ||
            track.kind == EditorTrackKind.audio;
        final knownDuration = !temporal
            ? clip.sourceDurationUs
            : sourceDurations.putIfAbsent(
                clip.mediaId,
                () => clip.sourceDurationUs,
              );
        if (temporal && knownDuration != clip.sourceDurationUs) {
          throw ArgumentError(
            'Placements of the same source must agree on its duration.',
          );
        }
        if (!temporal &&
            (clip.speed.numerator != clip.speed.denominator ||
                clip.volume != 1)) {
          throw ArgumentError(
            'Static placements do not have playback speed or audio volume.',
          );
        }
        if (!placementIds.add(clip.id) || !allowed.contains(clip.mediaId)) {
          throw ArgumentError(
            'Clip IDs must be unique and reference matching media.',
          );
        }
      }
    }
  }

  factory EditorProject.empty({
    String id = 'untitled',
    required int width,
    required int height,
    required double frameRate,
    EditorFrameRate? timebase,
  }) => EditorProject(
    id: id,
    width: width,
    height: height,
    frameRate: frameRate,
    timebase: timebase,
  );

  final String id;
  final int width;
  final int height;
  final double frameRate;
  final EditorFrameRate timebase;
  final List<VideoClip> videoClips;
  final List<ImageClip> imageClips;
  final List<AudioClip> audioClips;
  final List<TextOverlay> textOverlays;
  final List<StickerOverlay> stickerOverlays;
  final List<EditorTrack> tracks;

  int get durationUs => tracks.fold(
    0,
    (end, track) => track.clips.isEmpty || track.clips.last.timelineEndUs < end
        ? end
        : track.clips.last.timelineEndUs,
  );

  EditorProject copyWith({
    List<VideoClip>? videoClips,
    List<ImageClip>? imageClips,
    List<AudioClip>? audioClips,
    List<TextOverlay>? textOverlays,
    List<StickerOverlay>? stickerOverlays,
    List<EditorTrack>? tracks,
  }) => EditorProject(
    id: id,
    width: width,
    height: height,
    frameRate: frameRate,
    timebase: timebase,
    videoClips: videoClips ?? this.videoClips,
    imageClips: imageClips ?? this.imageClips,
    audioClips: audioClips ?? this.audioClips,
    textOverlays: textOverlays ?? this.textOverlays,
    stickerOverlays: stickerOverlays ?? this.stickerOverlays,
    tracks: tracks ?? this.tracks,
  );
}
