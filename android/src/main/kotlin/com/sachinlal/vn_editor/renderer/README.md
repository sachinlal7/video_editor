# Android renderer

Renderer v1 lives in the parent package's `GpuEffects.kt`, `GpuComposition.kt` and generated `EffectCatalog.g.kt`. Media3 owns frame scheduling and OpenGL resources; preview and proof export share the composition.
