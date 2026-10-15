import XCTest
@testable import vn_editor

@MainActor
final class RunnerTests: XCTestCase {
  func testGPUCatalogAndValidation() throws {
    XCTAssertEqual(effectSpecs.count, 13)
    for spec in effectSpecs {
      try validateEffects([NativeEffectConfiguration(effectId: spec.id, parameters: [:], intensity: 1, instanceId: "test")])
      for parameter in spec.parameters {
        for value in [parameter.min, parameter.max, parameter.value] {
          try validateEffects([NativeEffectConfiguration(effectId: spec.id, parameters: [parameter.name: value], intensity: 1, instanceId: "test")])
        }
        for value in [parameter.min - 1, parameter.max + 1, Double.nan, Double.infinity] {
          XCTAssertThrowsError(try validateEffects([NativeEffectConfiguration(effectId: spec.id, parameters: [parameter.name: value], intensity: 1, instanceId: "test")]))
        }
      }
    }
    XCTAssertThrowsError(try validateEffects([NativeEffectConfiguration(effectId: "lut", parameters: ["preset": 0.5], intensity: 1, instanceId: "test")]))
    XCTAssertThrowsError(try validateEffects([NativeEffectConfiguration(effectId: "missing", parameters: [:], intensity: 1, instanceId: "test")]))
  }
  func testRejectsPreviewBeforeInitialization() {
    VnEditorPlugin().loadMediaStrip(path: "/unused", startUs: 0, endUs: 1000, thumbnailCount: 1, requestId: 1) { result in
      guard case .failure(let error) = result else { XCTFail("Expected rejection"); return }
      XCTAssertEqual((error as? PigeonError)?.code, "not-initialized")
    }
  }

  func testRejectsMalformedComposition() async throws {
    let plugin = VnEditorPlugin()
    try plugin.initialize(configuration: NativeProjectConfiguration(projectId: "test", width: 640, height: 360, frameRate: 30, sessionId: "tests"))
    defer { try? plugin.disposeEditor() }
    for plan in [[], [NativeTimelineSegment(path: "/unused", sourceInUs: 0, sourceOutUs: 1000, startUs: -1, durationUs: 1000, speed: 1, volume: 1, effects: [])]] {
      let done = expectation(description: "invalid plan")
      plugin.openComposition(segments: plan, requestId: 1) { result in
        guard case .failure(let error) = result else { XCTFail("Expected rejection"); done.fulfill(); return }
        XCTAssertEqual((error as? PigeonError)?.code, "invalid-composition")
        done.fulfill()
      }
      await fulfillment(of: [done], timeout: 5)
    }
  }
  func testLifecycleAndUnavailablePlayback() throws {
    let plugin = VnEditorPlugin()
    let config = NativeProjectConfiguration(projectId: "test", width: 1080, height: 1920, frameRate: 30, sessionId: "test-session")
    XCTAssertThrowsError(try plugin.play())
    try plugin.initialize(configuration: config)
    defer { try? plugin.disposeEditor() }
    XCTAssertThrowsError(try plugin.play()) { error in
      XCTAssertEqual((error as? PigeonError)?.code, "no-media")
    }
    XCTAssertThrowsError(try plugin.initialize(configuration: config))
    try plugin.disposeEditor()
    try plugin.disposeEditor()
    try plugin.initialize(configuration: config)
  }

  func testRejectsInvalidFrameRate() {
    for rate in [0.0, -1.0, Double.nan, Double.infinity] {
      XCTAssertThrowsError(try VnEditorPlugin().initialize(configuration:
        NativeProjectConfiguration(projectId: "test", width: 1080, height: 1920, frameRate: rate, sessionId: "test-session")))
    }
  }

  func testRejectsSeekAndPauseWithoutMedia() throws {
    let plugin = VnEditorPlugin()
    try plugin.initialize(configuration: NativeProjectConfiguration(projectId: "test", width: 640, height: 360, frameRate: 30, sessionId: "tests"))
    XCTAssertThrowsError(try plugin.pause()) { error in
      XCTAssertEqual((error as? PigeonError)?.code, "no-media")
    }
    XCTAssertThrowsError(try plugin.seekTo(positionMilliseconds: -1)) { error in
      XCTAssertEqual((error as? PigeonError)?.code, "invalid-position")
    }
    XCTAssertThrowsError(try plugin.seekTo(positionMilliseconds: 0))
    try plugin.disposeEditor()
  }
}
