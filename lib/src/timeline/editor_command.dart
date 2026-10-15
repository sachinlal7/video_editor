import '../models/editor_media.dart';
import '../models/editor_project.dart';
import '../models/editor_transform.dart';
import '../models/editor_effect.dart';
import 'editor_timeline.dart';

/// A pure edit. Failure leaves the original project unchanged.
abstract interface class EditorCommand {
  EditorProject apply(EditorProject project);
}

/// Swap neighboring placements atomically, preserving their shared outer span
/// and intervening gap. Existing transitions must remain valid or the edit fails.
final class ReorderTimelineClip implements EditorCommand {
  const ReorderTimelineClip(this.clipId, {required this.earlier});
  final String clipId;
  final bool earlier;
  @override
  EditorProject apply(EditorProject project) {
    final track = project.tracks.firstWhere(
      (t) => t.clips.any((c) => c.id == clipId),
      orElse: () => throw ArgumentError('Unknown clip: $clipId'),
    );
    final index = track.clips.indexWhere((c) => c.id == clipId);
    final neighbor = index + (earlier ? -1 : 1);
    if (neighbor < 0 || neighbor >= track.clips.length) return project;
    final left = track.clips[earlier ? neighbor : index];
    final right = track.clips[earlier ? index : neighbor];
    final gap = right.timelineStartUs - left.timelineEndUs;
    return project.copyWith(
      tracks: [
        for (final t in project.tracks)
          if (t != track)
            t
          else
            t.withClips([
              for (final clip in t.clips)
                if (clip == right)
                  clip.copyWith(timelineStartUs: left.timelineStartUs)
                else if (clip == left)
                  clip.copyWith(
                    timelineStartUs:
                        left.timelineStartUs + right.durationUs + gap,
                  )
                else
                  clip,
            ]),
      ],
    );
  }
}

final class AddVideoSource implements EditorCommand {
  const AddVideoSource(this.source);
  final VideoClip source;
  @override
  EditorProject apply(EditorProject project) =>
      project.copyWith(videoClips: [...project.videoClips, source]);
}

final class AddAudioSource implements EditorCommand {
  const AddAudioSource(this.source);
  final AudioClip source;
  @override
  EditorProject apply(EditorProject project) =>
      project.copyWith(audioClips: [...project.audioClips, source]);
}

final class AddImageSource implements EditorCommand {
  const AddImageSource(this.source);
  final ImageClip source;
  @override
  EditorProject apply(EditorProject project) =>
      project.copyWith(imageClips: [...project.imageClips, source]);
}

final class AddTextOverlay implements EditorCommand {
  const AddTextOverlay(this.overlay);
  final TextOverlay overlay;
  @override
  EditorProject apply(EditorProject project) =>
      project.copyWith(textOverlays: [...project.textOverlays, overlay]);
}

final class AddStickerOverlay implements EditorCommand {
  const AddStickerOverlay(this.overlay);
  final StickerOverlay overlay;
  @override
  EditorProject apply(EditorProject project) =>
      project.copyWith(stickerOverlays: [...project.stickerOverlays, overlay]);
}

/// Replaces shared text; every placement of this definition updates together.
final class SetOverlayContent implements EditorCommand {
  const SetOverlayContent({
    required this.id,
    required this.kind,
    required this.value,
  });
  final String id, value;
  final EditorTrackKind kind;
  @override
  EditorProject apply(EditorProject project) {
    if (kind == EditorTrackKind.text &&
        project.textOverlays.any((o) => o.id == id)) {
      return project.copyWith(
        textOverlays: [
          for (final o in project.textOverlays)
            if (o.id == id) TextOverlay(id: id, text: value) else o,
        ],
      );
    }
    if (kind == EditorTrackKind.sticker &&
        project.stickerOverlays.any((o) => o.id == id)) {
      return project.copyWith(
        stickerOverlays: [
          for (final o in project.stickerOverlays)
            if (o.id == id) StickerOverlay(id: id, assetId: value) else o,
        ],
      );
    }
    throw ArgumentError('Unknown overlay or unsupported content kind.');
  }
}

