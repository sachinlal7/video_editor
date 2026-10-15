/// Output settings for a native export job.
final class EditorExportSettings {
  EditorExportSettings({
    required this.outputPath,
    this.width = 1080,
    this.height = 1920,
    this.frameRate = 30,
    this.videoBitrate = 12000000,
    this.videoCodec = 'h264',
    this.container = 'mp4',
  }) {
    if (outputPath.trim().isEmpty) {
      throw ArgumentError.value(outputPath, 'outputPath', 'Must not be empty.');
    }
    if (videoCodec.trim().isEmpty || container.trim().isEmpty) {
      throw ArgumentError('Codec and container must not be empty.');
    }
    if (width <= 0 || height <= 0 || frameRate <= 0 || videoBitrate <= 0) {
      throw ArgumentError(
        'Export dimensions, frame rate, and bitrate must be positive.',
      );
    }
  }

  final String outputPath;
  final int width;
  final int height;
  final int frameRate;
  final int videoBitrate;
  final String videoCodec;
  final String container;
}

/// Metadata returned after a successful export.
final class EditorExportResult {
  const EditorExportResult({
    required this.path,
    required this.duration,
    required this.width,
    required this.height,
    required this.frameRate,
  });

  final String path;
  final Duration duration;
  final int width;
  final int height;
  final int frameRate;
}
