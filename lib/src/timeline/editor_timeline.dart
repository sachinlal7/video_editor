import '../models/editor_effect.dart';
import '../models/editor_transform.dart';

/// Maximum exact JSON integer supported by the project format.
const maxTimelineValue = 9007199254740991;

void validateTimelineInteger(int value, String name, {bool positive = false}) {
  if (value < (positive ? 1 : 0) || value > maxTimelineValue) {
    throw ArgumentError.value(value, name, 'Outside the supported time range.');
  }
}

/// Positive, normalized rational speed. No floating-point time accumulation.
final class PlaybackRate {
  factory PlaybackRate(int numerator, [int denominator = 1]) {
    validateTimelineInteger(numerator, 'numerator', positive: true);
    validateTimelineInteger(denominator, 'denominator', positive: true);
    final divisor = numerator.gcd(denominator);
    return PlaybackRate._(numerator ~/ divisor, denominator ~/ divisor);
  }

  const PlaybackRate._(this.numerator, this.denominator);
  static const normal = PlaybackRate._(1, 1);
  final int numerator;
  final int denominator;

  int timelineDuration(int sourceDurationUs) {
    validateTimelineInteger(sourceDurationUs, 'sourceDurationUs');
    final scaled = BigInt.from(sourceDurationUs) * BigInt.from(denominator);
    final divisor = BigInt.from(numerator);
    final result = (scaled + divisor - BigInt.one) ~/ divisor;
    if (result > BigInt.from(maxTimelineValue)) {
      throw ArgumentError('Timeline duration exceeds the supported range.');
    }
    return result.toInt();
  }

  int sourceOffset(int timelineOffsetUs, {bool requireExact = false}) {
    validateTimelineInteger(timelineOffsetUs, 'timelineOffsetUs');
    final scaled = BigInt.from(timelineOffsetUs) * BigInt.from(numerator);
    final divisor = BigInt.from(denominator);
    if (requireExact && scaled.remainder(divisor) != BigInt.zero) {
      throw ArgumentError('Split must map to an exact source microsecond.');
    }
    final result = scaled ~/ divisor;
    if (result > BigInt.from(maxTimelineValue)) {
      throw ArgumentError('Source time exceeds the supported range.');
    }
    return result.toInt();
  }
}

enum EditorTrackKind { video, audio, image, text, sticker }

/// A placement referencing a VideoClip/AudioClip by [mediaId].
/// Source and timeline intervals are half-open: [start, end).
final class TimelineClip {
  TimelineClip({
    required this.id,
    required this.mediaId,
    required this.sourceDurationUs,
    required this.sourceOutUs,
    this.sourceInUs = 0,
    this.timelineStartUs = 0,
    this.speed = PlaybackRate.normal,
    this.volume = 1,
    this.transform = EditorTransform.identity,
    List<EditorFilter> filters = const [],
    List<EditorEffect> effects = const [],
  }) : filters = List.unmodifiable(filters),
       effects = List.unmodifiable(effects) {
    if (id.trim().isEmpty || mediaId.trim().isEmpty) {
      throw ArgumentError('Clip and media IDs must not be empty.');
    }
    validateTimelineInteger(
      sourceDurationUs,
      'sourceDurationUs',
      positive: true,
    );
    validateTimelineInteger(sourceInUs, 'sourceInUs');
    validateTimelineInteger(sourceOutUs, 'sourceOutUs', positive: true);
    validateTimelineInteger(timelineStartUs, 'timelineStartUs');
    if (sourceOutUs <= sourceInUs || sourceOutUs > sourceDurationUs) {
      throw ArgumentError(
        'Source range must be nonempty and inside the media.',
      );
    }
    if (!volume.isFinite || volume < 0 || volume > 1) {
      throw ArgumentError.value(
        volume,
        'volume',
        'Must be finite and in [0, 1].',
      );
    }
    validateTimelineInteger(timelineEndUs, 'timelineEndUs');
    final ids = <String>{};
    for (final id in [
      ...filters.map((f) => f.id),
      ...effects.map((e) => e.id),
    ]) {
      if (!ids.add(id)) throw ArgumentError('Duplicate filter/effect ID.');
    }
  }

  /// Static media use a virtual source interval; no decoding duration is implied.
  factory TimelineClip.still({
    required String id,
    required String mediaId,
    required int durationUs,
    int timelineStartUs = 0,
    EditorTransform transform = EditorTransform.identity,
  }) => TimelineClip(
    id: id,
    mediaId: mediaId,
    sourceDurationUs: durationUs,
    sourceOutUs: durationUs,
    timelineStartUs: timelineStartUs,
    transform: transform,
  );