/// Removes only the reference, never the source file. References in use are
/// rejected unless the caller explicitly requests placement removal as well.
final class RemoveSource implements EditorCommand {
  const RemoveSource({
    required this.mediaId,
    required this.kind,
    this.removePlacements = false,
  });
  final String mediaId;
  final EditorTrackKind kind;
  final bool removePlacements;
  @override
  EditorProject apply(EditorProject project) {
    final ids = switch (kind) {
      EditorTrackKind.video => project.videoClips.map((m) => m.id),
      EditorTrackKind.audio => project.audioClips.map((m) => m.id),
      EditorTrackKind.image => project.imageClips.map((m) => m.id),
      EditorTrackKind.text => project.textOverlays.map((m) => m.id),
      EditorTrackKind.sticker => project.stickerOverlays.map((m) => m.id),
    };
    if (!ids.contains(mediaId)) throw ArgumentError('Unknown source: $mediaId');
    final tracks = <EditorTrack>[];
    for (final track in project.tracks) {
      final removed = track.kind == kind
          ? track.clips
                .where((c) => c.mediaId == mediaId)
                .map((c) => c.id)
                .toSet()
          : <String>{};
      if (removed.isNotEmpty && !removePlacements) {
        throw StateError('Source is still used on the timeline.');
      }
      tracks.add(
        EditorTrack(
          id: track.id,
          kind: track.kind,
          clips: track.clips.where((c) => !removed.contains(c.id)).toList(),
          transitions: track.transitions
              .where(
                (t) =>
                    !removed.contains(t.fromClipId) &&
                    !removed.contains(t.toClipId),
              )
              .toList(),
        ),
      );
    }
    return project.copyWith(
      tracks: tracks,
      videoClips: kind == EditorTrackKind.video
          ? project.videoClips.where((m) => m.id != mediaId).toList()
          : null,
      audioClips: kind == EditorTrackKind.audio
          ? project.audioClips.where((m) => m.id != mediaId).toList()
          : null,
      imageClips: kind == EditorTrackKind.image
          ? project.imageClips.where((m) => m.id != mediaId).toList()
          : null,
      textOverlays: kind == EditorTrackKind.text
          ? project.textOverlays.where((m) => m.id != mediaId).toList()
          : null,
      stickerOverlays: kind == EditorTrackKind.sticker
          ? project.stickerOverlays.where((m) => m.id != mediaId).toList()
          : null,
    );
  }
}

final class MoveTimelineClip implements EditorCommand {
  const MoveTimelineClip({
    required this.clipId,
    required this.targetTrackId,
    required this.timelineStartUs,
  });
  final String clipId, targetTrackId;
  final int timelineStartUs;
  @override
  EditorProject apply(EditorProject project) {
    final target = _track(project, targetTrackId);
    final source = project.tracks.firstWhere(
      (t) => t.clips.any((c) => c.id == clipId),
      orElse: () => throw ArgumentError('Unknown clip: $clipId'),
    );
    if (target.kind != source.kind) {
      throw ArgumentError('Cross-track moves require matching kinds.');
    }
    if (source.id == target.id) {
      return EditTimelineClip(
        clipId: clipId,
        timelineStartUs: timelineStartUs,
      ).apply(project);
    }
    final clip = source.clips
        .firstWhere((c) => c.id == clipId)
        .copyWith(timelineStartUs: timelineStartUs);
    // Transitions are deliberately not silently removed; detach them first.
    return project.copyWith(
      tracks: [
        for (final track in project.tracks)
          if (track.id == source.id)
            track.withClips(track.clips.where((c) => c.id != clipId).toList())
          else if (track.id == target.id)
            track.withClips([...track.clips, clip])
          else
            track,
      ],
    );
  }
}

final class SetClipFilter implements EditorCommand {
  const SetClipFilter({required this.clipId, required this.filter});
  final String clipId;
  final EditorFilter filter;
  @override
  EditorProject apply(EditorProject project) => _editClip(
    project,
    clipId,
    (clip) => [
      clip.copyWith(filters: _upsert(clip.filters, filter, (f) => f.id)),
    ],
  );
}

