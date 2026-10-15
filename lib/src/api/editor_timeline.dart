import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controller/editor_controller.dart';
import '../controller/timeline_cubit.dart';
import '../timeline/editor_timeline.dart';
import 'media_strip.dart';
import 'editor_effect_panel.dart';

/// A bounded-height, zoomable timeline. Does not take ownership of [controller].
///
/// Source trims preserve the placement start. Ruler seeks affect the native
/// player only inside a selected video whose source is already open.
class EditorTimeline extends StatelessWidget {
  const EditorTimeline({super.key, required this.controller});
  final EditorController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final minimumHeight = 160 + MediaQuery.textScalerOf(context).scale(32);
      final surface = _TimelineSurface(
        key: ObjectKey(controller),
        controller: controller,
      );
      return SingleChildScrollView(
        child: SizedBox(
          height: math.max(minimumHeight, box.maxHeight),
          child: surface,
        ),
      );
    },
  );
}

class _TimelineSurface extends StatefulWidget {
  const _TimelineSurface({super.key, required this.controller});
  final EditorController controller;
  @override
  State<_TimelineSurface> createState() => _TimelineSurfaceState();
}

class _TimelineSurfaceState extends State<_TimelineSurface> {
  late final cubit = TimelineCubit(widget.controller);
  final scroll = ScrollController();
  final cursor = ValueNotifier<int>(0);
  late final StreamSubscription<TimelineViewState> subscription;
  late TimelineViewState view;
  int? scrubPosition;

  @override
  void initState() {
    super.initState();
    view = cubit.state;
    subscription = cubit.stream.listen((next) {
      cursor.value = next.positionUs;
      if (!identical(next.project, view.project) ||
          next.selectedId != view.selectedId ||
          next.pixelsPerSecond != view.pixelsPerSecond ||
          next.error != view.error) {
        setState(() => view = next);
      }
    });
  }

  @override
  void dispose() {
    unawaited(subscription.cancel());
    unawaited(cubit.close());
    cursor.dispose();
    scroll.dispose();
    super.dispose();
  }

