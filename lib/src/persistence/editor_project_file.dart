import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../models/editor_project.dart';
import 'editor_project_codec.dart';

/// One owner per document path. Operations on this instance are serialized.
/// Atomic sibling-file replacement preserves the previous file on write failure.
/// Cross-process/multi-instance writers are not coordinated.
final class EditorProjectFile {
  EditorProjectFile(String path) : _file = File(path).absolute {
    if (path.trim().isEmpty) throw ArgumentError('Document path is required.');
  }

  static const maxDocumentBytes = 16 * 1024 * 1024;
  final File _file;
  Future<void> _pending = Future.value();

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final next = _pending.then((_) => operation());
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> save(EditorProject project) => _serialize(() async {
    final bytes = await _encode(project);
    if (bytes.length > maxDocumentBytes) {
      throw const FormatException('Project document exceeds 16 MiB.');
    }
    // Caller selects/creates an app-owned directory; never create arbitrary parents.
    final temporary = await _file.parent.createTemp('.vn-editor-');
    try {
      final staged = File('${temporary.path}/project.json');
      await staged.writeAsBytes(bytes, flush: true);
      await staged.rename(_file.absolute.path);
    } finally {
      await temporary.delete(recursive: true);
    }
  });

  Future<EditorProject> load() => _serialize(() async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in _file.openRead()) {
      if (bytes.length + chunk.length > maxDocumentBytes) {
        throw const FormatException('Project document exceeds 16 MiB.');
      }
      bytes.add(chunk);
    }
    return _decode(bytes.takeBytes());
  });
}

// Keep worker closures outside the file owner's context (pending futures/I/O).
Future<List<int>> _encode(EditorProject project) =>
    Isolate.run(() => utf8.encode(const EditorProjectCodec().encode(project)));

Future<EditorProject> _decode(List<int> bytes) =>
    Isolate.run(() => const EditorProjectCodec().decode(utf8.decode(bytes)));
