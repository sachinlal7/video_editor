package com.sachinlal.vn_editor

import android.content.Context
import android.graphics.Bitmap
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.io.File
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.max

internal fun localMediaFile(path: String): File {
    val uri = Uri.parse(path)
    val file = when {
        uri.scheme == "file" -> File(uri.path ?: "")
        uri.scheme == null && File(path).isAbsolute -> File(path)
        else -> throw FlutterError("invalid-path", "Use an absolute local path or file URI.")
    }
    if (!file.isFile || !file.canRead()) throw FlutterError("media-not-found", "Media is missing or unreadable.")
    return file
}

/** Small session-scoped LRU; only paths and 128 peak values cross the channel. */
internal class MediaStrips(context: Context) {
    private val directory = File(context.cacheDir, "vn-strips-${java.util.UUID.randomUUID()}").apply { mkdirs() }
    private val executor = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())
    private val jobs = ConcurrentHashMap<Long, AtomicBoolean>()
    private val cache = LinkedHashMap<String, NativeMediaStrip>(16, 0.75f, true)
    @Volatile private var closed = false

    fun cancel(id: Long) { jobs[id]?.set(true) }
    fun close() {
        closed = true
        jobs.values.forEach { it.set(true) }
        // Let queued jobs finish their cancellation callbacks; do not orphan futures.
        executor.shutdown()
        synchronized(cache) { cache.clear() }
        if (jobs.isEmpty()) directory.deleteRecursively()
    }

    fun load(path: String, start: Long, end: Long, count: Long, id: Long, done: (Result<NativeMediaStrip>) -> Unit) {
        if (closed || start < 0 || end <= start || end > 86_400_000_000L || count !in 0..8 || jobs.size >= 34) {
            done(Result.failure(FlutterError("invalid-preview", "Invalid or unavailable preview request."))); return
        }
        val cancelled = AtomicBoolean()
        if (jobs.putIfAbsent(id, cancelled) != null) { done(Result.failure(FlutterError("duplicate-request", "Preview request ID is active."))); return }
        executor.execute {
            val outputs = mutableListOf<File>()
            val deadline = System.nanoTime() + 60_000_000_000L
            fun check() {
                if (closed || cancelled.get()) throw FlutterError("operation-cancelled", "Preview cancelled.")
                if (System.nanoTime() > deadline) throw FlutterError("preview-timeout", "Preview decoding exceeded 60 seconds.")
            }
            val result = runCatching {
                check()
                val file = localMediaFile(path)
                val key = "${file.canonicalPath}:${file.length()}:${file.lastModified()}:$start:$end:$count"
                synchronized(cache) { cache[key] }?.let { return@runCatching it }
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(file.path)
                    val duration = (retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0) * 1000
                    if (duration <= 0 || end > duration + 1000) throw FlutterError("invalid-preview", "Preview range exceeds the source.")
                    for (index in 0 until count.toInt()) {
                        check()
                        val time = start + (end - start - 1) * index / max(1, count.toInt() - 1)
                        val bitmap = if (Build.VERSION.SDK_INT >= 27) retriever.getScaledFrameAtTime(time, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 160, 90)
                            else retriever.getFrameAtTime(time, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                        if (bitmap == null) throw FlutterError("preview-failed", "No video thumbnail could be decoded.")
                        try {
                            val ratio = minOf(160f / bitmap.width, 90f / bitmap.height, 1f)
                            val small = Bitmap.createScaledBitmap(bitmap, max(1, (bitmap.width * ratio).toInt()), max(1, (bitmap.height * ratio).toInt()), true)
                            try {
                                val output = File(directory, "${java.util.UUID.randomUUID()}.jpg")
                                outputs.add(output)
                                output.outputStream().use { if (!small.compress(Bitmap.CompressFormat.JPEG, 75, it)) throw IllegalStateException("JPEG encoding failed") }
                            } finally { if (small !== bitmap) small.recycle() }
                        } finally { bitmap.recycle() }
                    }
                } finally { retriever.release() }
                val peaks = peaks(file, start, end, ::check)
                check()
                val strip = NativeMediaStrip(outputs.map { it.path }, peaks)
                synchronized(cache) {
                    // Concurrent duplicates reuse the first result and remove their files.
                    cache[key]?.let { existing -> outputs.forEach { it.delete() }; return@synchronized existing }
                    cache[key] = strip
                    while (cache.size > 16) {
                        val entry = cache.entries.iterator().next()
                        entry.value.thumbnails.forEach { File(it).delete() }
                        cache.remove(entry.key)
                    }
                    strip
                }
            }
            if (result.isFailure) outputs.forEach { it.delete() }
            jobs.remove(id)
            if (closed && jobs.isEmpty()) directory.deleteRecursively()
            main.post { done(if (closed || cancelled.get()) Result.failure(FlutterError("operation-cancelled", "Preview cancelled.")) else result.fold({ Result.success(it) }, { Result.failure(if (it is FlutterError) it else FlutterError("preview-failed", "Media preview could not be decoded.")) })) }
        }
    }

    private fun peaks(file: File, start: Long, end: Long, check: () -> Unit): List<Double> {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(file.path)
            val track = (0 until extractor.trackCount).firstOrNull { extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true } ?: return emptyList()
            extractor.selectTrack(track)
            extractor.seekTo(start, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            val format = extractor.getTrackFormat(track)
            val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec = decoder
            decoder.configure(format, null, null, 0)
            decoder.start()
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var floating = false
            var inputEnded = false
            val peaks = DoubleArray(128)
            val info = MediaCodec.BufferInfo()
            while (true) {
                check()
                if (!inputEnded) {
                    val input = decoder.dequeueInputBuffer(1000)
                    if (input >= 0) {
                        val buffer = decoder.getInputBuffer(input)!!
                        val time = extractor.sampleTime
                        val size = if (time < 0 || time >= end) -1 else extractor.readSampleData(buffer, 0)
                        if (size < 0) { decoder.queueInputBuffer(input, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); inputEnded = true }
                        else { decoder.queueInputBuffer(input, 0, size, time, 0); extractor.advance() }
                    }
                }
                val output = decoder.dequeueOutputBuffer(info, 1000)
                if (output == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val actual = decoder.outputFormat
                    channels = actual.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    sampleRate = actual.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    if (channels <= 0 || sampleRate <= 0) throw FlutterError("unsupported-audio", "Invalid decoded audio format.")
                    val encoding = if (actual.containsKey(MediaFormat.KEY_PCM_ENCODING)) actual.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT
                    if (encoding != AudioFormat.ENCODING_PCM_16BIT && encoding != AudioFormat.ENCODING_PCM_FLOAT) throw FlutterError("unsupported-audio", "Unsupported decoded PCM format.")
                    floating = encoding == AudioFormat.ENCODING_PCM_FLOAT
                } else if (output >= 0) {
                    try {
                        val buffer = decoder.getOutputBuffer(output)!!.order(ByteOrder.LITTLE_ENDIAN)
                        buffer.position(info.offset); buffer.limit(info.offset + info.size)
                        var sample = 0L
                        val bytes = if (floating) 4 else 2
                        while (buffer.remaining() >= bytes) {
                            val value = if (floating) abs(buffer.float.toDouble()) else abs(buffer.short.toDouble() / 32768.0)
                            val time = info.presentationTimeUs + (sample / channels) * 1_000_000 / sampleRate
                            if (time >= start && time < end && value.isFinite()) {
                                val bin = ((time - start).toDouble() / (end - start) * peaks.size).toInt().coerceIn(0, peaks.lastIndex)
                                peaks[bin] = max(peaks[bin], value.coerceAtMost(1.0))
                            }
                            sample++
                        }
                    } finally { decoder.releaseOutputBuffer(output, false) }
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
            return peaks.toList()
        } finally { codec?.release(); extractor.release() }
    }
}
