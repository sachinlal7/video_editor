/// Bounded native-generated preview data. Paths are temporary, session-owned
/// JPEG files; peaks are normalized PCM maxima, not audio samples.
final class EditorMediaStrip {
  EditorMediaStrip({
    required List<String> thumbnails,
    required List<double> peaks,
  }) : thumbnails = List.unmodifiable(thumbnails),
       peaks = List.unmodifiable(peaks);
  final List<String> thumbnails;
  final List<double> peaks;
}
