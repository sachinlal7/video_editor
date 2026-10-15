import AVFoundation
import Metal
import CoreImage

struct EffectParameter { let name: String; let min: Double; let max: Double; let value: Double }
struct EffectSpec { let id: String; let parameters: [EffectParameter] }
func validateEffects(_ effects: [NativeEffectConfiguration]) throws {
  guard effects.count <= 8 else { throw gpuError("invalid-effect", "At most eight GPU stages are supported.") }
  for effect in effects {
    guard let spec = effectSpecs.first(where: { $0.id == effect.effectId }) else { throw gpuError("unsupported-effect", "Unknown GPU effect: \(effect.effectId)") }
    guard effect.intensity.isFinite, (0...1).contains(effect.intensity) else { throw gpuError("invalid-effect", "Invalid intensity.") }
    for (key, value) in effect.parameters {
      guard let p = spec.parameters.first(where: { $0.name == key }), value.isFinite, (p.min...p.max).contains(value), effect.effectId != "lut" || value == value.rounded() else { throw gpuError("invalid-effect", "Invalid \(effect.effectId).\(key).") }
    }
  }
}
func gpuError(_ code: String, _ message: String) -> PigeonError { PigeonError(code: code, message: message, details: nil) }

/// One serial compositor owns a Metal pipeline, LUT and two reusable textures.
final class GpuRenderer {
  let device: MTLDevice
  let queue: MTLCommandQueue
  let context: CIContext
  let pipeline: MTLRenderPipelineState
  let lut: MTLTexture
  var cache: CVMetalTextureCache?
  var scratch: [MTLTexture] = []
  init() throws {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw gpuError("gpu-unavailable", "Metal is unavailable.") }
    self.device = device; self.queue = queue
    context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false, .workingColorSpace: NSNull()])
    let library = try device.makeLibrary(source: Self.shader, options: nil)
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "vertexMain")
    descriptor.fragmentFunction = library.makeFunction(name: "fragmentMain")
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    let texture = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 289, height: 68, mipmapped: false)
    texture.usage = .shaderRead
    guard let lut = device.makeTexture(descriptor: texture) else { throw gpuError("gpu-unavailable", "Cannot allocate LUT.") }
    self.lut = lut
    #if SWIFT_PACKAGE
    let bundle = Bundle.module
    #else
    guard let resourceURL = Bundle(for: GpuVideoCompositor.self).url(forResource: "vn_editor_resources", withExtension: "bundle"), let bundle = Bundle(url: resourceURL) else { throw gpuError("gpu-unavailable", "GPU resource bundle missing.") }
    #endif
    guard let url = bundle.url(forResource: "vn_editor_luts", withExtension: "rgba") else { throw gpuError("gpu-unavailable", "LUT resource missing.") }
    let data = try Data(contentsOf: url)
    guard data.count == 289 * 68 * 4 else { throw gpuError("gpu-unavailable", "Invalid LUT resource.") }
    data.withUnsafeBytes { lut.replace(region: MTLRegionMake2D(0, 0, 289, 68), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 289 * 4) }
    guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess else { throw gpuError("gpu-unavailable", "Cannot create texture cache.") }
  }
  func render(source: CVPixelBuffer?, output: CVPixelBuffer, instruction: GpuInstruction, time: Double) throws {
    let width = CVPixelBufferGetWidth(output), height = CVPixelBufferGetHeight(output)
    guard width > 0, height > 0, width <= 4096, height <= 4096 else { throw gpuError("unsupported-size", "GPU preview is limited to 4096 pixels per dimension.") }
    if scratch.first?.width != width || scratch.first?.height != height {
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
      descriptor.usage = [.shaderRead, .renderTarget, .shaderWrite]
      scratch = try (0..<2).map { _ in guard let value = device.makeTexture(descriptor: descriptor) else { throw gpuError("gpu-unavailable", "Cannot allocate render texture.") }; return value }
    }
    var wrapped: CVMetalTexture?
    guard let cache, CVMetalTextureCacheCreateTextureFromImage(nil, cache, output, nil, .bgra8Unorm, width, height, 0, &wrapped) == kCVReturnSuccess, let wrapped, let target = CVMetalTextureGetTexture(wrapped), let command = queue.makeCommandBuffer() else { throw gpuError("gpu-unavailable", "Cannot create frame target.") }
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    let black = CIImage(color: .black).cropped(to: bounds)
    let picture = source.map { CIImage(cvPixelBuffer: $0).transformed(by: instruction.transform).composited(over: black).cropped(to: bounds) } ?? black
    let stages = instruction.effects.filter { $0.intensity > 0 }
    // Core Image is bottom-left; Metal textures and the shared shader use top-left.
    let oriented = picture.transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(height)))
    context.render(oriented, to: stages.isEmpty ? target : scratch[0], commandBuffer: command, bounds: bounds, colorSpace: CGColorSpace(name: CGColorSpace.itur_709)!)
    for (index, effect) in stages.enumerated() {
      let destination = index == stages.count - 1 ? target : scratch[(index + 1) % 2]
      let pass = MTLRenderPassDescriptor()
      pass.colorAttachments[0].texture = destination
      pass.colorAttachments[0].loadAction = .dontCare
      pass.colorAttachments[0].storeAction = .store
      guard let encoder = command.makeRenderCommandEncoder(descriptor: pass), let kind = effectSpecs.firstIndex(where: { $0.id == effect.effectId }) else { throw gpuError("gpu-unavailable", "Cannot encode effect.") }
      var uniforms = [Float](repeating: 0, count: 16)
      for (i, p) in effectSpecs[kind].parameters.enumerated() { uniforms[i] = Float(effect.parameters[p.name] ?? p.value) }
      uniforms[8] = Float(kind + 1); uniforms[9] = Float(effect.intensity); uniforms[10] = Float(time)
      uniforms[11] = 1 / Float(width); uniforms[12] = 1 / Float(height)
      encoder.setRenderPipelineState(pipeline)
      encoder.setFragmentTexture(scratch[index % 2], index: 0)
      encoder.setFragmentTexture(lut, index: 1)
      encoder.setFragmentBytes(&uniforms, length: uniforms.count * MemoryLayout<Float>.size, index: 0)
      encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
      encoder.endEncoding()
    }
    command.commit(); command.waitUntilCompleted()
    if let error = command.error { throw error }
    withExtendedLifetime(wrapped) {}
  }
  private static let shader = """
  #include <metal_stdlib>
  using namespace metal;
  struct Vertex { float4 position [[position]]; float2 uv; };
  vertex Vertex vertexMain(uint id [[vertex_id]]) {
    float2 positions[4] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(1,1)};
    Vertex v; v.position = float4(positions[id],0,1); v.uv = float2(positions[id].x * 0.5 + 0.5, 0.5 - positions[id].y * 0.5); return v;
  }
  float3 cube(texture2d<float> lut, float3 v, float preset) {
    return lut.read(uint2(uint(v.b) * 17 + uint(v.r), uint(preset) * 17 + uint(v.g))).rgb;
  }
  float3 lookup(texture2d<float> lut, float3 c, float preset) {
    float3 v = c * 16.0; float3 lo = floor(v); float3 hi = min(lo + 1.0, float3(16.0)); float3 f = fract(v);
    return mix(mix(mix(cube(lut,lo,preset),cube(lut,float3(hi.r,lo.g,lo.b),preset),f.r),mix(cube(lut,float3(lo.r,hi.g,lo.b),preset),cube(lut,float3(hi.r,hi.g,lo.b),preset),f.r),f.g),mix(mix(cube(lut,float3(lo.r,lo.g,hi.b),preset),cube(lut,float3(hi.r,lo.g,hi.b),preset),f.r),mix(cube(lut,float3(lo.r,hi.g,hi.b),preset),cube(lut,hi,preset),f.r),f.g),f.b);
  }
  fragment float4 fragmentMain(Vertex in [[stage_in]], texture2d<float> source [[texture(0)]], texture2d<float> lut [[texture(1)]], constant float *p [[buffer(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = in.uv; int kind = int(p[8]); float intensity = p[9]; float time = p[10]; float2 pixel = float2(p[11],p[12]);
    #define SAMPLE(v) source.sample(s, v)
    #define LUT(v) lookup(lut, v, p[0])
    \(effectBody)
  }
  """
}

