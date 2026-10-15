package com.sachinlal.vn_editor

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

internal class VnEditorPluginTest {
    @Test fun gpuCatalogAndValidation() {
        assertEquals(13, effectSpecs.size)
        for (spec in effectSpecs) {
            validateEffects(listOf(NativeEffectConfiguration(spec.id, emptyMap(), 1.0, "test")))
            for (parameter in spec.parameters) {
                for (value in listOf(parameter.min, parameter.max, parameter.value)) validateEffects(listOf(NativeEffectConfiguration(spec.id, mapOf(parameter.name to value), 1.0, "test")))
                for (value in listOf(parameter.min - 1, parameter.max + 1, Double.NaN, Double.POSITIVE_INFINITY)) assertFailsWith<FlutterError> { validateEffects(listOf(NativeEffectConfiguration(spec.id, mapOf(parameter.name to value), 1.0, "test"))) }
            }
        }
        assertFailsWith<FlutterError> { validateEffects(List(9) { NativeEffectConfiguration("grayscale", emptyMap(), 1.0, "$it") }) }
        assertFailsWith<FlutterError> { validateEffects(listOf(NativeEffectConfiguration("lut", mapOf("preset" to 0.5), 1.0, "test"))) }
        assertFailsWith<FlutterError> { validateEffects(listOf(NativeEffectConfiguration("missing", emptyMap(), 1.0, "test"))) }
    }
    @Test fun rejectsEmptyAndMalformedCompositions() {
        val plugin = VnEditorPlugin()
        plugin.initialize(configuration())
        for (plan in listOf(emptyList(), listOf(NativeTimelineSegment("/unused", 0, 1000, 0, 1000, Double.NaN, 1.0, emptyList())), listOf(NativeTimelineSegment("/unused", 0, 1000, -1, 1000, 1.0, 1.0, emptyList())))) {
            var code: String? = null
            plugin.openComposition(plan, 1) { code = (it.exceptionOrNull() as? FlutterError)?.code }
            assertEquals("invalid-composition", code)
        }
        plugin.disposeEditor()
    }

    @Test fun rejectsPreviewBeforeInitialization() {
        var code: String? = null
        VnEditorPlugin().loadMediaStrip("/unused", 0, 1000, 1, 1) { code = (it.exceptionOrNull() as? FlutterError)?.code }
        assertEquals("not-initialized", code)
    }
    private fun configuration(rate: Double = 30.0) =
        NativeProjectConfiguration("test", 1080, 1920, rate, "test-session")

    @Test fun lifecycleAndUnavailablePlayback() {
        val plugin = VnEditorPlugin()
        assertEquals("not-initialized", assertFailsWith<FlutterError> { plugin.play() }.code)
        plugin.initialize(configuration())
        assertEquals("no-media", assertFailsWith<FlutterError> { plugin.play() }.code)
        assertEquals("editor-in-use", assertFailsWith<FlutterError> { plugin.initialize(configuration()) }.code)
        plugin.disposeEditor()
        plugin.disposeEditor()
        plugin.initialize(configuration())
    }

    @Test fun rejectsInvalidFrameRates() {
        for (rate in listOf(0.0, -1.0, Double.NaN, Double.POSITIVE_INFINITY)) {
            assertEquals("invalid-project", assertFailsWith<FlutterError> {
                VnEditorPlugin().initialize(configuration(rate))
            }.code)
        }
    }

    @Test fun rejectsCommandsWithoutMediaAndNegativeSeek() {
        val plugin = VnEditorPlugin()
        plugin.initialize(configuration())
        assertEquals("no-media", assertFailsWith<FlutterError> { plugin.pause() }.code)
        assertEquals("invalid-position", assertFailsWith<FlutterError> { plugin.seekTo(-1) }.code)
        assertEquals("no-media", assertFailsWith<FlutterError> { plugin.seekTo(0) }.code)
        plugin.disposeEditor()
        assertEquals("not-initialized", assertFailsWith<FlutterError> { plugin.seekTo(0) }.code)
    }
}