  final String id;
  final String mediaId;
  final int sourceDurationUs;
  final int sourceInUs;
  final int sourceOutUs;
  final int timelineStartUs;
  final PlaybackRate speed;
  final double volume;
  final EditorTransform transform;
  final List<EditorFilter> filters;
  final List<EditorEffect> effects;
  int get durationUs => speed.timelineDuration(sourceOutUs - sourceInUs);
  int get timelineEndUs => timelineStartUs + durationUs;

  int sourceTimeAt(int timelineTimeUs) {
    if (timelineTimeUs < timelineStartUs || timelineTimeUs >= timelineEndUs) {
      throw RangeError('Time is outside this clip.');
    }
    return sourceInUs + speed.sourceOffset(timelineTimeUs - timelineStartUs);
  }

  TimelineClip copyWith({
    String? id,
    int? sourceDurationUs,
    int? sourceInUs,
    int? sourceOutUs,
    int? timelineStartUs,
    PlaybackRate? speed,
    double? volume,
    EditorTransform? transform,
    List<EditorFilter>? filters,
    List<EditorEffect>? effects,
  }) => TimelineClip(
    id: id ?? this.id,
    mediaId: mediaId,
    sourceDurationUs: sourceDurationUs ?? this.sourceDurationUs,
    sourceInUs: sourceInUs ?? this.sourceInUs,
    sourceOutUs: sourceOutUs ?? this.sourceOutUs,
    timelineStartUs: timelineStartUs ?? this.timelineStartUs,
    speed: speed ?? this.speed,
    volume: volume ?? this.volume,
    transform: transform ?? this.transform,
    filters: filters ?? this.filters,
    effects: effects ?? this.effects,
  );
}

/// Clips on one track cannot overlap; layers use separate tracks.
final class EditorTrack {
  EditorTrack({
    required this.id,
    required this.kind,
    List<TimelineClip> clips = const [],
    List<EditorTransition> transitions = const [],
  }) : clips = List.unmodifiable(
         [...clips]
           ..sort((a, b) => a.timelineStartUs.compareTo(b.timelineStartUs)),
       ),
       transitions = List.unmodifiable(transitions) {
    if (id.trim().isEmpty) throw ArgumentError('Track ID must not be empty.');
    final ids = <String>{};
    var previousEnd = 0;
    for (final clip in this.clips) {
      if (!ids.add(clip.id)) {
        throw ArgumentError('Duplicate clip ID: ${clip.id}');
      }
      if (clip.timelineStartUs < previousEnd) {
        throw ArgumentError('Clips cannot overlap within a track.');
      }
      previousEnd = clip.timelineEndUs;
    }
    if (kind == EditorTrackKind.audio && transitions.isNotEmpty) {
      throw ArgumentError(
        'Visual transitions cannot be applied to audio tracks.',
      );
    }
    final transitionIds = <String>{};
    final cuts = <String>{};
    for (final transition in transitions) {
      final index = this.clips.indexWhere((c) => c.id == transition.fromClipId);
      if (!transitionIds.add(transition.id) ||
          !cuts.add(transition.fromClipId) ||
          index < 0 ||
          index + 1 >= this.clips.length) {
        throw ArgumentError('Invalid or duplicate transition.');
      }
      final left = this.clips[index];
      final right = this.clips[index + 1];
      if (right.id != transition.toClipId ||
          left.timelineEndUs != right.timelineStartUs ||
          transition.durationUs > left.durationUs ||
          transition.durationUs > right.durationUs) {
        throw ArgumentError(
          'Transitions require adjacent clips and a duration within both clips.',
        );
      }
    }
  }

  final String id;
  final EditorTrackKind kind;
  final List<TimelineClip> clips;
  final List<EditorTransition> transitions;
  EditorTrack withClips(List<TimelineClip> clips) =>
      EditorTrack(id: id, kind: kind, clips: clips, transitions: transitions);
  EditorTrack withTransitions(List<EditorTransition> transitions) =>
      EditorTrack(id: id, kind: kind, clips: clips, transitions: transitions);
}

/// A data-only visual transition centered on an adjacent cut. Its duration
/// occupies floor(duration/2) before the cut and the remainder after it.
final class EditorTransition {
  EditorTransition({
    required this.id,
    required this.fromClipId,
    required this.toClipId,
    required this.durationUs,
    required this.effectId,
    Map<String, double> parameters = const {},
  }) : parameters = Map.unmodifiable(parameters) {
    validateTimelineInteger(durationUs, 'transition duration', positive: true);
    if ([id, fromClipId, toClipId, effectId].any((s) => s.trim().isEmpty) ||
        fromClipId == toClipId ||
        parameters.entries.any(
          (e) => e.key.trim().isEmpty || !e.value.isFinite,
        )) {
      throw ArgumentError('Invalid transition definition.');
    }
  }
  final String id, fromClipId, toClipId, effectId;
  final int durationUs;
  final Map<String, double> parameters;
}
