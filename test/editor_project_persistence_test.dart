import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vn_editor/vn_editor.dart';

import 'editor_timeline_test.dart' show timelineProject, placement;

void main() {
  const codec = EditorProjectCodec();
  final project = timelineProject().copyWith(
    tracks: [
      EditorTrack(
        id: 'video-track',
        kind: EditorTrackKind.video,
        clips: [placement(speed: PlaybackRate(3, 2))],
      ),
    ],
    textOverlays: const [TextOverlay(id: 'caption', text: 'Hello 👋')],
    stickerOverlays: const [
      StickerOverlay(id: 'sticker', assetId: 'assets/star.png'),
    ],
  );

  test('versioned JSON round trip preserves all data and relative paths', () {
    final encoded = codec.encode(project);
    final restored = codec.decode(encoded);
    expect(codec.encode(restored), encoded);
    expect(restored.videoClips.single.sourcePath, 'media/video.mp4');
    expect(restored.tracks.single.clips.single.speed.denominator, 2);
    expect(restored.textOverlays.single.text, 'Hello 👋');
  });

  test('rejects malformed documents and unknown versions', () {
    for (final value in [
      '{',
      'null',
      '[]',
      '{}',
      '{"schemaVersion":2}',
      '{"schemaVersion":0}',
      '{"schemaVersion":1.0}',
    ]) {
      expect(() => codec.decode(value), throwsFormatException);
    }
  });

  test('rejects invalid nested data instead of guessing defaults', () {
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (p) => p.remove('tracks'),
      (p) => p['width'] = '1920',
      (p) => p['height'] = 0,
      (p) => p['videoClips'] = [],
      (p) => p['tracks'][0]['kind'] = 'unsupported',
      (p) => p['tracks'][0]['clips'][0]['sourceInUs'] = -1,
      (p) => p['tracks'][0]['clips'][0]['sourceOutUs'] = 10000001,
      (p) => p['tracks'][0]['clips'][0]['speedDenominator'] = 0,
      (p) => p['tracks'][0]['clips'][0]['timelineStartUs'] = 0.5,
      (p) => p['tracks'][0]['clips'][0]['volume'] = 2,
      (p) => p['stickerOverlays'][0]['assetId'] = '',
    ]) {
      final document =
          jsonDecode(codec.encode(project)) as Map<String, dynamic>;
      mutate(document['project'] as Map<String, dynamic>);
      expect(() => codec.decode(jsonEncode(document)), throwsFormatException);
    }
  });

  group('atomic project files', () {
    late Directory directory;
    late String path;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('vn-editor-test-');
      path = '${directory.path}/project.json';
    });
    tearDown(() => directory.delete(recursive: true));

    test('save, close ownership, reopen preserves the document', () async {
      await EditorProjectFile(path).save(project);
      final loaded = await EditorProjectFile(path).load();
      expect(codec.encode(loaded), codec.encode(project));
      expect(await directory.list().length, 1);
    });

    test(
      'queued saves are ordered and load waits for preceding writes',
      () async {
        final file = EditorProjectFile(path);
        final first = file.save(project);
        final second = file.save(timelineProject());
        final loaded = file.load();
        await Future.wait([first, second]);
        expect(codec.encode(await loaded), codec.encode(timelineProject()));
        expect(await directory.list().length, 1);
      },
    );

    test(
      'missing/corrupt files report errors and the queue recovers',
      () async {
        final file = EditorProjectFile(path);
        await expectLater(file.load(), throwsA(isA<FileSystemException>()));
        await File(path).writeAsString('{');
        await expectLater(file.load(), throwsFormatException);
        await file.save(project);
        expect((await file.load()).id, project.id);
      },
    );

    test('missing parent does not get silently created; retry works', () async {
      final file = EditorProjectFile('${directory.path}/missing/project.json');
      await expectLater(
        file.save(project),
        throwsA(isA<FileSystemException>()),
      );
      await Directory('${directory.path}/missing').create();
      await file.save(project);
      expect((await file.load()).id, project.id);
    });

    test(
      'failed replacement cleans temporary files and preserves destination',
      () async {
        await Directory(path).create();
        await File('$path/keep.txt').writeAsString('keep');
        await expectLater(
          EditorProjectFile(path).save(project),
          throwsA(isA<FileSystemException>()),
        );
        expect(await File('$path/keep.txt').readAsString(), 'keep');
        expect(await directory.list().length, 1);
      },
    );

    test(
      'oversized save preserves previous file and rejects oversized load',
      () async {
        final file = EditorProjectFile(path);
        await file.save(project);
        final tooLarge = project.copyWith(
          textOverlays: [
            TextOverlay(
              id: 'big',
              text: 'x' * EditorProjectFile.maxDocumentBytes,
            ),
          ],
        );
        await expectLater(file.save(tooLarge), throwsFormatException);
        expect(codec.encode(await file.load()), codec.encode(project));
        final oversized = File('${directory.path}/oversized.json');
        final handle = await oversized.open(mode: FileMode.write);
        await handle.truncate(EditorProjectFile.maxDocumentBytes + 1);
        await handle.close();
        await expectLater(
          EditorProjectFile(oversized.path).load(),
          throwsFormatException,
        );
      },
    );
  });
}
