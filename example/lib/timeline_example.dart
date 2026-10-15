import 'package:vn_editor/vn_editor.dart';

/// Data-only Phase 1 walkthrough. Media paths are illustrative references, not
/// decoded files. [projectPath] is an explicit app-owned document to overwrite.
Future<EditorProject> runTimelineExample({required String projectPath}) async {
  final controller = EditorController(
    project: EditorProject.empty(
      id: 'Timeline example',
      width: 1080,
      height: 1920,
      frameRate: 30,
    ),
  );
  final file = EditorProjectFile(projectPath);
  try {
    controller.execute(
      EditorTransaction([
        const AddVideoSource(
          VideoClip(id: 'source', sourcePath: 'media/demo.mp4'),
        ),
        AddTrack(EditorTrack(id: 'main', kind: EditorTrackKind.video)),
        AddTimelineClip(
          trackId: 'main',
          clip: TimelineClip(
            id: 'clip',
            mediaId: 'source',
            sourceDurationUs: 10000000,
            sourceOutUs: 10000000,
          ),
        ),
      ]),
    );
    controller.execute(
      EditTimelineClip(
        clipId: 'clip',
        sourceInUs: 1000000,
        sourceOutUs: 9000000,
        speed: PlaybackRate(2),
      ),
    );
    controller.execute(
      const SplitTimelineClip(
        clipId: 'clip',
        atUs: 2000000,
        rightClipId: 'right',
      ),
    );
    controller.execute(
      const EditTimelineClip(
        clipId: 'right',
        timelineStartUs: 3000000,
        volume: 0.5,
      ),
    );
    controller.undo();
    controller.redo();
    controller.execute(
      EditorTransaction([
        const AddImageSource(
          ImageClip(id: 'photo-source', sourcePath: 'media/photo.jpg'),
        ),
        const AddTextOverlay(TextOverlay(id: 'title-source', text: 'My story')),
        const AddStickerOverlay(
          StickerOverlay(id: 'sticker-source', assetId: 'assets/star.png'),
        ),
        AddTrack(EditorTrack(id: 'photos', kind: EditorTrackKind.image)),
        AddTrack(EditorTrack(id: 'titles', kind: EditorTrackKind.text)),
        AddTrack(EditorTrack(id: 'stickers', kind: EditorTrackKind.sticker)),
        AddTrack(
          EditorTrack(id: 'second-title-layer', kind: EditorTrackKind.text),
        ),
        AddTimelineClip(
          trackId: 'photos',
          clip: TimelineClip.still(
            id: 'photo',
            mediaId: 'photo-source',
            durationUs: 1000000,
          ),
        ),
        AddTimelineClip(
          trackId: 'titles',
          clip: TimelineClip.still(
            id: 'title',
            mediaId: 'title-source',
            durationUs: 1000000,
          ),
        ),
        AddTimelineClip(
          trackId: 'stickers',
          clip: TimelineClip.still(
            id: 'sticker',
            mediaId: 'sticker-source',
            durationUs: 1000000,
          ),
        ),
        EditTimelineClip(
          clipId: 'title',
          transform: EditorTransform(x: 0.5, y: 0.8, scaleX: 0.7, scaleY: 0.7),
        ),
        const SetStillDuration(clipId: 'title', durationUs: 2000000),
        const MoveTimelineClip(
          clipId: 'title',
          targetTrackId: 'second-title-layer',
          timelineStartUs: 1000000,
        ),
        SetClipFilter(
          clipId: 'photo',
          filter: EditorFilter(
            id: 'grade',
            name: 'Warm',
            shaderId: 'warm',
            intensity: 0.5,
          ),
        ),
        SetClipEffect(
          clipId: 'sticker',
          effect: EditorEffect(
            id: 'glow',
            effectId: 'glow',
            parameters: {'radius': 4},
          ),
        ),
      ]),
    );
    controller.undo();
    controller.redo();
    await file.save(controller.project);
  } finally {
    await controller.close();
  }
  // A fresh file owner models closing and reopening a document.
  return EditorProjectFile(projectPath).load();
}