final class SetClipEffect implements EditorCommand {
  const SetClipEffect({required this.clipId, required this.effect});
  final String clipId;
  final EditorEffect effect;
  @override
  EditorProject apply(EditorProject project) => _editClip(
    project,
    clipId,
    (clip) => [
      clip.copyWith(effects: _upsert(clip.effects, effect, (e) => e.id)),
    ],
  );
}

/// Filter/effect IDs share one namespace per placement.
final class RemoveClipAdjustment implements EditorCommand {
  const RemoveClipAdjustment({
    required this.clipId,
    required this.adjustmentId,
  });
  final String clipId, adjustmentId;
  @override
  EditorProject apply(EditorProject project) =>
      _editClip(project, clipId, (clip) {
        if (!clip.filters.any((f) => f.id == adjustmentId) &&
            !clip.effects.any((e) => e.id == adjustmentId)) {
          throw ArgumentError('Unknown filter/effect: $adjustmentId');
        }
        return [
          clip.copyWith(
            filters: clip.filters.where((f) => f.id != adjustmentId).toList(),
            effects: clip.effects.where((e) => e.id != adjustmentId).toList(),
          ),
        ];
      });
}

List<T> _upsert<T>(List<T> items, T item, String Function(T) id) =>
    items.any((old) => id(old) == id(item))
    ? [
        for (final old in items)
          if (id(old) == id(item)) item else old,
      ]
    : [...items, item];

final class SetTransition implements EditorCommand {
  const SetTransition({required this.trackId, required this.transition});
  final String trackId;
  final EditorTransition transition;
  @override
  EditorProject apply(EditorProject project) {
    final track = _track(project, trackId);
    return _replaceTrack(
      project,
      track.withTransitions(
        _upsert(track.transitions, transition, (t) => t.id),
      ),
    );
  }
}

final class RemoveTransition implements EditorCommand {
  const RemoveTransition({required this.trackId, required this.transitionId});
  final String trackId, transitionId;
  @override
  EditorProject apply(EditorProject project) {
    final track = _track(project, trackId);
    if (!track.transitions.any((t) => t.id == transitionId)) {
      throw ArgumentError('Unknown transition.');
    }
    return _replaceTrack(
      project,
      track.withTransitions(
        track.transitions.where((t) => t.id != transitionId).toList(),
      ),
    );
  }
}

final class SplitTimelineClipAtFrame implements EditorCommand {
  const SplitTimelineClipAtFrame({
    required this.clipId,
    required this.frame,
    required this.rightClipId,
  });
  final String clipId, rightClipId;
  final int frame;
  @override
  EditorProject apply(EditorProject project) => SplitTimelineClip(
    clipId: clipId,
    atUs: project.timebase.timeAtFrame(frame),
    rightClipId: rightClipId,
  ).apply(project);
}

/// Static assets have a virtual display interval, which can grow without
/// claiming additional decoded media. Temporal sources still require trimming.
final class SetStillDuration implements EditorCommand {
  const SetStillDuration({required this.clipId, required this.durationUs});
  final String clipId;
  final int durationUs;
  @override
  EditorProject apply(EditorProject project) {
    final track = project.tracks.firstWhere(
      (t) => t.clips.any((c) => c.id == clipId),
      orElse: () => throw ArgumentError('Unknown clip.'),
    );
    if (track.kind == EditorTrackKind.video ||
        track.kind == EditorTrackKind.audio) {
      throw ArgumentError('Use source trim ranges for temporal media.');
    }
    return _editClip(
      project,
      clipId,
      (clip) => [
        clip.copyWith(
          sourceInUs: 0,
          sourceOutUs: durationUs,
          sourceDurationUs: durationUs,
        ),
      ],
    );
  }
}

final class AddTrack implements EditorCommand {
  const AddTrack(this.track);
  final EditorTrack track;
  @override
  EditorProject apply(EditorProject project) =>
      project.copyWith(tracks: [...project.tracks, track]);
}

