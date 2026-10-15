import Flutter
import AVFoundation
import UIKit
import Metal

@MainActor
public final class VnEditorPlugin: NSObject, @preconcurrency FlutterPlugin, @preconcurrency VnEditorHostApi {
  private var initialized = false
  private var sessionId = ""
  private var requestId: Int64 = 0
  private var generation = 0
  private var events: VnEditorFlutterApi?
  private var player: AVPlayer?
  private var asset: AVAsset?
  private var strips: MediaStrips?
  private var projectWidth: Int64 = 0
  private var projectHeight: Int64 = 0
  private var projectRate: Double = 30
  private var playIntent = 0
  private weak var preview: PreviewView?
  private var metadata: NativeMediaMetadata?
  private var pending: ((Result<NativeMediaMetadata, Error>) -> Void)?
  private var loading: Task<Void, Never>?
  private var timeout: DispatchWorkItem?
  private var observations: [NSKeyValueObservation] = []
  private var notifications: [NSObjectProtocol] = []
  private var timeObserver: Any?
  private var ended = false
  private var sourceInstruction: GpuInstruction?
  private var sourceEffects: [NativeEffectConfiguration] = []
  private var exporter: ProofExporter?
  private var frameGenerator: AVAssetImageGenerator?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = VnEditorPlugin()
    instance.events = VnEditorFlutterApi(binaryMessenger: registrar.messenger())
    VnEditorHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    registrar.register(PreviewFactory(plugin: instance), withId: "vn_editor/preview")
    registrar.publish(instance)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    try? disposeEditor()
    VnEditorHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
    events = nil
  }

  func initialize(configuration: NativeProjectConfiguration) throws {
    guard !initialized else { throw failure("editor-in-use", "An editor is already active.") }
    guard !configuration.projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      configuration.width > 0, configuration.height > 0, configuration.frameRate.isFinite, configuration.frameRate > 0 else {
      throw failure("invalid-project", "Project ID, dimensions and frame rate must be valid.")
    }
    sessionId = configuration.sessionId
    projectWidth = configuration.width
    projectHeight = configuration.height
    projectRate = configuration.frameRate
    strips = MediaStrips()
    initialized = true
  }

  func disposeEditor() throws {
    exporter?.cancel(); exporter = nil
    releaseMedia()
    strips?.close(); strips = nil
    preview = nil
    initialized = false
    sessionId = ""
  }

  private func releaseMedia() {
    frameGenerator?.cancelAllCGImageGeneration(); frameGenerator = nil
    sourceInstruction = nil
    sourceEffects = []
    generation += 1
    playIntent += 1
    asset?.cancelLoading()
    asset = nil
    loading?.cancel()
    loading = nil
    timeout?.cancel()
    timeout = nil
    observations.removeAll()
    notifications.forEach { NotificationCenter.default.removeObserver($0) }
    notifications.removeAll()
    if let observer = timeObserver { player?.removeTimeObserver(observer) }
    timeObserver = nil
    player?.pause()
    preview?.playerLayer.player = nil
    player?.replaceCurrentItem(with: nil)
    player = nil
    metadata = nil
    ended = false
    let completion = pending
    pending = nil
    completion?(.failure(failure("operation-cancelled", "Media loading was replaced or disposed.")))
  }

  func openMedia(path: String, requestId: Int64, completion: @escaping (Result<NativeMediaMetadata, Error>) -> Void) {
    open(path: path, segments: nil, requestId: requestId, completion: completion)
  }

  func openComposition(segments: [NativeTimelineSegment], requestId: Int64, completion: @escaping (Result<NativeMediaMetadata, Error>) -> Void) {
    open(path: "vn-editor:timeline", segments: segments, requestId: requestId, completion: completion)
  }

  func loadMediaStrip(path: String, startUs: Int64, endUs: Int64, thumbnailCount: Int64, requestId: Int64, completion: @escaping (Result<NativeMediaStrip, Error>) -> Void) {
    do {
      try requireInitialized()
      guard let strips else { throw failure("not-initialized", "No preview decoder.") }
      strips.load(path: path, start: startUs, end: endUs, count: thumbnailCount, id: requestId, completion: completion)
    } catch { completion(.failure(error)) }
  }
  func cancelMediaStrip(requestId: Int64) throws { strips?.cancel(requestId) }

  private func open(path: String, segments: [NativeTimelineSegment]?, requestId: Int64, completion: @escaping (Result<NativeMediaMetadata, Error>) -> Void) {
    do { try requireInitialized() } catch { completion(.failure(error)); return }
    releaseMedia()
    self.requestId = requestId
    pending = completion
    emit(.loading)
    let token = generation
    let deadline = DispatchWorkItem { [weak self] in
      guard let self, self.generation == token, self.pending != nil else { return }
      self.fail("media-timeout", "The video did not become ready within 30 seconds.")
    }
    timeout = deadline
    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: deadline)
    loading = Task { @MainActor [weak self] in
      guard let self, self.generation == token, !Task.isCancelled else { return }
      do {
        let item: AVPlayerItem
        if let segments {
          let built = try await buildTimeline(segments, width: self.projectWidth, height: self.projectHeight, frameRate: self.projectRate)
          try Task.checkCancellation()
          guard self.generation == token else { return }
          self.asset = built.0
          item = built.1
          self.metadata = built.2
        } else {
        let url = try localMediaURL(path)
        let asset = AVURLAsset(url: url)
        self.asset = asset
        let duration = try await asset.load(.duration)
        let playable = try await asset.load(.isPlayable)
        let protected = try await asset.load(.hasProtectedContent)
        let videos = try await asset.loadTracks(withMediaType: .video)
        guard playable, !protected, let video = videos.first, duration.seconds.isFinite,
          duration.seconds > 0, duration.seconds < Double(Int64.max / 1000) else {
          throw self.failure("unsupported-media", "A finite, decodable video track is required.")
        }
        let size = try await video.load(.naturalSize)
        guard !(try await video.load(.mediaCharacteristics)).contains(.containsHDRVideo) else { throw self.failure("unsupported-media", "Renderer v1 supports SDR video only.") }
        let transform = try await video.load(.preferredTransform)
        let rate = try await video.load(.nominalFrameRate)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let display = size.applying(transform)
        guard display.width.isFinite, display.height.isFinite,
          (1...32768).contains(abs(display.width)), (1...32768).contains(abs(display.height)) else {
          throw self.failure("unsupported-media", "The video dimensions are invalid.")
        }
        try Task.checkCancellation()
        guard self.initialized, self.generation == token else { return }
        self.metadata = NativeMediaMetadata(path: path, durationMilliseconds: Int64((duration.seconds * 1000).rounded()),
          width: Int64(abs(display.width).rounded()), height: Int64(abs(display.height).rounded()),
          hasAudio: !audio.isEmpty, frameRate: rate.isFinite && rate > 0 ? Double(rate) : nil)
        item = AVPlayerItem(asset: asset)
        let composition = AVMutableVideoComposition()
        composition.customVideoCompositorClass = GpuVideoCompositor.self
        composition.renderSize = CGSize(width: abs(display.width), height: abs(display.height))
        composition.frameDuration = CMTime(seconds: 1 / Double(rate > 0 ? rate : 30), preferredTimescale: 60000)
        let bounds = CGRect(origin: .zero, size: size).applying(transform)
        let instruction = GpuInstruction(range: CMTimeRange(start: .zero, duration: duration), trackID: video.trackID, transform: transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)))
        self.sourceInstruction = instruction
        composition.instructions = [instruction]
        item.videoComposition = composition
        }
        let current = AVPlayer(playerItem: item)
        self.player = current
        self.preview?.playerLayer.player = current
        self.observations = [
          item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
            DispatchQueue.main.async {
              guard let self, let item, self.generation == token else { return }
              switch item.status {
              case .readyToPlay:
                if let result = self.metadata, let done = self.pending {
                  self.pending = nil
                  self.timeout?.cancel()
                  self.timeout = nil
                  self.emit(.ready)
                  done(.success(result))
                }
              case .failed: self.fail("playback-failed", "The video could not be decoded. Try another local video.")
              default: break
              }
            }
          },
          current.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
              guard let self, self.generation == token else { return }
              self.emit()
            }
          }
        ]
        self.timeObserver = current.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 5), queue: .main) { [weak self] _ in
          MainActor.assumeIsolated {
            guard let self, self.generation == token else { return }
            self.emit()
          }
        }
        let center = NotificationCenter.default
        self.notifications = [
          center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
              guard let self, self.generation == token else { return }
              self.ended = true
              self.emit(.ended)
            }
          },
          center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
              guard let self, self.generation == token else { return }
              self.fail("playback-failed", "Playback stopped because the video could not be decoded.")
            }
          },
          center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.suspendPlayback() } },
          center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.suspendPlayback() } },
          center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            if (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
              MainActor.assumeIsolated { self?.suspendPlayback() }
            }
          }
        ]
      } catch {
        guard self.generation == token else { return }
        let pigeon = error as? PigeonError
        self.fail(pigeon?.code ?? "media-open-failed", pigeon?.message ?? "The video could not be opened.")
      }
    }
  }

  private func fail(_ code: String, _ message: String) {
    let completion = pending
    pending = nil
    releaseMedia()
    emit(.failed, error: message)
    completion?(.failure(failure(code, message)))
  }

  private func emit(_ status: NativePlaybackStatus? = nil, error: String? = nil) {
    guard initialized else { return }
    let position = player?.currentTime().seconds ?? 0
    let buffered = player?.currentItem?.loadedTimeRanges.last?.timeRangeValue.end.seconds ?? 0
    let actual: NativePlaybackStatus = status ?? (ended ? .ended :
      pending != nil || player?.timeControlStatus == .waitingToPlayAtSpecifiedRate ? .loading :
      player?.timeControlStatus == .playing ? .playing : player == nil ? .idle : .paused)
    events?.onPlaybackStateChanged(event: NativePlaybackEvent(status: actual,
      positionMilliseconds: milliseconds(position), bufferedPositionMilliseconds: milliseconds(buffered),
      sessionId: sessionId, requestId: requestId, errorMessage: error)) { _ in }
  }

  private func milliseconds(_ seconds: Double) -> Int64 {
    guard seconds.isFinite, seconds > 0, seconds < Double(Int64.max / 1000) else { return 0 }
    return Int64((seconds * 1000).rounded())
  }

  func play() throws {
    let current = try requireMedia()
    playIntent += 1
    let intent = playIntent
    if ended {
      let token = generation
      ended = false
      current.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak current] finished in
        DispatchQueue.main.async {
          guard finished, let self, self.generation == token, self.playIntent == intent else { return }
          current?.play()
        }
      }
    } else { current.play() }
  }

  func pause() throws { playIntent += 1; try requireMedia().pause(); emit() }

  private func suspendPlayback() {
    playIntent += 1
    player?.pause()
    emit()
  }

  func seekTo(positionMilliseconds: Int64) throws {
    try requireInitialized()
    guard positionMilliseconds >= 0 else { throw failure("invalid-position", "Seek position must not be negative.") }
    let current = try requireMedia()
    playIntent += 1
    guard positionMilliseconds <= (metadata?.durationMilliseconds ?? 0) else {
      throw failure("invalid-position", "Seek position exceeds the source duration.")
    }
    ended = false
    let token = generation
    current.seek(to: CMTime(value: positionMilliseconds, timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
      DispatchQueue.main.async {
        guard finished, let self, self.generation == token else { return }
        self.emit()
      }
    }
  }

  private func requireMedia() throws -> AVPlayer {
    try requireInitialized()
    guard let player, pending == nil, player.currentItem?.status == .readyToPlay else {
      throw failure("no-media", "Open a video and wait until it is ready.")
    }
    return player
  }
  private func requireInitialized() throws {
    guard initialized else { throw failure("not-initialized", "Initialize the editor before sending commands.") }
  }
  private func failure(_ code: String, _ message: String) -> PigeonError {
    PigeonError(code: code, message: message, details: nil)
  }
  func applyEffect(effect: NativeEffectConfiguration, completion: @escaping (Result<Void, Error>) -> Void) {
    do {
    let next = sourceEffects.contains { $0.instanceId == effect.instanceId } ? sourceEffects.map { $0.instanceId == effect.instanceId ? effect : $0 } : sourceEffects + [effect]
    try validateEffects(next)
    try setSourceEffects(next)
    completion(.success(()))
    } catch { completion(.failure(error)) }
  }
  func removeEffect(effectId: String, completion: @escaping (Result<Void, Error>) -> Void) {
    do { try setSourceEffects(sourceEffects.filter { $0.instanceId != effectId }); completion(.success(())) }
    catch { completion(.failure(error)) }
  }
  private func setSourceEffects(_ effects: [NativeEffectConfiguration]) throws {
    let current = try requireMedia()
    guard let original = sourceInstruction, let composition = current.currentItem?.videoComposition?.mutableCopy() as? AVMutableVideoComposition else { throw failure("timeline-edit-required", "Use project commands to edit timeline effects.") }
    composition.instructions = [GpuInstruction(range: original.timeRange, trackID: original.trackID, transform: original.transform, effects: effects)]
    current.currentItem?.videoComposition = composition
    sourceEffects = effects
    current.seek(to: current.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
  }
  func supportedEffects() throws -> [String] { try requireInitialized(); return MTLCreateSystemDefaultDevice() == nil ? [] : effectSpecs.map(\.id) }
  func capturePreviewFrame(completion: @escaping (Result<String, Error>) -> Void) {
    do {
      let current = try requireMedia()
      guard frameGenerator == nil, let item = current.currentItem else { throw failure("capture-in-progress", "Wait for the current frame capture.") }
      let generator = AVAssetImageGenerator(asset: item.asset)
      generator.videoComposition = item.videoComposition
      generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
      generator.maximumSize = CGSize(width: 1920, height: 1920)
      frameGenerator = generator
      let token = generation
      generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: current.currentTime())]) { [weak self] _, image, _, _, error in
        let result: Result<String, Error> = Result {
          guard let image, let data = UIImage(cgImage: image).pngData() else { throw error ?? gpuError("capture-failed", "No rendered frame.") }
          let url = FileManager.default.temporaryDirectory.appendingPathComponent("vn-frame-\(UUID().uuidString).png")
          try data.write(to: url, options: .atomic)
          return url.path
        }
        DispatchQueue.main.async {
          guard let self, self.generation == token else {
            if case .success(let path) = result { try? FileManager.default.removeItem(atPath: path) }
            completion(.failure(gpuError("operation-cancelled", "Frame capture cancelled."))); return
          }
          self.frameGenerator = nil; completion(result)
        }
      }
    } catch { completion(.failure(error)) }
  }
  func startExport(configuration: NativeExportConfiguration, completion: @escaping (Result<String, Error>) -> Void) {
    do {
      let current = try requireMedia()
      guard exporter == nil, let item = current.currentItem, let metadata else { throw failure("export-in-progress", "Wait for the current export.") }
      let job = ProofExporter()
      exporter = job
      do {
        try job.start(item: item, configuration: configuration, metadata: metadata) { [weak self] result in
          if self?.exporter === job { self?.exporter = nil }
          completion(result)
        }
      } catch { if exporter === job { exporter = nil }; throw error }
    } catch { completion(.failure(error)) }
  }
  func cancelExport(exportId: String) throws {
    try requireInitialized()
    guard let job = exporter else { return }
    guard job.outputPath == exportId else { throw failure("invalid-export", "The export path does not identify the active job.") }
    job.cancel()
  }

  fileprivate func attach(_ view: PreviewView, session: String) {
    guard initialized, session == sessionId else { return }
    preview?.playerLayer.player = nil
    preview = view
    view.playerLayer.player = player
  }
}

private final class PreviewView: UIView, FlutterPlatformView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }
  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
  func view() -> UIView { self }
}

@MainActor
private final class PreviewFactory: NSObject, @preconcurrency FlutterPlatformViewFactory {
  weak var plugin: VnEditorPlugin?
  init(plugin: VnEditorPlugin) { self.plugin = plugin }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let view = PreviewView(frame: frame)
    #if targetEnvironment(simulator)
    // The simulator's CoreAnimation image queue cannot display every format
    // selected by the system video compositor. Keep conversion entirely native.
    view.playerLayer.pixelBufferAttributes = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    #endif
    view.playerLayer.videoGravity = .resizeAspect
    view.backgroundColor = .black
    plugin?.attach(view, session: (args as? [String: Any])?["sessionId"] as? String ?? "")
    return view
  }
}
