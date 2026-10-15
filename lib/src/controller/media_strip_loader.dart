import 'dart:async';
import 'dart:collection';
import '../domain/editor_platform.dart';
import '../models/editor_media_strip.dart';

final class MediaStripRequest {
  MediaStripRequest(
    this.id,
    this.path,
    this.startUs,
    this.endUs,
    this.thumbnails,
  );
  final int id, startUs, endUs, thumbnails;
  final String path;
  final result = Completer<EditorMediaStrip>();
  bool cancelled = false;
  bool running = false;
}

/// One bounded decoder queue per editor. Widgets cancel requests when culled;
/// native code owns the bounded file cache and always releases its decoders.
final class MediaStripLoader {
  MediaStripLoader(this.platform);
  final EditorPlatform platform;
  final _pending = Queue<MediaStripRequest>();
  final _active = <MediaStripRequest>{};
  int _nextId = 0;
  bool _closed = false;

  MediaStripRequest load(
    String path,
    int startUs,
    int endUs, {
    int thumbnails = 6,
  }) {
    if (_closed) throw StateError('Preview loader is closed.');
    if (path.isEmpty ||
        startUs < 0 ||
        endUs <= startUs ||
        thumbnails < 0 ||
        thumbnails > 8) {
      throw ArgumentError('Invalid preview interval/count.');
    }
    final request = MediaStripRequest(
      ++_nextId,
      path,
      startUs,
      endUs,
      thumbnails,
    );
    if (_pending.length >= 32) {
      request.result.completeError(
        StateError('Preview queue is full. Retry when scrolling stops.'),
      );
    } else {
      _pending.add(request);
      _drain();
    }
    return request;
  }

  void cancel(MediaStripRequest request) {
    if (request.cancelled) return;
    request.cancelled = true;
    _pending.remove(request);
    if (!request.result.isCompleted) {
      request.result.completeError(StateError('Preview cancelled.'));
    }
    if (request.running) {
      unawaited(
        platform.cancelMediaStrip(request.id).catchError((Object _) {}),
      );
    }
  }

  void _drain() {
    while (!_closed && _active.length < 2 && _pending.isNotEmpty) {
      final request = _pending.removeFirst();
      _active.add(request);
      request.running = true;
      unawaited(_run(request));
    }
  }

  Future<void> _run(MediaStripRequest request) async {
    try {
      final result = await platform.loadMediaStrip(
        request.path,
        request.startUs,
        request.endUs,
        request.thumbnails,
        request.id,
      );
      if (!request.result.isCompleted) request.result.complete(result);
    } catch (error, stack) {
      if (!request.result.isCompleted) {
        request.result.completeError(error, stack);
      }
    } finally {
      request.running = false;
      _active.remove(request);
      _drain();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final request in [..._pending, ..._active]) {
      cancel(request);
    }
  }
}
