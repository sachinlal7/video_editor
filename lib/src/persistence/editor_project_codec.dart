import 'dart:convert';

import '../models/editor_media.dart';
import '../models/editor_effect.dart';
import '../models/editor_transform.dart';
import '../timeline/editor_frame_rate.dart';
import '../models/editor_project.dart';
import '../timeline/editor_timeline.dart';

/// Versioned project data only: original media files and undo history are not
/// embedded. Relative source paths are preserved, never automatically opened.
final class EditorProjectCodec {
  const EditorProjectCodec();
  static const schemaVersion = 2;

  String encode(EditorProject project) => jsonEncode({
    'schemaVersion': schemaVersion,
    'project': {
      'id': project.id,
      'width': project.width,
      'height': project.height,
      'frameRate': project.frameRate,
      'timebase': {
        'numerator': project.timebase.numerator,
        'denominator': project.timebase.denominator,
      },
      'imageClips': [
        for (final m in project.imageClips)
          {'id': m.id, 'sourcePath': m.sourcePath},
      ],
      'videoClips': [
        for (final m in project.videoClips)
          {'id': m.id, 'sourcePath': m.sourcePath},
      ],
      'audioClips': [
        for (final m in project.audioClips)
          {'id': m.id, 'sourcePath': m.sourcePath},
      ],
      'textOverlays': [
        for (final m in project.textOverlays) {'id': m.id, 'text': m.text},
      ],
      'stickerOverlays': [
        for (final m in project.stickerOverlays)
          {'id': m.id, 'assetId': m.assetId},
      ],
      'tracks': [
        for (final track in project.tracks)
          {
            'id': track.id,
            'kind': track.kind.name,
            'transitions': [
              for (final t in track.transitions)
                {
                  'id': t.id,
                  'fromClipId': t.fromClipId,
                  'toClipId': t.toClipId,
                  'effectId': t.effectId,
                  'durationUs': t.durationUs,
                  'parameters': t.parameters,
                },
            ],
            'clips': [
              for (final clip in track.clips)
                {
                  'id': clip.id,
                  'mediaId': clip.mediaId,
                  'sourceDurationUs': clip.sourceDurationUs,
                  'sourceInUs': clip.sourceInUs,
                  'sourceOutUs': clip.sourceOutUs,
                  'timelineStartUs': clip.timelineStartUs,
                  'speedNumerator': clip.speed.numerator,
                  'speedDenominator': clip.speed.denominator,
                  'volume': clip.volume,
                  'transform': _encodeTransform(clip.transform),
                  'filters': [
                    for (final f in clip.filters)
                      {
                        'id': f.id,
                        'name': f.name,
                        'shaderId': f.shaderId,
                        'parameters': f.parameters,
                        'intensity': f.intensity,
                      },
                  ],
                  'effects': [
                    for (final e in clip.effects)
                      {
                        'id': e.id,
                        'effectId': e.effectId,
                        'parameters': e.parameters,
                        'intensity': e.intensity,
                      },
                  ],
                },
            ],
          },
      ],
    },
  });

