/// A reusable video source; TimelineClip supplies its placements and trim ranges.
final class VideoClip {
  const VideoClip({required this.id, required this.sourcePath});
  final String id;
  final String sourcePath;
}

/// A reusable audio source; TimelineClip supplies its placements and trim ranges.
final class AudioClip {
  const AudioClip({required this.id, required this.sourcePath});
  final String id;
  final String sourcePath;
}

/// A reusable still-image source; placements define its display interval.
final class ImageClip {
  const ImageClip({required this.id, required this.sourcePath});
  final String id;
  final String sourcePath;
}

/// A reusable text definition; placement timing and transforms live on the track.
final class TextOverlay {
  const TextOverlay({required this.id, required this.text});
  final String id;
  final String text;
}

/// An image or animated asset placed over project video.
final class StickerOverlay {
  const StickerOverlay({required this.id, required this.assetId});
  final String id;
  final String assetId;
}

/// Metadata read by the native media layer.
final class EditorMediaMetadata {
  const EditorMediaMetadata({
    required this.path,
    required this.duration,
    required this.width,
    required this.height,
    required this.hasAudio,
    this.frameRate,
  });

  final String path;
  final Duration duration;
  final int width;
  final int height;
  final bool hasAudio;
  final double? frameRate;
}
