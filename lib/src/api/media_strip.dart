import 'dart:io';
import 'package:flutter/material.dart';
import '../controller/editor_controller.dart';
import '../controller/media_strip_loader.dart';
import '../models/editor_media_strip.dart';

/// Internal, culled with its clip. Decoding/caching belongs to the controller
/// and native adapter, not the widget. No synthetic waveform placeholders.
class MediaStrip extends StatefulWidget {
  const MediaStrip({
    super.key,
    required this.controller,
    required this.path,
    required this.startUs,
    required this.endUs,
    required this.video,
    required this.foreground,
  });
  final EditorController controller;
  final String path;
  final int startUs, endUs;
  final bool video;
  final Color foreground;
  @override
  State<MediaStrip> createState() => _MediaStripState();
}

class _MediaStripState extends State<MediaStrip> {
  MediaStripRequest? request;
  EditorMediaStrip? strip;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant MediaStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.path != widget.path ||
        oldWidget.startUs != widget.startUs ||
        oldWidget.endUs != widget.endUs ||
        oldWidget.video != widget.video) {
      if (request case final pending?) {
        oldWidget.controller.mediaStrips.cancel(pending);
      }
      load();
    }
  }

  void load() {
    strip = null;
    failed = false;
    try {
      final next = widget.controller.mediaStrips.load(
        widget.path,
        widget.startUs,
        widget.endUs,
        thumbnails: widget.video ? 6 : 0,
      );
      request = next;
      next.result.future.then(
        (result) {
          if (mounted && identical(request, next)) {
            setState(() => strip = result);
          }
        },
        onError: (Object error) {
          if (mounted && identical(request, next) && !next.cancelled) {
            setState(() => failed = true);
          }
        },
      );
    } catch (_) {
      failed = true;
    }
  }

  @override
  void dispose() {
    if (request case final pending?) {
      widget.controller.mediaStrips.cancel(pending);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = strip;
    if (failed) {
      return Center(
        child: IconButton(
          tooltip: 'Preview unavailable. Retry',
          onPressed: () => setState(load),
          icon: Icon(Icons.refresh, size: 18, color: widget.foreground),
        ),
      );
    }
    if (data == null) {
      return Center(
        child: Text(
          'Loading preview…',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: widget.foreground),
        ),
      );
    }
    return RepaintBoundary(
      child: Column(
        children: [
          if (data.thumbnails.isNotEmpty)
            Expanded(
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    for (final path in data.thumbnails)
                      Expanded(
                        child: Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          height: double.infinity,
                          cacheWidth: 160,
                          gaplessPlayback: false,
                          errorBuilder: (_, _, _) => Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              size: 16,
                              color: widget.foreground,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (data.peaks.isNotEmpty)
            SizedBox(
              height: widget.video ? 18 : 40,
              width: double.infinity,
              child: Semantics(
                label: 'Audio waveform',
                child: CustomPaint(
                  painter: _WaveformPainter(data.peaks, widget.foreground),
                ),
              ),
            )
          else if (!widget.video)
            Text(
              'No audio track',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: widget.foreground),
            ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter(this.peaks, this.color);
  final List<double> peaks;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path();
    for (var i = 0; i < peaks.length; i++) {
      final x = (i + .5) / peaks.length * size.width;
      final height = peaks[i].clamp(0, 1) * size.height / 2;
      path.moveTo(x, size.height / 2 - height);
      path.lineTo(x, size.height / 2 + height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.peaks != peaks || oldDelegate.color != color;
}
