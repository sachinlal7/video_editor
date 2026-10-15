# iOS renderer

Renderer v1 lives in the parent module's `GpuEffects.swift`, `TimelineComposition.swift` and generated `EffectCatalog.g.swift`. The AVFoundation custom compositor owns Metal resources; preview and proof export share the render instructions.
