package com.sachinlal.vn_editor

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.audio.ChannelMixingAudioProcessor
import androidx.media3.common.audio.ChannelMixingMatrix
import androidx.media3.common.audio.SpeedProvider
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects

/** Immutable native render plan shared by CompositionPlayer and Transformer. */
@UnstableApi
internal fun gpuComposition(segments: List<NativeTimelineSegment>, width: Int, height: Int, includeAudio: Boolean = true): Composition {
    val tracks = if (includeAudio) setOf(C.TRACK_TYPE_AUDIO, C.TRACK_TYPE_VIDEO) else setOf(C.TRACK_TYPE_VIDEO)
    val sequence = EditedMediaItemSequence.Builder(tracks)
    for (clip in segments) {
        if (clip.path.isEmpty()) { sequence.addGap(clip.durationUs); continue }
        validateEffects(clip.effects)
        val audio = ChannelMixingAudioProcessor()
        for (channels in 1..8) audio.putChannelMixingMatrix(ChannelMixingMatrix(channels, channels, FloatArray(channels * channels) { if (it / channels == it % channels) clip.volume.toFloat() else 0f }))
        val item = MediaItem.Builder().setUri(Uri.fromFile(localMediaFile(clip.path)))
            .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder().setStartPositionUs(clip.sourceInUs).setEndPositionUs(clip.sourceOutUs).build()).build()
        val effects = listOf(Presentation.createForWidthAndHeight(width, height, Presentation.LAYOUT_SCALE_TO_FIT)) + clip.effects.filter { it.intensity > 0 }.map { GpuEffect(it) }
        sequence.addItem(EditedMediaItem.Builder(item).setDurationUs(clip.sourceOutUs).setFrameRate(30)
            .setSpeed(object : SpeedProvider {
                override fun getSpeed(timeUs: Long): Float = clip.speed.toFloat()
                override fun getNextSpeedChangeTimeUs(timeUs: Long): Long = C.TIME_UNSET
            }).setEffects(Effects(listOf(audio), effects)).build())
    }
    // Gap frames start at Media3's 16×16 default; normalize the final canvas too.
    return Composition.Builder(sequence.build()).setEffects(Effects(emptyList(), listOf(Presentation.createForWidthAndHeight(width, height, Presentation.LAYOUT_SCALE_TO_FIT)))).build()
}
