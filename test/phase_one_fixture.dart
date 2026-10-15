import 'package:vn_editor/vn_editor.dart';

EditorProject fullProject() => EditorProject(
  id: 'full',
  width: 1920,
  height: 1080,
  frameRate: 30000 / 1001,
  timebase: EditorFrameRate(30000, 1001),
  videoClips: const [VideoClip(id: 'video', sourcePath: 'media/video.mp4')],
  audioClips: const [AudioClip(id: 'audio', sourcePath: 'media/audio.wav')],
  imageClips: const [ImageClip(id: 'image', sourcePath: 'media/image.jpg')],
  textOverlays: const [TextOverlay(id: 'text', text: 'Title 👋')],
  stickerOverlays: const [
    StickerOverlay(id: 'sticker', assetId: 'assets/star.png'),
  ],
  tracks: [
    EditorTrack(
      id: 'video',
      kind: EditorTrackKind.video,
      clips: [
        TimelineClip(
          id: 'left',
          mediaId: 'video',
          sourceDurationUs: 4000000,
          sourceOutUs: 2000000,
        ),
        TimelineClip(
          id: 'right',
          mediaId: 'video',
          sourceDurationUs: 4000000,
          sourceInUs: 2000000,
          sourceOutUs: 4000000,
          timelineStartUs: 2000000,
        ),
      ],
      transitions: [
        EditorTransition(
          id: 'cut',
          fromClipId: 'left',
          toClipId: 'right',
          effectId: 'dissolve',
          durationUs: 500000,
          parameters: {'curve': 1},
        ),
      ],
    ),
    EditorTrack(
      id: 'audio',
      kind: EditorTrackKind.audio,
      clips: [
        TimelineClip(
          id: 'sound',
          mediaId: 'audio',
          sourceDurationUs: 4000000,
          sourceOutUs: 4000000,
        ),
      ],
    ),
    EditorTrack(
      id: 'image',
      kind: EditorTrackKind.image,
      clips: [
        TimelineClip.still(id: 'photo', mediaId: 'image', durationUs: 1000000),
      ],
    ),
    EditorTrack(
      id: 'text',
      kind: EditorTrackKind.text,
      clips: [
        TimelineClip.still(
          id: 'caption',
          mediaId: 'text',
          durationUs: 1000000,
          transform: EditorTransform(
            x: 0.2,
            y: 0.8,
            scaleX: 0.5,
            scaleY: 0.75,
            rotation: 0.2,
            opacity: 0.9,
          ),
        ),
      ],
    ),
    EditorTrack(
      id: 'sticker',
      kind: EditorTrackKind.sticker,
      clips: [
        TimelineClip.still(id: 'star', mediaId: 'sticker', durationUs: 2000000),
      ],
    ),
  ],
);
