import AVFoundation

/// Bounded foreground proof export using the preview's exact compositor.
@MainActor
final class ProofExporter {
  private(set) var outputPath: String?
  private var session: AVAssetExportSession?
  private var deadline: DispatchWorkItem?
  private var cancelled = false
  func start(item: AVPlayerItem, configuration: NativeExportConfiguration, metadata: NativeMediaMetadata, completion: @escaping (Result<String, Error>) -> Void) throws {
    let output = URL(fileURLWithPath: configuration.outputPath)
    guard (2...1920).contains(metadata.width), (2...1920).contains(metadata.height) else { throw gpuError("unsupported-export", "Verification dimensions must be between 2 and 1920 pixels per side.") }
    guard configuration.frameRate == 30, configuration.videoBitrate == 12000000 else { throw gpuError("unsupported-export", "Custom frame rate and bitrate controls arrive with the full exporter. Verification uses native encoder quality at 30 fps.") }
    guard configuration.outputPath.hasPrefix("/"), !FileManager.default.fileExists(atPath: output.path), configuration.container == "mp4", configuration.videoCodec == "h264", configuration.width == metadata.width, configuration.height == metadata.height, metadata.width * metadata.height <= 1920 * 1080, metadata.durationMilliseconds <= 60_000, metadata.width % 2 == 0, metadata.height % 2 == 0 else { throw gpuError("unsupported-export", "Verification export requires a new local H.264 MP4 path, current render dimensions up to 1080p and at most 60 seconds.") }
    guard let session = AVAssetExportSession(asset: item.asset, presetName: AVAssetExportPresetHighestQuality) else { throw gpuError("export-unavailable", "No compatible encoder.") }
    self.session = session
    outputPath = output.path
    let temporary = output.deletingLastPathComponent().appendingPathComponent(".vn-export-\(UUID().uuidString).mp4")
    session.outputURL = temporary; session.outputFileType = .mp4
    if let composition = item.videoComposition?.mutableCopy() as? AVMutableVideoComposition {
      composition.frameDuration = CMTime(value: 1, timescale: 30)
      session.videoComposition = composition
    }
    session.audioMix = item.audioMix
    let timeout = DispatchWorkItem { [weak self] in self?.cancel() }
    deadline = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: timeout)
    session.exportAsynchronously { [self] in
      DispatchQueue.main.async {
        deadline?.cancel(); deadline = nil
        let result = Result<String, Error> {
          guard !cancelled, session.status == .completed else { throw gpuError(cancelled ? "operation-cancelled" : "export-failed", cancelled ? "Verification export cancelled." : "The device could not encode the verification video.") }
          try FileManager.default.moveItem(at: temporary, to: output)
          return output.path
        }
        try? FileManager.default.removeItem(at: temporary)
        self.session = nil
        completion(result)
      }
    }
  }
  func cancel() { cancelled = true; session?.cancelExport() }
}
