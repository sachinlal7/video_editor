import '../models/editor_effect.dart';
import '../models/editor_export.dart';
import '../models/editor_media.dart';
import '../models/editor_project.dart';
import '../models/editor_playback.dart';
import '../models/editor_media_strip.dart';
import '../timeline/editor_composition.dart';

abstract interface class EditorPlatform {
  Stream<EditorPlayback> get playback;
  String? get previewSessionId;
  Future<void> initialize(EditorProject project);
  Future<void> dispose();
  Future<EditorMediaMetadata> openMedia(String path);
  Future<EditorMediaMetadata> openComposition(EditorComposition composition);
  Future<EditorMediaStrip> loadMediaStrip(
    String path,
    int startUs,
    int endUs,
    int thumbnailCount,
    int requestId,
  );
  Future<void> cancelMediaStrip(int requestId);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> applyEffect(EditorEffect effect);
  Future<void> removeEffect(String effectId);
  Future<List<String>> supportedEffects();
  Future<String> startExport(EditorExportSettings settings);
  Future<void> cancelExport(String exportId);
}
