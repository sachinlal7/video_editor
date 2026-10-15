import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/platform/vn_editor_api.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/src/main/kotlin/com/sachinlal/vn_editor/VnEditorApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.sachinlal.vn_editor'),
    swiftOut: 'ios/vn_editor/Sources/vn_editor/VnEditorApi.g.swift',
    swiftOptions: SwiftOptions(),
    dartPackageName: 'vn_editor',
  ),
)
enum NativePlaybackStatus {
  idle,
  loading,
  ready,
  playing,
  paused,
  ended,
  failed,
}

class NativeProjectConfiguration {
  NativeProjectConfiguration({
    required this.projectId,
    required this.width,
    required this.height,
    required this.frameRate,
    this.sessionId = '',
  });
  String projectId;
  int width;
  int height;
  double frameRate;
  String sessionId;
}

class NativeEffectConfiguration {
  NativeEffectConfiguration({
    required this.effectId,
    required this.parameters,
    required this.intensity,
    this.instanceId = '',
  });
  String effectId;
  Map<String, double> parameters;
  double intensity;
  String instanceId;
}

class NativeExportConfiguration {
  NativeExportConfiguration({
    required this.outputPath,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.videoBitrate,
    required this.videoCodec,
    required this.container,
  });
  String outputPath;
  int width;
  int height;
  int frameRate;
  int videoBitrate;
  String videoCodec;
  String container;
}

class NativePlaybackEvent {
  NativePlaybackEvent({
    required this.status,
    required this.positionMilliseconds,
    required this.bufferedPositionMilliseconds,
    this.sessionId = '',
    this.requestId = 0,
    this.errorMessage,
  });
  NativePlaybackStatus status;
  int positionMilliseconds;
  int bufferedPositionMilliseconds;
  String sessionId;
  int requestId;
  String? errorMessage;
}

class NativeExportEvent {
  NativeExportEvent({
    required this.exportId,
    required this.progress,
    required this.isComplete,
    this.outputPath,
  });
  String exportId;
  double progress;
  bool isComplete;
  String? outputPath;
}

class NativeEditorError {
  NativeEditorError({
    required this.code,
    required this.message,
    required this.isRecoverable,
    this.details,
  });
  String code;
  String message;
  bool isRecoverable;
  String? details;
}

class NativeMediaMetadata {
  NativeMediaMetadata({
    required this.path,
    required this.durationMilliseconds,
    required this.width,
    required this.height,
    required this.hasAudio,
    this.frameRate,
  });
  String path;
  int durationMilliseconds;
  int width;
  int height;
  bool hasAudio;
  double? frameRate;
}

@HostApi()
abstract class VnEditorHostApi {
  void initialize(NativeProjectConfiguration configuration);
  void disposeEditor();
  @asyncCallback
  NativeMediaMetadata openMedia(String path, int requestId);
  @asyncCallback
  NativeMediaMetadata openComposition(
    List<NativeTimelineSegment> segments,
    int requestId,
  );
  @asyncCallback
  NativeMediaStrip loadMediaStrip(
    String path,
    int startUs,
    int endUs,
    int thumbnailCount,
    int requestId,
  );
  void cancelMediaStrip(int requestId);
  void play();
  void pause();
  void seekTo(int positionMilliseconds);
  @asyncCallback
  void applyEffect(NativeEffectConfiguration effect);
  @asyncCallback
  void removeEffect(String effectId);
  List<String> supportedEffects();
  @asyncCallback
  String capturePreviewFrame();
  @asyncCallback
  String startExport(NativeExportConfiguration configuration);
  void cancelExport(String exportId);
}

class NativeTimelineSegment {
  NativeTimelineSegment({
    required this.path,
    required this.sourceInUs,
    required this.sourceOutUs,
    required this.startUs,
    required this.durationUs,
    required this.speed,
    required this.volume,
    this.effects = const [],
  });
  String path;
  int sourceInUs;
  int sourceOutUs;
  int startUs;
  int durationUs;
  double speed;
  double volume;
  List<NativeEffectConfiguration> effects;
}

class NativeMediaStrip {
  NativeMediaStrip({required this.thumbnails, required this.peaks});
  List<String> thumbnails;
  List<double> peaks;
}

@FlutterApi()
abstract class VnEditorFlutterApi {
  @asyncCallback
  void onPlaybackStateChanged(NativePlaybackEvent event);
  @asyncCallback
  void onExportProgress(NativeExportEvent event);
  @asyncCallback
  void onError(NativeEditorError error);
}