final class GpuInstruction: NSObject, AVVideoCompositionInstructionProtocol {
  let timeRange: CMTimeRange
  let enablePostProcessing = false
  let containsTweening = true
  let passthroughTrackID = kCMPersistentTrackID_Invalid
  let requiredSourceTrackIDs: [NSValue]?
  let trackID: CMPersistentTrackID
  let transform: CGAffineTransform
  let effects: [NativeEffectConfiguration]
  init(range: CMTimeRange, trackID: CMPersistentTrackID, transform: CGAffineTransform = .identity, effects: [NativeEffectConfiguration] = []) {
    timeRange = range; self.trackID = trackID; self.transform = transform; self.effects = effects
    requiredSourceTrackIDs = trackID == kCMPersistentTrackID_Invalid ? [] : [NSNumber(value: trackID)]
  }
}

final class GpuVideoCompositor: NSObject, AVVideoCompositing {
  let sourcePixelBufferAttributes: [String: Any]? = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferMetalCompatibilityKey as String: true]
  let requiredPixelBufferAttributesForRenderContext: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferMetalCompatibilityKey as String: true]
  private let queue = DispatchQueue(label: "vn_editor.gpu")
  private let lock = NSLock()
  private var generation = 0
  private var renderer: GpuRenderer?
  func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
  func cancelAllPendingVideoCompositionRequests() { lock.lock(); generation += 1; lock.unlock() }
  func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
    lock.lock(); let token = generation; lock.unlock()
    queue.async { [self] in
      autoreleasepool {
        lock.lock(); let cancelled = token != generation; lock.unlock()
        if cancelled { request.finishCancelledRequest(); return }
        do {
          guard let instruction = request.videoCompositionInstruction as? GpuInstruction, let output = request.renderContext.newPixelBuffer() else { throw gpuError("gpu-unavailable", "No render target.") }
          if renderer == nil { renderer = try GpuRenderer() }
          let source = instruction.trackID == kCMPersistentTrackID_Invalid ? nil : request.sourceFrame(byTrackID: instruction.trackID)
          if instruction.trackID != kCMPersistentTrackID_Invalid && source == nil { throw gpuError("missing-frame", "Source video frame unavailable.") }
          try renderer!.render(source: source, output: output, instruction: instruction, time: request.compositionTime.seconds)
          lock.lock(); let cancelledAfter = token != generation; lock.unlock()
          if cancelledAfter { request.finishCancelledRequest() } else { request.finish(withComposedVideoFrame: output) }
        } catch { request.finish(with: error) }
      }
    }
  }
}
