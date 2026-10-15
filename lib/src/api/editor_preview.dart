import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../controller/editor_controller.dart';
import '../models/editor_playback.dart';

/// A native source or cut-composition preview. Mount one preview per controller.
/// It never plays automatically and does not own/dispose the controller.
final class EditorPreview extends StatelessWidget {
  const EditorPreview({super.key, required this.controller});
  final EditorController controller;

  @override
  Widget build(BuildContext context) => StreamBuilder<EditorState>(
    key: ObjectKey(controller),
    stream: controller.stream,
    initialData: controller.state,
    builder: (context, snapshot) {
      final state = snapshot.requireData;
      final media = state.media;
      final session = controller.previewSessionId;
      if (state.playback.status == EditorPlaybackStatus.failed) {
        return const Center(
          child: Text('Cannot play this video. Open another file or retry.'),
        );
      }
      if (media == null || session == null) {
        return Center(
          child: state.playback.status == EditorPlaybackStatus.loading
              ? const CircularProgressIndicator.adaptive(
                  semanticsLabel: 'Loading video',
                )
              : const Text('Open a video to preview it.'),
        );
      }
      final params = <String, Object>{'sessionId': session};
      final Widget surface;
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          // Hybrid composition keeps the decoder's SurfaceView in the native
          // view hierarchy, including the first paused frame. Nesting it in
          // AndroidView's texture composition can leave that frame black.
          surface = PlatformViewLink(
            viewType: 'vn_editor/preview',
            surfaceFactory: (context, controller) => AndroidViewSurface(
              controller: controller as AndroidViewController,
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
              gestureRecognizers:
                  const <Factory<OneSequenceGestureRecognizer>>{},
            ),
            onCreatePlatformView: (parameters) {
              final controller = PlatformViewsService.initExpensiveAndroidView(
                id: parameters.id,
                viewType: 'vn_editor/preview',
                layoutDirection: TextDirection.ltr,
                creationParams: params,
                creationParamsCodec: const StandardMessageCodec(),
                onFocus: () => parameters.onFocusChanged(true),
              );
              controller.addOnPlatformViewCreatedListener(
                parameters.onPlatformViewCreated,
              );
              controller.create();
              return controller;
            },
          );
        case TargetPlatform.iOS:
          surface = UiKitView(
            viewType: 'vn_editor/preview',
            creationParams: params,
            creationParamsCodec: const StandardMessageCodec(),
          );
        default:
          return const Center(
            child: Text('Video preview requires Android or iOS.'),
          );
      }
      return Center(
        child: AspectRatio(
          aspectRatio: media.width / media.height,
          child: Semantics(
            label: 'Video preview',
            image: true,
            child: KeyedSubtree(key: ValueKey(session), child: surface),
          ),
        ),
      );
    },
  );
}
