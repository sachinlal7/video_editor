import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vn_editor/vn_editor.dart';

/// Example-only fixture copy; the SDK accepts host-owned local paths.
Future<File> copySampleVideo([String name = 'sample.mp4']) async {
  final bytes = await rootBundle.load('assets/media/$name');
  final directory = await Directory(
    '${Directory.systemTemp.path}/vn_editor_samples',
  ).create(recursive: true);
  return File('${directory.path}/$name').writeAsBytes(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    flush: true,
  );
}

class PlaybackExample extends StatefulWidget {
  const PlaybackExample({super.key});
  @override
  State<PlaybackExample> createState() => _PlaybackExampleState();
}

class _PlaybackExampleState extends State<PlaybackExample> {
  late final project = EditorProject.empty(
    id: 'Timeline editor',
    width: 1280,
    height: 720,
    frameRate: 30,
  );
  late final controller = EditorController(project: project);
  Object? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await controller.initialize();
      final file = await copySampleVideo();
      if (!mounted) return;
      final media = await controller.openMedia(file.path);
      if (!mounted) return;
      if (controller.project.tracks.isEmpty) {
        controller.execute(
          EditorTransaction([
            AddVideoSource(VideoClip(id: 'sample', sourcePath: file.path)),
            AddTrack(
              EditorTrack(
                id: 'Video',
                kind: EditorTrackKind.video,
                clips: [
                  TimelineClip(
                    id: 'First cut',
                    mediaId: 'sample',
                    sourceDurationUs: media.duration.inMicroseconds,
                    sourceOutUs: 3000000,
                  ),
                  TimelineClip(
                    id: 'Fast cut',
                    mediaId: 'sample',
                    sourceDurationUs: media.duration.inMicroseconds,
                    sourceInUs: 4000000,
                    sourceOutUs: 8000000,
                    timelineStartUs: 3500000,
                    speed: PlaybackRate(2),
                    effects: [
                      EditorEffectRegistry.definition('lut').create(
                        instanceId: 'editor-adjustment',
                        parameters: {'preset': 2},
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ]),
        );
      }
      await controller.prepareTimeline();
    } catch (failure) {
      if (mounted) error = failure;
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    unawaited(
      controller.close().catchError((Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading || error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Native playback')),
        body: Center(
          child: loading
              ? const CircularProgressIndicator.adaptive()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('The sample video could not be opened.'),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
        ),
      );
    }
    return VnEditor(project: controller.project, controller: controller);
  }
}
