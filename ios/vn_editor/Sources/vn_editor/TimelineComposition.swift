import AVFoundation

/// Native cut composition: AVPlayer owns the edited clock, including gaps.
@MainActor
func buildTimeline(_ segments: [NativeTimelineSegment], width: Int64, height: Int64, frameRate: Double) async throws -> (AVMutableComposition, AVPlayerItem, NativeMediaMetadata) {
  func invalid(_ message: String) -> PigeonError { PigeonError(code: "invalid-composition", message: message, details: nil) }
  guard !segments.isEmpty, segments.count <= 256 else { throw invalid("Expected 1–256 video clips.") }
  let composition = AVMutableComposition()
  guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
        let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw invalid("Composition tracks unavailable.") }
  let videoComposition = AVMutableVideoComposition()
  videoComposition.customVideoCompositorClass = GpuVideoCompositor.self
  // Phase 3 composition output is explicitly SDR; HDR parity is a later gate.
  videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
  videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
  videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
  videoComposition.renderSize = CGSize(width: CGFloat(width), height: CGFloat(height))
  videoComposition.frameDuration = CMTime(seconds: 1 / frameRate, preferredTimescale: 60000)
  let mix = AVMutableAudioMix()
  let volume = AVMutableAudioMixInputParameters(track: audio)
  var instructions: [GpuInstruction] = []
  var end: Int64 = 0
  var hasAudio = false
  func time(_ value: Int64) -> CMTime { CMTime(value: value, timescale: 1_000_000) }
  for clip in segments {
    try Task.checkCancellation()
    try validateEffects(clip.effects)
    guard clip.startUs >= end, clip.durationUs >= 1000, clip.sourceInUs >= 0, clip.sourceOutUs > clip.sourceInUs,
          clip.durationUs <= 86_400_000_000, clip.startUs <= 86_400_000_000 - clip.durationUs,
          clip.speed.isFinite, (0.25...4).contains(clip.speed), clip.volume.isFinite, (0...1).contains(clip.volume),
          abs(Double(clip.sourceOutUs - clip.sourceInUs) / clip.speed - Double(clip.durationUs)) <= 2 else { throw invalid("Invalid timeline interval, speed or volume.") }
    let asset = AVURLAsset(url: try localMediaURL(clip.path))
    let sourceDuration = try await asset.load(.duration)
    guard sourceDuration.seconds.isFinite, Double(clip.sourceOutUs) <= sourceDuration.seconds * 1_000_000 + 1,
          let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { throw invalid("A clip exceeds its source or has no video track.") }
    let sourceRange = CMTimeRange(start: time(clip.sourceInUs), end: time(clip.sourceOutUs))
    guard !(try await sourceVideo.load(.mediaCharacteristics)).contains(.containsHDRVideo) else { throw invalid("Renderer v1 supports SDR video only.") }
    let destination = time(clip.startUs)
    if clip.startUs > end {
      let gap = GpuInstruction(range: CMTimeRange(start: time(end), end: destination), trackID: kCMPersistentTrackID_Invalid)
      instructions.append(gap)
    }
    try video.insertTimeRange(sourceRange, of: sourceVideo, at: destination)
    video.scaleTimeRange(CMTimeRange(start: destination, duration: sourceRange.duration), toDuration: time(clip.durationUs))
    if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
      let available = try await sourceAudio.load(.timeRange)
      let range = CMTimeRangeGetIntersection(sourceRange, otherRange: available)
      if range.duration.seconds > 0 {
        let offset = CMTimeSubtract(range.start, sourceRange.start).seconds / clip.speed
        let audioStart = CMTimeAdd(destination, CMTime(seconds: offset, preferredTimescale: 1_000_000))
        try audio.insertTimeRange(range, of: sourceAudio, at: audioStart)
        audio.scaleTimeRange(CMTimeRange(start: audioStart, duration: range.duration), toDuration: CMTime(seconds: range.duration.seconds / clip.speed, preferredTimescale: 1_000_000))
        volume.setVolume(Float(clip.volume), at: audioStart)
        hasAudio = true
      }
    }
    let size = try await sourceVideo.load(.naturalSize)
    let preferred = try await sourceVideo.load(.preferredTransform)
    let bounds = CGRect(origin: .zero, size: size).applying(preferred)
    guard bounds.width > 0, bounds.height > 0 else { throw invalid("Invalid source dimensions.") }
    let scale = min(CGFloat(width) / bounds.width, CGFloat(height) / bounds.height)
    let transform = preferred.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
      .concatenating(CGAffineTransform(scaleX: scale, y: scale))
      .concatenating(CGAffineTransform(translationX: (CGFloat(width) - bounds.width * scale) / 2, y: (CGFloat(height) - bounds.height * scale) / 2))
    let instruction = GpuInstruction(range: CMTimeRange(start: destination, duration: time(clip.durationUs)), trackID: video.trackID, transform: transform, effects: clip.effects)
    instructions.append(instruction)
    end = clip.startUs + clip.durationUs
  }
  videoComposition.instructions = instructions
  mix.inputParameters = [volume]
  let item = AVPlayerItem(asset: composition)
  item.videoComposition = videoComposition
  item.audioMix = mix
  item.audioTimePitchAlgorithm = .spectral
  return (composition, item, NativeMediaMetadata(path: "vn-editor:timeline", durationMilliseconds: end / 1000, width: width, height: height, hasAudio: hasAudio, frameRate: frameRate))
}