  void zoom(double factor) {
    final anchor = scroll.hasClients
        ? scroll.offset / view.pixelsPerSecond
        : 0.0;
    cubit.zoom(view.pixelsPerSecond * factor);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.jumpTo(
          (anchor * cubit.state.pixelsPerSecond).clamp(
            0,
            scroll.position.maxScrollExtent,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final labelStyle = textTheme.labelSmall!;
    final labelHeight = math.max(
      20.0,
      scaler.scale(labelStyle.fontSize!) * (labelStyle.height ?? 1.4) + 4,
    );
    final clipHeight = math.max(
      96.0,
      scaler.scale(textTheme.bodyMedium!.fontSize!) *
              (textTheme.bodyMedium!.height ?? 1.4) +
          64,
    );
    return ColoredBox(
      color: colors.surfaceContainer,
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('Timeline'),
                ),
                IconButton(
                  tooltip: 'Preview timeline',
                  icon: const Icon(Icons.movie_outlined),
                  onPressed: () async {
                    try {
                      await widget.controller.prepareTimeline();
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Timeline unavailable: $error'),
                          ),
                        );
                      }
                    }
                  },
                ),
                PopupMenuButton<String>(
                  tooltip: 'Select clip',
                  enabled: view.project.tracks.any((t) => t.clips.isNotEmpty),
                  icon: const Icon(Icons.video_library_outlined),
                  onSelected: cubit.select,
                  itemBuilder: (_) => [
                    for (final track in view.project.tracks)
                      for (final clip in track.clips)
                        PopupMenuItem(value: clip.id, child: Text(clip.id)),
                  ],
                ),
                IconButton(
                  tooltip: 'Undo',
                  onPressed: widget.controller.state.canUndo
                      ? widget.controller.undo
                      : null,
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  tooltip: 'Clip effects',
                  icon: const Icon(Icons.tune),
                  onPressed: cubit.selected == null
                      ? null
                      : () => showModalBottomSheet<void>(
                          context: context,
                          barrierColor: Colors.transparent,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight:
                                  MediaQuery.sizeOf(context).height * .55,
                            ),
                            child: SingleChildScrollView(
                              child: EditorEffectPanel(
                                controller: widget.controller,
                                clipId: cubit.selected!.id,
                              ),
                            ),
                          ),
                        ),
                ),
                IconButton(
                  tooltip: 'Redo',
                  onPressed: widget.controller.state.canRedo
                      ? widget.controller.redo
                      : null,
                  icon: const Icon(Icons.redo),
                ),
                IconButton(
                  tooltip: 'Zoom out',
                  onPressed: view.pixelsPerSecond > 16 ? () => zoom(0.5) : null,
                  icon: const Icon(Icons.zoom_out),
                ),
                IconButton(
                  tooltip: 'Zoom in',
                  onPressed: view.pixelsPerSecond < 256 ? () => zoom(2) : null,
                  icon: const Icon(Icons.zoom_in),
                ),
                PopupMenuButton<int>(
                  tooltip: 'Trim selected clip',
                  enabled: cubit.selected != null,
                  icon: const Icon(Icons.content_cut),
                  onSelected: (action) {
                    final clip = cubit.selected;
                    if (clip != null) {
                      cubit.trim(
                        clip,
                        start: action < 2,
                        deltaUs:
                            view.project.timebase.timeAtFrame(1) *
                            (action.isEven ? -1 : 1),
                      );
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 0,
                      child: Text('Start: one frame earlier'),
                    ),
                    PopupMenuItem(
                      value: 1,
                      child: Text('Start: one frame later'),
                    ),
                    PopupMenuItem(
                      value: 2,
                      child: Text('End: one frame earlier'),
                    ),
                    PopupMenuItem(
                      value: 3,
                      child: Text('End: one frame later'),
                    ),
                  ],
                ),
                PopupMenuButton<int>(
                  tooltip: 'Move selected clip',
                  enabled: cubit.selected != null,
                  icon: const Icon(Icons.swap_horiz),
                  onSelected: (action) {
                    final clip = cubit.selected;
                    if (clip == null) return;
                    if (action < 2) {
                      cubit.move(
                        clip,
                        view.project.timebase.timeAtFrame(1) *
                            (action == 0 ? -1 : 1),
                      );
                    } else {
                      cubit.reorder(action == 2);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 0,
                      child: Text('Move one frame earlier'),
                    ),
                    PopupMenuItem(
                      value: 1,
                      child: Text('Move one frame later'),
                    ),
                    PopupMenuItem(
                      value: 2,
                      child: Text('Swap with previous clip'),
                    ),
                    PopupMenuItem(value: 3, child: Text('Swap with next clip')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: view.project.tracks.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Add a track and clips to begin editing.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, box) {
                      final width = math.max(
                        box.maxWidth,
                        view.project.durationUs /
                                1000000 *
                                view.pixelsPerSecond +
                            64,
                      );
                      return AnimatedBuilder(
                        animation: scroll,
                        builder: (context, _) {
                          final offset = scroll.hasClients
                              ? scroll.offset
                              : 0.0;
                          return Column(
                            children: [
                              GestureDetector(
                                key: const ValueKey('timeline-ruler'),
                                behavior: HitTestBehavior.opaque,
                                onHorizontalDragUpdate: (event) {
                                  scrubPosition =
                                      ((event.localPosition.dx + offset) /
                                              view.pixelsPerSecond *
                                              1000000)
                                          .round();
                                  cubit.previewCursor(scrubPosition!);
                                },
                                onHorizontalDragEnd: (_) {
                                  if (scrubPosition case final position?) {
                                    cubit.scrub(position);
                                  }
                                  scrubPosition = null;
                                },
                                onHorizontalDragCancel: () =>
                                    scrubPosition = null,
                                onTapUp: (event) => cubit.scrub(
                                  ((event.localPosition.dx + offset) /
                                          view.pixelsPerSecond *
                                          1000000)
                                      .round(),
                                ),
                                child: SizedBox(
                                  height: 48,
                                  width: box.maxWidth,
                                  child: CustomPaint(
                                    painter: _RulerPainter(
                                      offset,
                                      view.pixelsPerSecond,
                                      colors.onSurfaceVariant,
                                      Theme.of(context).textTheme.labelSmall!,
                                      MediaQuery.textScalerOf(context),
                                    ),
                                    foregroundPainter: _PlayheadPainter(
                                      cursor,
                                      offset,
                                      view.pixelsPerSecond,
                                      colors.primary,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Stack(
                                  children: [
                                    Scrollbar(
                                      controller: scroll,
                                      thumbVisibility: true,
                                      child: SingleChildScrollView(
                                        controller: scroll,
                                        scrollDirection: Axis.horizontal,
                                        child: SizedBox(
                                          width: width,
                                          child: ListView.builder(
                                            itemCount:
                                                view.project.tracks.length,
                                            itemExtent:
                                                labelHeight + clipHeight + 4,
                                            itemBuilder: (context, index) {
                                              final track =
                                                  view.project.tracks[index];
                                              return Stack(
                                                clipBehavior: Clip.hardEdge,
                                                children: [
                                                  Positioned(
                                                    left: offset + 8,
                                                    top: 0,
                                                    width: math.max(
                                                      0,
                                                      box.maxWidth - 16,
                                                    ),
                                                    child: Text(
                                                      '${track.kind.name} · ${track.id}',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: Theme.of(
                                                        context,
                                                      ).textTheme.labelSmall,
                                                    ),
                                                  ),
                                                  if (track.clips.isEmpty)
                                                    Positioned(
                                                      left: offset + 8,
                                                      top: labelHeight,
                                                      width: math.max(
                                                        0,
                                                        box.maxWidth - 16,
                                                      ),
                                                      height: clipHeight,
                                                      child: Align(
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: Text(
                                                          'Add clips to this track.',
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            color: colors
                                                                .onSurfaceVariant,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  for (final clip
                                                      in track.clips)
                                                    if (clip.timelineEndUs /
                                                                1000000 *
                                                                view.pixelsPerSecond >=
                                                            offset &&
                                                        clip.timelineStartUs /
                                                                1000000 *
                                                                view.pixelsPerSecond <=
                                                            offset +
                                                                box.maxWidth)
                                                      Positioned(
                                                        left:
                                                            clip.timelineStartUs /
                                                            1000000 *
                                                            view.pixelsPerSecond,
                                                        top: labelHeight,
                                                        width: math.max(
                                                          4,
                                                          clip.durationUs /
                                                              1000000 *
                                                              view.pixelsPerSecond,
                                                        ),
                                                        height: clipHeight,
                                                        child: _ClipBlock(
                                                          key: ValueKey(
                                                            clip.id,
                                                          ),
                                                          clip: clip,
                                                          controller:
                                                              widget.controller,
                                                          sourcePath:
                                                              track.kind ==
                                                                  EditorTrackKind
                                                                      .video
                                                              ? view
                                                                    .project
                                                                    .videoClips
                                                                    .where(
                                                                      (s) =>
                                                                          s.id ==
                                                                          clip.mediaId,
                                                                    )
                                                                    .firstOrNull
                                                                    ?.sourcePath
                                                              : track.kind ==
                                                                    EditorTrackKind
                                                                        .audio
                                                              ? view
                                                                    .project
                                                                    .audioClips
                                                                    .where(
                                                                      (s) =>
                                                                          s.id ==
                                                                          clip.mediaId,
                                                                    )
                                                                    .firstOrNull
                                                                    ?.sourcePath
                                                              : null,
                                                          video:
                                                              track.kind ==
                                                              EditorTrackKind
                                                                  .video,
                                                          frameDurationUs: view
                                                              .project
                                                              .timebase
                                                              .timeAtFrame(1),
                                                          selected:
                                                              view.selectedId ==
                                                              clip.id,
                                                          pixelsPerSecond: view
                                                              .pixelsPerSecond,
                                                          onSelect: () => cubit
                                                              .select(clip.id),
                                                          onMove: (delta) =>
                                                              cubit.move(
                                                                clip,
                                                                (delta /
                                                                        view.pixelsPerSecond *
                                                                        1000000)
                                                                    .round(),
                                                              ),
                                                          onTrimStep:
                                                              (
                                                                start,
                                                                direction,
                                                              ) => cubit.trim(
                                                                clip,
                                                                start: start,
                                                                deltaUs:
                                                                    view
                                                                        .project
                                                                        .timebase
                                                                        .timeAtFrame(
                                                                          1,
                                                                        ) *
                                                                    direction,
                                                              ),
                                                          onTrim:
                                                              (
                                                                start,
                                                                delta,
                                                              ) => cubit.trim(
                                                                clip,
                                                                start: start,
                                                                deltaUs:
                                                                    (delta /
                                                                            view.pixelsPerSecond *
                                                                            1000000)
                                                                        .round(),
                                                              ),
                                                        ),
                                                      ),
                                                ],
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: CustomPaint(
                                          painter: _PlayheadPainter(
                                            cursor,
                                            offset,
                                            view.pixelsPerSecond,
                                            colors.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: cursor,
                  builder: (_, value, child) => Text(
                    _time(value),
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    view.error ??
                        (view.selectedId == null
                            ? 'Select a clip to trim'
                            : 'Trim source • ${view.selectedId}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: view.error == null
                          ? colors.onSurfaceVariant
                          : colors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClipBlock extends StatefulWidget {
  const _ClipBlock({
    super.key,
    required this.clip,
    required this.selected,
    required this.onSelect,
    required this.onMove,
    required this.onTrim,
    required this.onTrimStep,
    required this.frameDurationUs,
    required this.controller,
    required this.sourcePath,
    required this.video,
    required this.pixelsPerSecond,
  });
  final TimelineClip clip;
  final EditorController controller;
  final String? sourcePath;
  final bool video;
  final bool selected;
  final VoidCallback onSelect;
  final void Function(double delta) onMove;
  final void Function(bool start, double delta) onTrim;
  final void Function(bool start, int direction) onTrimStep;
  final int frameDurationUs;
  final double pixelsPerSecond;
  @override
  State<_ClipBlock> createState() => _ClipBlockState();
}

class _ClipBlockState extends State<_ClipBlock> {
  double drag = 0;
  bool? edge;
  double? moving;

  @override
  void didUpdateWidget(covariant _ClipBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.clip, widget.clip) || !widget.selected) {
      edge = null;
      drag = 0;
      moving = null;
    }
  }

  String boundaryValue(bool start, int direction) {
    final clip = widget.clip;
    final delta = clip.speed.sourceOffset(widget.frameDurationUs) * direction;
    return _time(
      start
          ? (clip.sourceInUs + delta).clamp(0, clip.sourceOutUs - 1)
          : (clip.sourceOutUs + delta).clamp(
              clip.sourceInUs + 1,
              clip.sourceDurationUs,
            ),
    );
  }

  Widget handle(bool start) => Semantics(
    label: start ? 'Trim start' : 'Trim end',
    value: boundaryValue(start, 0),
    increasedValue: boundaryValue(start, 1),
    decreasedValue: boundaryValue(start, -1),
    onIncrease: () => widget.onTrimStep(start, 1),
    onDecrease: () => widget.onTrimStep(start, -1),
    child: Tooltip(
      message: start ? 'Trim start' : 'Trim end',
      child: GestureDetector(
        key: ValueKey('${widget.clip.id}-${start ? 'start' : 'end'}'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() {
          edge = start;
          drag = 0;
        }),
        onHorizontalDragUpdate: (event) =>
            setState(() => drag += event.delta.dx),
        onHorizontalDragCancel: () => setState(() {
          edge = null;
          drag = 0;
        }),
        onHorizontalDragEnd: (_) {
          if (edge != null) widget.onTrim(start, drag);
          setState(() {
            edge = null;
            drag = 0;
          });
        },
        child: SizedBox(
          width: 48,
          height: 56,
          child: Icon(
            edge == start ? Icons.swap_horiz : Icons.drag_indicator,
            size: 18,
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: widget.selected,
      button: true,
      label: '${widget.clip.id}, ${_time(widget.clip.durationUs)}',
      child: Material(
        color: widget.selected
            ? colors.primaryContainer
            : colors.secondaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: widget.selected ? colors.primary : colors.outlineVariant,
            width: widget.selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          onTap: widget.onSelect,
          child: GestureDetector(
            onLongPressStart: (_) {
              widget.onSelect();
              setState(() => moving = 0);
            },
            onLongPressMoveUpdate: (details) =>
                setState(() => moving = details.offsetFromOrigin.dx),
            onLongPressEnd: (_) {
              if (moving case final delta?) widget.onMove(delta);
              setState(() => moving = null);
            },
            onLongPressCancel: () => setState(() => moving = null),
            child: LayoutBuilder(
              builder: (context, box) => Row(
                children: [
                  if (widget.selected && box.maxWidth >= 144) handle(true),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            moving != null
                                ? 'Move ${(moving! / widget.pixelsPerSecond).toStringAsFixed(2)}s'
                                : edge == null
                                ? widget.clip.id
                                : 'Trim ${(drag / widget.pixelsPerSecond).toStringAsFixed(2)}s',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.selected
                                  ? colors.onPrimaryContainer
                                  : colors.onSecondaryContainer,
                            ),
                          ),
                          if (widget.sourcePath case final path?)
                            Expanded(
                              child: MediaStrip(
                                controller: widget.controller,
                                path: path,
                                startUs: widget.clip.sourceInUs,
                                endUs: widget.clip.sourceOutUs,
                                video: widget.video,
                                foreground: widget.selected
                                    ? colors.onPrimaryContainer
                                    : colors.onSecondaryContainer,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.selected && box.maxWidth >= 144) handle(false),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _time(int us) {
  final centiseconds = us ~/ 10000;
  return '${centiseconds ~/ 6000}:${((centiseconds ~/ 100) % 60).toString().padLeft(2, '0')}.${(centiseconds % 100).toString().padLeft(2, '0')}';
}

class _RulerPainter extends CustomPainter {
  _RulerPainter(
    this.offset,
    this.scale,
    this.color,
    this.style,
    this.textScaler,
  );
  final double offset, scale;
  final Color color;
  final TextStyle style;
  final TextScaler textScaler;
  @override
  void paint(Canvas canvas, Size size) {
    var seconds = 1;
    while (seconds * scale < 72 * textScaler.scale(1)) {
      seconds *= 2;
    }
    final first = (offset / scale / seconds).floor() * seconds;
    final paint = Paint()..color = color;
    for (
      var time = first;
      time * scale < offset + size.width;
      time += seconds
    ) {
      final x = time * scale - offset;
      canvas.drawLine(Offset(x, 36), Offset(x, 48), paint);
      final text = TextPainter(
        text: TextSpan(
          text: _time(time * 1000000),
          style: style.copyWith(color: color),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      text.paint(canvas, Offset(x + 4, 10));
      text.dispose();
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.offset != offset ||
      old.scale != scale ||
      old.color != color ||
      old.style != style ||
      old.textScaler != textScaler;
}

class _PlayheadPainter extends CustomPainter {
  _PlayheadPainter(this.cursor, this.offset, this.scale, this.color)
    : super(repaint: cursor);
  final ValueNotifier<int> cursor;
  final double offset, scale;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final x = cursor.value / 1000000 * scale - offset;
    if (x >= 0 && x <= size.width) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = color
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_PlayheadPainter old) =>
      old.cursor != cursor ||
      old.offset != offset ||
      old.scale != scale ||
      old.color != color;
}
