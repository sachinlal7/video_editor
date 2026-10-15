import '../models/editor_project.dart';
import '../models/editor_transform.dart';
import 'editor_timeline.dart';
import '../effects/editor_effect_registry.dart';

/// Single-video-track cut/effect plan. Later-phase features must never be silently
/// dropped from the preview. Times remain integer microseconds until playback.
final class EditorComposition {
  EditorComposition(EditorProject project) {
    final populated = project.tracks.where((t) => t.clips.isNotEmpty).toList();
    if (populated.length != 1 ||
        populated.single.kind != EditorTrackKind.video ||
        populated.single.transitions.isNotEmpty) {
      throw UnsupportedError(
        'Timeline preview requires one video track without transitions. Layered visuals and audio mixing belong to later phases.',
      );
    }
    final track = populated.single;
    if (track.clips.length > 256 ||
        project.durationUs > 24 * 60 * 60 * 1000000) {
      throw UnsupportedError('Preview supports up to 256 clips and 24 hours.');
    }
    for (final clip in track.clips) {
      final speed = clip.speed.numerator / clip.speed.denominator;
      EditorEffectRegistry.chain(clip.filters, clip.effects);
      if (clip.transform != EditorTransform.identity ||
          speed < 0.25 ||
          speed > 4 ||
          clip.durationUs < 1000) {
        throw UnsupportedError(
          'Preview supports cuts, GPU effects, trims, volume and 0.25–4× speed; transforms and sub-millisecond clips are not supported.',
        );
      }
    }
    clips = track.clips;
    paths = {
      for (final source in project.videoClips) source.id: source.sourcePath,
    };
  }
  late final List<TimelineClip> clips;
  late final Map<String, String> paths;
}
