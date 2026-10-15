package com.sachinlal.vn_editor

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import java.io.File
import java.io.FileOutputStream
import android.system.Os
import android.system.OsConstants
import java.util.concurrent.Executors

/** Foreground, bounded verification export. The full job engine is Phase 8. */
@UnstableApi
internal class ProofExporter(private val context: Context) {
    var outputPath: String? = null
        private set
    private var transformer: Transformer? = null
    private var temporary: File? = null
    private var completion: ((Result<String>) -> Unit)? = null
    private val handler = Handler(Looper.getMainLooper())
    private val deadline = Runnable { finish(Result.failure(FlutterError("export-timeout", "Verification export exceeded two minutes."))) }
    fun start(plan: Composition, config: NativeExportConfiguration, durationMs: Long, callback: (Result<String>) -> Unit) {
        val output = File(config.outputPath)
        if (config.frameRate != 30L || config.videoBitrate != 12000000L) throw FlutterError("unsupported-export", "Custom frame rate and bitrate controls arrive with the full exporter. Verification uses native encoder quality at 30 fps.")
        if (!output.isAbsolute || output.exists() || output.parentFile?.isDirectory != true || config.container != "mp4" || config.videoCodec != "h264" || config.width !in 2..1920 || config.height !in 2..1920 || config.width * config.height > 1920 * 1080 || config.width % 2 != 0L || config.height % 2 != 0L || durationMs > 60_000) throw FlutterError("unsupported-export", "Verification export requires a new local MP4 path, H.264, even dimensions up to 1080p and at most 60 seconds.")
        outputPath = output.path
        completion = callback
        try {
            val temp = File.createTempFile(".vn-export-", ".mp4", output.parentFile)
            temporary = temp
            transformer = Transformer.Builder(context).setVideoMimeType(MimeTypes.VIDEO_H264).setAudioMimeType(MimeTypes.AUDIO_AAC)
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        if (completion == null) return
                        val worker = Executors.newSingleThreadExecutor()
                        worker.execute {
                            var owned = false
                            val result = runCatching {
                                // Android emulated storage forbids hard links. Exclusive creation
                                // prevents overwriting even if another writer races this export.
                                val descriptor = Os.open(output.path, OsConstants.O_WRONLY or OsConstants.O_CREAT or OsConstants.O_EXCL, 384)
                                owned = true
                                FileOutputStream(descriptor).use { target -> temp.inputStream().use { it.copyTo(target) } }
                                output.path
                            }
                            handler.post {
                                if (owned && (completion == null || result.isFailure)) output.delete()
                                finish(result)
                            }
                            worker.shutdown()
                        }
                    }
                    override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                        android.util.Log.e("VnGpu", "Verification export failed", exportException)
                        finish(Result.failure(FlutterError("export-failed", "The device could not encode the verification video: ${exportException.errorCodeName}")))
                    }
                }).build().also { it.start(plan, temp.path) }
            handler.postDelayed(deadline, 120_000)
        } catch (error: Throwable) { finish(Result.failure(error)) }
    }
    fun cancel() = finish(Result.failure(FlutterError("operation-cancelled", "Verification export cancelled.")))
    private fun finish(result: Result<String>) {
        val callback = completion ?: return
        completion = null
        handler.removeCallbacks(deadline)
        transformer?.cancel(); transformer = null
        temporary?.delete(); temporary = null
        callback(result)
    }
}
