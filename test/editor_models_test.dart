import 'package:flutter_test/flutter_test.dart';
import 'package:vn_editor/vn_editor.dart';

void main() {
  group('EditorProject', () {
    test('creates a valid empty project', () {
      final project = EditorProject.empty(
        id: 'test',
        width: 1080,
        height: 1920,
        frameRate: 30,
      );

      expect(project.videoClips, isEmpty);
      expect(project.frameRate, 30);
    });

    test('rejects empty IDs', () {
      expect(
        () => EditorProject.empty(
          id: ' ',
          width: 1080,
          height: 1920,
          frameRate: 30,
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid dimensions and frame rates', () {
      expect(
        () => EditorProject.empty(width: 0, height: 1920, frameRate: 30),
        throwsArgumentError,
      );
      expect(
        () => EditorProject.empty(
          width: 1080,
          height: 1920,
          frameRate: double.nan,
        ),
        throwsArgumentError,
      );
    });
  });

  test('project collections are defensive immutable snapshots', () {
    final clips = <VideoClip>[
      const VideoClip(id: 'clip', sourcePath: '/clip.mp4'),
    ];
    final project = EditorProject(
      id: 'test',
      width: 1080,
      height: 1920,
      frameRate: 30,
      videoClips: clips,
    );
    clips.clear();
    expect(project.videoClips, hasLength(1));
    expect(() => project.videoClips.clear(), throwsUnsupportedError);
  });

  test('effect parameters are immutable and reject non-finite values', () {
    final parameters = {'amount': 0.5};
    final effect = EditorEffect(
      id: 'one',
      effectId: 'grain',
      parameters: parameters,
    );
    parameters['amount'] = 1;
    expect(effect.parameters['amount'], 0.5);
    expect(() => effect.parameters.clear(), throwsUnsupportedError);
    expect(
      () => EditorEffect(
        id: 'one',
        effectId: 'grain',
        parameters: {'amount': double.nan},
      ),
      throwsArgumentError,
    );
    expect(() => EditorEffect(id: 'one', effectId: ''), throwsArgumentError);
    expect(
      () => EditorExportSettings(outputPath: '/out', container: ''),
      throwsArgumentError,
    );
  });

  group('effect validation', () {
    test('accepts boundary intensities', () {
      expect(
        EditorEffect(id: 'a', effectId: 'grain', intensity: 0).intensity,
        0,
      );
      expect(
        EditorFilter(
          id: 'b',
          name: 'Warm',
          shaderId: 'warm',
          intensity: 1,
        ).intensity,
        1,
      );
    });

    test('rejects out-of-range and non-finite intensities', () {
      expect(
        () => EditorEffect(id: 'a', effectId: 'grain', intensity: -0.1),
        throwsArgumentError,
      );
      expect(
        () => EditorEffect(
          id: 'a',
          effectId: 'grain',
          intensity: double.infinity,
        ),
        throwsArgumentError,
      );
    });
  });

  group('EditorExportSettings', () {
    test('provides production-safe defaults', () {
      final settings = EditorExportSettings(outputPath: '/tmp/out.mp4');
      expect(settings.videoCodec, 'h264');
      expect(settings.container, 'mp4');
      expect(settings.videoBitrate, 12000000);
    });

    test('rejects empty paths and invalid numeric values', () {
      expect(() => EditorExportSettings(outputPath: ' '), throwsArgumentError);
      expect(
        () => EditorExportSettings(outputPath: '/tmp/out.mp4', frameRate: 0),
        throwsArgumentError,
      );
    });
  });
}