/// Removes a track and its placements, retaining reusable media references.
final class RemoveTrack implements EditorCommand {
  const RemoveTrack(this.trackId);
  final String trackId;
  @override
  EditorProject apply(EditorProject project) {
    _track(project, trackId);
    return project.copyWith(
      tracks: project.tracks.where((t) => t.id != trackId).toList(),
    );
  }
}

final class AddTimelineClip implements EditorCommand {
  const AddTimelineClip({required this.trackId, required this.clip});
  final String trackId;
  final TimelineClip clip;
  @override
  EditorProject apply(EditorProject project) {
    final track = _track(project, trackId);
    return _replaceTrack(project, track.withClips([...track.clips, clip]));
  }
}

final class RemoveTimelineClip implements EditorCommand {
  const RemoveTimelineClip(this.clipId);
  final String clipId;
  @override
  EditorProject apply(EditorProject project) =>
      _editClip(project, clipId, (_) => []);
}

/// Trim in source time; move in timeline time. Speed changes preserve source
/// bounds and start time; collisions reject the edit rather than ripple others.
final class EditTimelineClip implements EditorCommand {
  const EditTimelineClip({
    required this.clipId,
    this.sourceInUs,
    this.sourceOutUs,
    this.timelineStartUs,
    this.speed,
    this.volume,
    this.transform,
  });
  final String clipId;
  final int? sourceInUs;
  final int? sourceOutUs;
  final int? timelineStartUs;
  final PlaybackRate? speed;
  final double? volume;
  final EditorTransform? transform;
  @override
  EditorProject apply(EditorProject project) => _editClip(
    project,
    clipId,
    (clip) => [
      clip.copyWith(
        sourceInUs: sourceInUs,
        sourceOutUs: sourceOutUs,
        timelineStartUs: timelineStartUs,
        speed: speed,
        volume: volume,
        transform: transform,
      ),
    ],
  );
}

final class SplitTimelineClip implements EditorCommand {
  const SplitTimelineClip({
    required this.clipId,
    required this.atUs,
    required this.rightClipId,
  });
  final String clipId;
  final int atUs;
  final String rightClipId;
  @override
  EditorProject apply(EditorProject project) =>
      _editClip(project, clipId, (clip) {
        if (atUs <= clip.timelineStartUs || atUs >= clip.timelineEndUs) {
          throw ArgumentError('Split must be strictly inside the clip.');
        }
        final sourceSplit =
            clip.sourceInUs +
            clip.speed.sourceOffset(
              atUs - clip.timelineStartUs,
              requireExact: true,
            );
        return [
          clip.copyWith(sourceOutUs: sourceSplit),
          clip.copyWith(
            id: rightClipId,
            sourceInUs: sourceSplit,
            timelineStartUs: atUs,
          ),
        ];
      });
}

/// An atomic group: either every command succeeds or none is recorded.
final class EditorTransaction implements EditorCommand {
  EditorTransaction(List<EditorCommand> commands)
    : commands = List.unmodifiable(commands);
  final List<EditorCommand> commands;
  @override
  EditorProject apply(EditorProject project) {
    var next = project;
    for (final command in commands) {
      next = command.apply(next);
    }
    return next;
  }
}

EditorTrack _track(EditorProject project, String id) =>
    project.tracks.firstWhere(
      (t) => t.id == id,
      orElse: () => throw ArgumentError('Unknown track: $id'),
    );

EditorProject _replaceTrack(EditorProject project, EditorTrack track) =>
    project.copyWith(
      tracks: [
        for (final old in project.tracks)
          if (old.id == track.id) track else old,
      ],
    );

EditorProject _editClip(
  EditorProject project,
  String id,
  List<TimelineClip> Function(TimelineClip) edit,
) {
  for (final track in project.tracks) {
    for (final clip in track.clips) {
      if (clip.id == id) {
        return _replaceTrack(
          project,
          track.withClips([
            for (final old in track.clips)
              if (old.id == id) ...edit(old) else old,
          ]),
        );
      }
    }
  }
  throw ArgumentError('Unknown timeline clip: $id');
}
