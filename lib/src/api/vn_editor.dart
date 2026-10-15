import 'dart:async';

import 'package:flutter/material.dart';

import '../controller/editor_controller.dart';
import '../models/editor_export.dart';
import '../models/editor_project.dart';
import '../models/editor_playback.dart';
import 'editor_preview.dart';
import 'editor_timeline.dart';

typedef EditorExportComplete = void Function(EditorExportResult result);

/// The host application's entry point into the editor experience.
final class VnEditor extends StatefulWidget {
  const VnEditor({
    super.key,
    required this.project,
    this.controller,
    this.onExportComplete,
  });

  final EditorProject project;
  final EditorController? controller;
  final EditorExportComplete? onExportComplete;

  @override
  State<VnEditor> createState() => _VnEditorState();
}

class _VnEditorState extends State<VnEditor> {
  late EditorController _controller;
  late bool _ownsController;

  @override
  void initState() {
    super.initState();
    _attachController();
  }

  void _attachController({Future<void>? after}) {
    if (widget.controller != null &&
        !identical(widget.controller!.project, widget.project)) {
      throw ArgumentError(
        'The controller and widget must use the same project.',
      );
    }
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ?? EditorController(project: widget.project);
    if (after == null) {
      _initialize();
    } else {
      final attached = _controller;
      unawaited(
        after.then((_) {
          if (mounted && identical(attached, _controller)) _initialize();
        }),
      );
    }
  }

  void _initialize() {
    // Initialization errors are rendered from controller state.
    unawaited(_controller.initialize().catchError((Object _) {}));
  }

  Future<void> _releaseOwnedController() async {
    if (_ownsController) {
      await _controller.close().catchError((Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'vn_editor',
          ),
        );
      });
    }
  }

  @override
  void didUpdateWidget(covariant VnEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller) ||
        !identical(widget.project, oldWidget.project)) {
      final releasing = _releaseOwnedController();
      _attachController(after: releasing);
    }
  }

  @override
  void dispose() {
    unawaited(_releaseOwnedController());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<EditorState>(
      key: ObjectKey(_controller),
      stream: _controller.stream.distinct((a, b) => a.lifecycle == b.lifecycle),
      initialData: _controller.state,
      builder: (BuildContext context, AsyncSnapshot<EditorState> snapshot) {
        final editorState = snapshot.requireData;
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.project.id),
            actions: <Widget>[
              Semantics(
                label: 'Export project',
                button: true,
                child: TextButton(onPressed: null, child: const Text('Export')),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(child: _buildBody(editorState)),
        );
      },
    );
  }

  Widget _buildBody(EditorState editorState) {
    switch (editorState.lifecycle) {
      case EditorLifecycleState.idle:
      case EditorLifecycleState.initializing:
        return const Center(child: CircularProgressIndicator.adaptive());
      case EditorLifecycleState.failed:
        return Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.error,
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The editor could not start.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Close any other editor, then try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  TextButton(
                    onPressed: _initialize,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        );
      case EditorLifecycleState.ready:
        return StreamBuilder<EditorState>(
          stream: _controller.stream,
          initialData: _controller.state,
          builder: (_, snapshot) => _EditorFoundationView(
            key: ObjectKey(_controller),
            controller: _controller,
            state: snapshot.requireData,
          ),
        );
      case EditorLifecycleState.disposed:
        return const SizedBox.shrink();
    }
  }
}

class _EditorFoundationView extends StatefulWidget {
  const _EditorFoundationView({
    super.key,
    required this.controller,
    required this.state,
  });
  final EditorController controller;
  final EditorState state;

  @override
  State<_EditorFoundationView> createState() => _EditorFoundationViewState();
}

class _EditorFoundationViewState extends State<_EditorFoundationView> {
  EditorController get controller => widget.controller;
  EditorState get state => widget.state;
  double? _scrub;
  late final _timeline = EditorTimeline(controller: controller);
  late final _preview = EditorPreview(controller: controller);

  Future<void> _command(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Playback command failed. Try reopening the video.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          flex: 4,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child:
                state.media != null ||
                    state.playback.status != EditorPlaybackStatus.idle
                ? _preview
                : Center(
                    child: Text(
                      'Your project is ready',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          color: Theme.of(context).colorScheme.surface,
          child: state.media == null
              ? Text(
                  'Open a local video with controller.openMedia(path).',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Slider(
                      value:
                          (_scrub ?? state.position.inMilliseconds.toDouble())
                              .clamp(
                                0,
                                state.media!.duration.inMilliseconds.toDouble(),
                              ),
                      max: state.media!.duration.inMilliseconds.toDouble(),
                      label: '${state.position.inSeconds} seconds',
                      semanticFormatterCallback: (value) =>
                          '${(value / 1000).round()} seconds',
                      onChanged:
                          state.playback.status == EditorPlaybackStatus.failed
                          ? null
                          : (value) => setState(() => _scrub = value),
                      onChangeEnd: (value) {
                        setState(() => _scrub = null);
                        _command(
                          context,
                          () => controller.seek(
                            Duration(milliseconds: value.round()),
                          ),
                        );
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton.filledTonal(
                          tooltip: state.isPlaying ? 'Pause' : 'Play',
                          onPressed:
                              state.playback.status ==
                                  EditorPlaybackStatus.failed
                              ? null
                              : () => _command(
                                  context,
                                  state.isPlaying
                                      ? controller.pause
                                      : controller.play,
                                ),
                          icon: Icon(
                            state.isPlaying ? Icons.pause : Icons.play_arrow,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '${state.isTimeline ? 'Timeline' : 'Source'} ${state.position.inSeconds}s / ${(state.isTimeline ? controller.project.durationUs ~/ 1000000 : state.media!.duration.inSeconds)}s',
                        ),
                      ],
                    ),
                  ],
                ),
        ),
        Expanded(flex: 3, child: _timeline),
      ],
    );
  }
}