  EditorProject decode(String document) {
    try {
      final root = _object(jsonDecode(document));
      final version = _integer(root, 'schemaVersion');
      if (version == 1) {
        _migrateV1(root);
      } else if (version != schemaVersion) {
        throw FormatException('Unsupported project schema: $version');
      }
      final p = _object(root['project']);
      final timebase = _object(p['timebase']);
      return EditorProject(
        id: _string(p, 'id'),
        width: _integer(p, 'width'),
        height: _integer(p, 'height'),
        frameRate: _number(p, 'frameRate'),
        timebase: EditorFrameRate(
          _integer(timebase, 'numerator'),
          _integer(timebase, 'denominator'),
        ),
        imageClips: [
          for (final m in _objects(p, 'imageClips'))
            ImageClip(
              id: _string(m, 'id'),
              sourcePath: _string(m, 'sourcePath'),
            ),
        ],
        videoClips: [
          for (final m in _objects(p, 'videoClips'))
            VideoClip(
              id: _string(m, 'id'),
              sourcePath: _string(m, 'sourcePath'),
            ),
        ],
        audioClips: [
          for (final m in _objects(p, 'audioClips'))
            AudioClip(
              id: _string(m, 'id'),
              sourcePath: _string(m, 'sourcePath'),
            ),
        ],
        textOverlays: [
          for (final m in _objects(p, 'textOverlays'))
            TextOverlay(id: _string(m, 'id'), text: _string(m, 'text')),
        ],
        stickerOverlays: [
          for (final m in _objects(p, 'stickerOverlays'))
            StickerOverlay(
              id: _string(m, 'id'),
              assetId: _string(m, 'assetId'),
            ),
        ],
        tracks: [
          for (final t in _objects(p, 'tracks'))
            EditorTrack(
              id: _string(t, 'id'),
              kind: _kind(_string(t, 'kind')),
              transitions: [
                for (final v in _objects(t, 'transitions'))
                  EditorTransition(
                    id: _string(v, 'id'),
                    fromClipId: _string(v, 'fromClipId'),
                    toClipId: _string(v, 'toClipId'),
                    effectId: _string(v, 'effectId'),
                    durationUs: _integer(v, 'durationUs'),
                    parameters: _parameters(v['parameters']),
                  ),
              ],
              clips: [
                for (final c in _objects(t, 'clips'))
                  TimelineClip(
                    id: _string(c, 'id'),
                    mediaId: _string(c, 'mediaId'),
                    sourceDurationUs: _integer(c, 'sourceDurationUs'),
                    sourceInUs: _integer(c, 'sourceInUs'),
                    sourceOutUs: _integer(c, 'sourceOutUs'),
                    timelineStartUs: _integer(c, 'timelineStartUs'),
                    speed: PlaybackRate(
                      _integer(c, 'speedNumerator'),
                      _integer(c, 'speedDenominator'),
                    ),
                    volume: _number(c, 'volume'),
                    transform: _decodeTransform(_object(c['transform'])),
                    filters: [
                      for (final f in _objects(c, 'filters'))
                        EditorFilter(
                          id: _string(f, 'id'),
                          name: _string(f, 'name'),
                          shaderId: _string(f, 'shaderId'),
                          parameters: _parameters(f['parameters']),
                          intensity: _number(f, 'intensity'),
                        ),
                    ],
                    effects: [
                      for (final e in _objects(c, 'effects'))
                        EditorEffect(
                          id: _string(e, 'id'),
                          effectId: _string(e, 'effectId'),
                          parameters: _parameters(e['parameters']),
                          intensity: _number(e, 'intensity'),
                        ),
                    ],
                  ),
              ],
            ),
        ],
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid project data: ${error.message}');
    }
  }
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected an object.');
  }
  return value;
}

List<Map<String, dynamic>> _objects(Map<String, dynamic> value, String key) {
  final items = value[key];
  if (items is! List) throw FormatException('Expected list: $key');
  return items.map(_object).toList();
}

String _string(Map<String, dynamic> value, String key) {
  final item = value[key];
  if (item is! String || item.trim().isEmpty) {
    throw FormatException('Expected nonempty string: $key');
  }
  return item;
}

int _integer(Map<String, dynamic> value, String key) {
  final item = value[key];
  if (item is! int || item < 0 || item > maxTimelineValue) {
    throw FormatException('Expected nonnegative exact integer: $key');
  }
  return item;
}

double _number(Map<String, dynamic> value, String key) {
  final item = value[key];
  if (item is! num || !item.isFinite) {
    throw FormatException('Expected finite number: $key');
  }
  return item.toDouble();
}

EditorTrackKind _kind(String value) => switch (value) {
  'video' => EditorTrackKind.video,
  'audio' => EditorTrackKind.audio,
  'image' => EditorTrackKind.image,
  'text' => EditorTrackKind.text,
  'sticker' => EditorTrackKind.sticker,
  _ => throw FormatException('Unknown track kind: $value'),
};

Map<String, double> _encodeTransform(EditorTransform t) => {
  'x': t.x,
  'y': t.y,
  'scaleX': t.scaleX,
  'scaleY': t.scaleY,
  'rotation': t.rotation,
  'opacity': t.opacity,
};

EditorTransform _decodeTransform(Map<String, dynamic> t) => EditorTransform(
  x: _number(t, 'x'),
  y: _number(t, 'y'),
  scaleX: _number(t, 'scaleX'),
  scaleY: _number(t, 'scaleY'),
  rotation: _number(t, 'rotation'),
  opacity: _number(t, 'opacity'),
);

Map<String, double> _parameters(Object? value) {
  final map = _object(value);
  return {for (final key in map.keys) key: _number(map, key)};
}

void _migrateV1(Map<String, dynamic> root) {
  final p = _object(root['project']);
  final timebase = EditorFrameRate.fromDouble(_number(p, 'frameRate'));
  p['timebase'] = {
    'numerator': timebase.numerator,
    'denominator': timebase.denominator,
  };
  p['imageClips'] = <Object>[];
  for (final track in _objects(p, 'tracks')) {
    if (!['video', 'audio'].contains(_string(track, 'kind'))) {
      throw const FormatException('Invalid v1 track kind.');
    }
    track['transitions'] = <Object>[];
    for (final clip in _objects(track, 'clips')) {
      clip['transform'] = _encodeTransform(EditorTransform.identity);
      clip['filters'] = <Object>[];
      clip['effects'] = <Object>[];
    }
  }
  root['schemaVersion'] = EditorProjectCodec.schemaVersion;
}
