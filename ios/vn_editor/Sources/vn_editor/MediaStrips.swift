import AVFoundation
import UIKit

func localMediaURL(_ path: String) throws -> URL {
  let url: URL
  if path.hasPrefix("/") { url = URL(fileURLWithPath: path) }
  else if let parsed = URL(string: path), parsed.isFileURL { url = parsed }
  else { throw PigeonError(code: "invalid-path", message: "Use an absolute local path or file URI.", details: nil) }
  guard FileManager.default.isReadableFile(atPath: url.path) else { throw PigeonError(code: "media-not-found", message: "Media is missing or unreadable.", details: nil) }
  return url
}

/// Session-scoped LRU. Worker decoders never send decoded image/audio buffers to Dart.
final class MediaStrips: @unchecked Sendable {
  private let queue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 2; return q }()
  private let lock = NSLock()
  private var closed = false
  private var jobs: [Int64: Bool] = [:]
  private var cache: [String: NativeMediaStrip] = [:]
  private var order: [String] = []
  private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vn-strips-\(UUID().uuidString)")

  init() { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
  func cancel(_ id: Int64) { lock.lock(); if jobs[id] != nil { jobs[id] = true }; lock.unlock() }
  func close() {
    lock.lock(); closed = true; cache.removeAll(); order.removeAll(); let empty = jobs.isEmpty; lock.unlock()
    if empty { try? FileManager.default.removeItem(at: directory) }
  }
  private func check(_ id: Int64, _ deadline: Date) throws {
    lock.lock(); let cancelled = closed || jobs[id] != false; lock.unlock()
    if cancelled { throw PigeonError(code: "operation-cancelled", message: "Preview cancelled.", details: nil) }
    if Date() > deadline { throw PigeonError(code: "preview-timeout", message: "Preview decoding exceeded 60 seconds.", details: nil) }
  }

  func load(path: String, start: Int64, end: Int64, count: Int64, id: Int64, completion: @escaping (Result<NativeMediaStrip, Error>) -> Void) {
    lock.lock()
    let valid = !closed && jobs[id] == nil && jobs.count < 34 && start >= 0 && end > start && end <= 86_400_000_000 && (0...8).contains(count)
    if valid { jobs[id] = false }
    lock.unlock()
    guard valid else { completion(.failure(PigeonError(code: "invalid-preview", message: "Invalid or unavailable preview request.", details: nil))); return }
    queue.addOperation { [self] in
      var outputs: [URL] = []
      let deadline = Date().addingTimeInterval(60)
      let result = Result<NativeMediaStrip, Error> {
        try check(id, deadline)
        let url = try localMediaURL(path)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let key = "\(url.path):\(attributes[.size]!):\(attributes[.modificationDate]!):\(start):\(end):\(count)"
        lock.lock()
        let existing = cache[key]
        if existing != nil { order.removeAll { $0 == key }; order.append(key) }
        lock.unlock()
        if let existing { return existing }
        let asset = AVURLAsset(url: url)
        defer { asset.cancelLoading() }
        guard asset.duration.seconds.isFinite, asset.duration.seconds > 0, Double(end) <= asset.duration.seconds * 1_000_000 + 1000 else { throw PigeonError(code: "invalid-preview", message: "Preview range exceeds the source.", details: nil) }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 90)
        defer { generator.cancelAllCGImageGeneration() }
        for index in 0..<count {
          try check(id, deadline)
          try autoreleasepool {
            let time = start + (end - start - 1) * index / max(1, count - 1)
            let image = try generator.copyCGImage(at: CMTime(value: time, timescale: 1_000_000), actualTime: nil)
            guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.75) else { throw PigeonError(code: "preview-failed", message: "JPEG encoding failed.", details: nil) }
            let output = directory.appendingPathComponent("\(UUID().uuidString).jpg")
            outputs.append(output)
            try data.write(to: output, options: .atomic)
          }
        }
        let peaks = try waveform(asset, start, end) { try self.check(id, deadline) }
        try check(id, deadline)
        let strip = NativeMediaStrip(thumbnails: outputs.map(\.path), peaks: peaks)
        lock.lock()
        if let existing = cache[key] {
          lock.unlock(); outputs.forEach { try? FileManager.default.removeItem(at: $0) }; return existing
        }
        cache[key] = strip; order.append(key)
        while order.count > 16 {
          let evicted = order.removeFirst()
          cache.removeValue(forKey: evicted)?.thumbnails.forEach { try? FileManager.default.removeItem(atPath: $0) }
        }
        lock.unlock()
        return strip
      }
      lock.lock()
      let cancelled = closed || jobs[id] != false
      jobs.removeValue(forKey: id)
      let cleanup = closed && jobs.isEmpty
      lock.unlock()
      if case .failure = result { outputs.forEach { try? FileManager.default.removeItem(at: $0) } }
      if cleanup { try? FileManager.default.removeItem(at: directory) }
      DispatchQueue.main.async {
        completion(cancelled ? .failure(PigeonError(code: "operation-cancelled", message: "Preview cancelled.", details: nil)) : result.mapError { ($0 as? PigeonError) ?? PigeonError(code: "preview-failed", message: "Media preview could not be decoded.", details: nil) })
      }
    }
  }

  private func waveform(_ asset: AVAsset, _ start: Int64, _ end: Int64, check: () throws -> Void) throws -> [Double] {
    guard let track = asset.tracks(withMediaType: .audio).first else { return [] }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw PigeonError(code: "unsupported-audio", message: "Audio PCM decoding is unavailable.", details: nil) }
    reader.add(output)
    reader.timeRange = CMTimeRange(start: CMTime(value: start, timescale: 1_000_000), end: CMTime(value: end, timescale: 1_000_000))
    guard reader.startReading() else { throw reader.error ?? PigeonError(code: "preview-failed", message: "Audio reader failed.", details: nil) }
    defer { reader.cancelReading() }
    var peaks = [Double](repeating: 0, count: 128)
    while reader.status == .reading {
      try check()
      let more: Bool = try autoreleasepool {
        guard let sample = output.copyNextSampleBuffer() else { return false }
        defer { CMSampleBufferInvalidate(sample) }
        guard let description = CMSampleBufferGetFormatDescription(sample), let format = CMAudioFormatDescriptionGetStreamBasicDescription(description), let block = CMSampleBufferGetDataBuffer(sample) else { throw PigeonError(code: "preview-failed", message: "Invalid decoded audio buffer.", details: nil) }
        let channels = Int(format.pointee.mChannelsPerFrame)
        let rate = format.pointee.mSampleRate
        guard channels > 0, rate > 0 else { throw PigeonError(code: "preview-failed", message: "Invalid audio format.", details: nil) }
        let bytes = CMBlockBufferGetDataLength(block)
        if bytes == 0 { return true }
        guard bytes % MemoryLayout<Float>.size == 0, bytes <= 16 * 1024 * 1024 else { throw PigeonError(code: "preview-failed", message: "Unexpected decoded audio buffer size.", details: nil) }
        var samples = [Float](repeating: 0, count: bytes / MemoryLayout<Float>.size)
        let status = samples.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes, destination: $0.baseAddress!) }
        guard status == kCMBlockBufferNoErr else { throw PigeonError(code: "preview-failed", message: "Audio buffer read failed.", details: nil) }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds * 1_000_000
        for (index, sample) in samples.enumerated() {
          let time = timestamp + Double(index / channels) * 1_000_000 / rate
          if time >= Double(start), time < Double(end), sample.isFinite {
            let bin = min(127, Int((time - Double(start)) / Double(end - start) * 128))
            peaks[bin] = max(peaks[bin], min(1, Double(abs(sample))))
          }
        }
        return true
      }
      if !more { break }
    }
    if reader.status == .failed { throw reader.error ?? PigeonError(code: "preview-failed", message: "Audio decoding failed.", details: nil) }
    return peaks
  }
}
