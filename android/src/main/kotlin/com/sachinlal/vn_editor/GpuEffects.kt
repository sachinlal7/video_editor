package com.sachinlal.vn_editor

import android.content.Context
import android.opengl.GLES20
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram
import java.nio.ByteBuffer

internal data class EffectParameter(val name: String, val min: Double, val max: Double, val value: Double)
internal data class EffectSpec(val id: String, val parameters: List<EffectParameter>)

internal fun validateEffects(effects: List<NativeEffectConfiguration>) {
    if (effects.size > 8) throw FlutterError("invalid-effect", "At most eight GPU stages are supported.")
    for (effect in effects) {
        val spec = effectSpecs.firstOrNull { it.id == effect.effectId }
            ?: throw FlutterError("unsupported-effect", "Unknown GPU effect: ${effect.effectId}")
        if (!effect.intensity.isFinite() || effect.intensity !in 0.0..1.0) throw FlutterError("invalid-effect", "Invalid effect intensity.")
        for ((key, value) in effect.parameters) {
            val parameter = spec.parameters.firstOrNull { it.name == key }
            if (parameter == null || !value.isFinite() || value < parameter.min || value > parameter.max || (effect.effectId == "lut" && value != kotlin.math.floor(value))) throw FlutterError("invalid-effect", "Invalid ${effect.effectId}.$key.")
        }
    }
}

@UnstableApi
internal class GpuEffect(private val configuration: NativeEffectConfiguration) : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram {
        if (useHdr) throw VideoFrameProcessingException("HDR effects are not supported in renderer v1.")
        return Program(context, configuration)
    }

    private class Program(context: Context, val config: NativeEffectConfiguration) : BaseGlShaderProgram(false, 1) {
        private val program = GlProgram(VERTEX, FRAGMENT)
        private var lut = 0
        private var width = 1
        private var height = 1
        init {
            try {
                validateEffects(listOf(config))
                program.setBufferAttribute("aPosition", GlUtil.getNormalizedCoordinateBounds(), 4)
                lut = GlUtil.createTexture(289, 68, false)
                GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, lut)
                val bytes = context.assets.open("vn_editor_luts.rgba").use { it.readBytes() }
                GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, 289, 68, 0, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, ByteBuffer.allocateDirect(bytes.size).put(bytes).apply { position(0) })
                GlUtil.checkGlError()
            } catch (error: Exception) {
                program.delete()
                if (lut != 0) GlUtil.deleteTexture(lut)
                throw VideoFrameProcessingException(error)
            }
        }
        override fun configure(inputWidth: Int, inputHeight: Int): Size {
            width = inputWidth; height = inputHeight
            return Size(width, height)
        }
        override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
            try {
                program.use()
                val index = effectSpecs.indexOfFirst { it.id == config.effectId }
                val values = FloatArray(8)
                effectSpecs[index].parameters.forEachIndexed { i, p -> values[i] = (config.parameters[p.name] ?: p.value).toFloat() }
                program.setSamplerTexIdUniform("uTex", inputTexId, 0)
                program.setSamplerTexIdUniform("uLut", lut, 1)
                program.setIntUniform("kind", index + 1)
                program.setFloatUniform("intensity", config.intensity.toFloat())
                program.setFloatUniform("time", (presentationTimeUs / 1_000_000.0).toFloat())
                program.setFloatsUniform("pixel", floatArrayOf(1f / width, 1f / height))
                program.bindAttributesAndUniforms()
                // GlProgram treats float uniforms as scalars, including GLSL arrays.
                GLES20.glUniform1fv(program.getUniformLocation("p[0]"), 6, values, 0)
                GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
                GlUtil.checkGlError()
            } catch (error: Exception) { android.util.Log.e("VnGpu", "GPU stage failed", error); throw VideoFrameProcessingException(error, presentationTimeUs) }
        }
        override fun release() {
            try { super.release() } finally { program.delete(); GlUtil.deleteTexture(lut) }
        }
    }
    companion object {
        private val VERTEX = """
            attribute vec4 aPosition;
            varying vec2 uv;
            void main() { gl_Position = aPosition; uv = vec2(aPosition.x * 0.5 + 0.5, 0.5 - aPosition.y * 0.5); }
        """
        private val FRAGMENT = """
            precision highp float;
            uniform sampler2D uTex;
            uniform sampler2D uLut;
            uniform int kind;
            uniform float p[8];
            uniform float intensity;
            uniform float time;
            uniform vec2 pixel;
            varying vec2 uv;
            vec4 sampleInput(vec2 v) { return texture2D(uTex, clamp(vec2(v.x, 1.0-v.y), vec2(0.0), vec2(1.0))); }
            #define SAMPLE(v) sampleInput(v)
            vec3 cube(vec3 v) { return texture2D(uLut, vec2((v.b * 17.0 + v.r + 0.5) / 289.0, (p[0] * 17.0 + v.g + 0.5) / 68.0)).rgb; }
            vec3 lookup(vec3 c) {
              vec3 v = c * 16.0; vec3 lo = floor(v); vec3 hi = min(lo + 1.0, vec3(16.0)); vec3 f = fract(v);
              return mix(mix(mix(cube(lo), cube(vec3(hi.r,lo.g,lo.b)), f.r), mix(cube(vec3(lo.r,hi.g,lo.b)), cube(vec3(hi.r,hi.g,lo.b)), f.r), f.g), mix(mix(cube(vec3(lo.r,lo.g,hi.b)), cube(vec3(hi.r,lo.g,hi.b)), f.r), mix(cube(vec3(lo.r,hi.g,hi.b)), cube(hi), f.r), f.g), f.b);
            }
            #define LUT(v) lookup(v)
            vec4 process() {
            $effectBody
            }
            void main() { gl_FragColor = process(); }
        """
    }
}
