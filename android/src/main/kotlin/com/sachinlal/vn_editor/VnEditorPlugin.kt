package com.sachinlal.vn_editor

import android.app.Activity
import android.app.Application
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.Bundle
import android.view.SurfaceView
import android.view.PixelCopy
import android.graphics.Bitmap
import android.view.Gravity
import android.view.View
import android.graphics.Color
import android.widget.FrameLayout
import android.media.MediaMetadataRetriever
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.SeekParameters
import androidx.media3.transformer.CompositionPlayer
import androidx.media3.transformer.Composition
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import java.lang.ref.WeakReference

/** One single-source player per engine; decoded frames never cross Pigeon. */
@UnstableApi
class VnEditorPlugin : FlutterPlugin, VnEditorHostApi, ActivityAware {
    private var initialized = false
    private var context: Context? = null
    private var events: VnEditorFlutterApi? = null
    private var handler: Handler? = null
    private var player: Player? = null
    private var renderPlan: Composition? = null
    private var sourcePath: String? = null
    private var mediaMetadata: NativeMediaMetadata? = null
    private var sourceEffects = listOf<NativeEffectConfiguration>()
    private var effectCompletion: ((Result<Unit>) -> Unit)? = null
    private val effectDeadline = Runnable { fail("effect-timeout", "The effect preview did not become ready.") }
    private var exporter: ProofExporter? = null
    private var preview: WeakReference<Preview>? = null
    private var sessionId = ""
    private var requestId = 0L
    private var loaded = false
    private var pending: ((Result<NativeMediaMetadata>) -> Unit)? = null
    private var timeout: Runnable? = null
    private var activity: Activity? = null
    private var strips: MediaStrips? = null
    private var composition = emptyList<NativeTimelineSegment>()
    private var projectWidth = 0L
    private var projectHeight = 0L
    private var projectRate = 30.0
    private var preparation = java.util.concurrent.Executors.newSingleThreadExecutor()
    private var videoAspect = 1.0
    @Volatile private var preparationGeneration = 0L
    private var capturing = false
    private val activityCallbacks = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityPaused(activity: Activity) {
            if (activity === this@VnEditorPlugin.activity) { player?.pause(); emit() }
        }
        override fun onActivityCreated(activity: Activity, state: Bundle?) {}
        override fun onActivityStarted(activity: Activity) {}
        override fun onActivityResumed(activity: Activity) {}
        override fun onActivityStopped(activity: Activity) {}
        override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) {}
        override fun onActivityDestroyed(activity: Activity) {}
    }
    private val tick = object : Runnable {
        override fun run() {
            if (player == null) return
            emit()
            if (player?.isPlaying == true || player?.playbackState == Player.STATE_BUFFERING) handler?.postDelayed(this, 200)
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        handler = Handler(Looper.getMainLooper())
        events = VnEditorFlutterApi(binding.binaryMessenger)
        VnEditorHostApi.setUp(binding.binaryMessenger, this)
        binding.platformViewRegistry.registerViewFactory("vn_editor/preview", object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
            override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
                val id = (args as? Map<*, *>)?.get("sessionId") as? String ?: ""
                return Preview(context, id).also { view ->
                    if (initialized && id == sessionId) {
                        preview?.get()?.let { player?.clearVideoSurfaceView(it.texture) }
                        preview = WeakReference(view)
                        player?.setVideoSurfaceView(view.texture)
                        player?.let { applySegment(it) }
                    }
                }
            }
        })
    }

    private inner class Preview(context: Context, val session: String) : PlatformView {
        val texture = SurfaceView(context)
        val container = FrameLayout(context).apply {
            setBackgroundColor(Color.BLACK)
            addView(texture, FrameLayout.LayoutParams(-1, -1))
        }
        init { texture.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> fitVideo() } }
        override fun getView(): View = container
        override fun dispose() {
            if (preview?.get() === this) {
                player?.clearVideoSurfaceView(texture)
                preview = null
            }
        }
    }

    override fun initialize(configuration: NativeProjectConfiguration) {
        if (initialized) throw FlutterError("editor-in-use", "An editor is already active.")
        if (configuration.projectId.isBlank() || configuration.width <= 0 || configuration.height <= 0 || !configuration.frameRate.isFinite() || configuration.frameRate <= 0) {
            throw FlutterError("invalid-project", "Project ID, dimensions and frame rate must be valid.")
        }
        sessionId = configuration.sessionId
        projectWidth = configuration.width
        projectHeight = configuration.height
        projectRate = configuration.frameRate
        context?.let { strips = MediaStrips(it) }
        initialized = true
    }

    override fun disposeEditor() {
        exporter?.cancel(); exporter = null
        releaseMedia()
        strips?.close(); strips = null
        preview = null
        initialized = false
        sessionId = ""
    }

    private fun releaseMedia() {
        handler?.removeCallbacks(effectDeadline)
        val effectCallback = effectCompletion
        effectCompletion = null
        preparationGeneration++
        handler?.removeCallbacks(tick)
        timeout?.let { handler?.removeCallbacks(it) }
        timeout = null
        val completion = pending
        pending = null
        loaded = false
        composition = emptyList()
        renderPlan = null
        sourcePath = null
        sourceEffects = emptyList()
        mediaMetadata = null
        val old = player
        player = null
        old?.release()
        effectCallback?.invoke(Result.failure(FlutterError("operation-cancelled", "Effect update cancelled.")))
        completion?.invoke(Result.failure(FlutterError("operation-cancelled", "Media loading was replaced or disposed.")))
    }

    override fun openMedia(path: String, requestId: Long, callback: (Result<NativeMediaMetadata>) -> Unit) {
        open(path, requestId, emptyList(), callback)
    }

    override fun openComposition(segments: List<NativeTimelineSegment>, requestId: Long, callback: (Result<NativeMediaMetadata>) -> Unit) {
        val plan = mutableListOf<NativeTimelineSegment>()
        try {
            requireInitialized()
            if (segments.isEmpty() || segments.size > 256) throw FlutterError("invalid-composition", "Expected 1–256 video clips.")
            var end = 0L
            for (clip in segments) {
                validateEffects(clip.effects)
                if (clip.startUs < end || clip.durationUs < 1000 || clip.sourceInUs < 0 || clip.sourceOutUs <= clip.sourceInUs || clip.startUs > 86_400_000_000L - clip.durationUs || !clip.speed.isFinite() || clip.speed !in 0.25..4.0 || !clip.volume.isFinite() || clip.volume !in 0.0..1.0 || kotlin.math.abs((clip.sourceOutUs - clip.sourceInUs) / clip.speed - clip.durationUs) > 2) throw FlutterError("invalid-composition", "Invalid timeline interval, speed or volume.")
                localMediaFile(clip.path)
                if (clip.startUs > end) plan.add(NativeTimelineSegment("", 0, clip.startUs - end, end, clip.startUs - end, 1.0, 0.0, emptyList()))
                plan.add(clip)
                end = clip.startUs + clip.durationUs
            }
        } catch (error: Throwable) { callback(Result.failure(error)); return }
        open("vn-editor:timeline", requestId, plan, callback)
    }

    override fun loadMediaStrip(path: String, startUs: Long, endUs: Long, thumbnailCount: Long, requestId: Long, callback: (Result<NativeMediaStrip>) -> Unit) {
        try { requireInitialized(); strips?.load(path, startUs, endUs, thumbnailCount, requestId, callback) ?: throw FlutterError("not-attached", "No preview decoder.") }
        catch (error: Throwable) { callback(Result.failure(error)) }
    }
    override fun cancelMediaStrip(requestId: Long) { strips?.cancel(requestId) }

    private fun open(path: String, requestId: Long, plan: List<NativeTimelineSegment>, callback: (Result<NativeMediaMetadata>) -> Unit) {
        try { requireInitialized() } catch (error: Throwable) { callback(Result.failure(error)); return }
        releaseMedia()
        composition = plan
        if (plan.isNotEmpty()) videoAspect = projectWidth.toDouble() / projectHeight
        this.requestId = requestId
        pending = callback
        emit(NativePlaybackStatus.LOADING)
        try {
            val file = if (plan.isEmpty()) localMediaFile(path) else null
            val nativeContext = context ?: throw FlutterError("not-attached", "The engine is not attached.")
            val current: Player = if (plan.isEmpty()) ExoPlayer.Builder(nativeContext).build().also {
                it.setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true)
                it.setHandleAudioBecomingNoisy(true)
                it.setSeekParameters(SeekParameters.EXACT)
                it.setVideoEffects(emptyList())
            } else CompositionPlayer.Builder(nativeContext).setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true).build()
            player = current
            sourcePath = if (plan.isEmpty()) path else null
            preview?.get()?.takeIf { it.session == sessionId }?.let { current.setVideoSurfaceView(it.texture) }
            current.addListener(object : Player.Listener {
                override fun onVideoSizeChanged(videoSize: VideoSize) {
                    if (videoSize.width > 0 && videoSize.height > 0) {
                        videoAspect = if (plan.isNotEmpty()) projectWidth.toDouble() / projectHeight
                            else videoSize.width * videoSize.pixelWidthHeightRatio.toDouble() / videoSize.height
                        fitVideo()
                    }
                }
                override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) { applySegment(current) }
                override fun onEvents(player: Player, events: Player.Events) {
                    if (this@VnEditorPlugin.player !== current) return
                    if (current.playbackState == Player.STATE_READY) {
                        val effectCallback = effectCompletion
                        effectCompletion = null
                        handler?.removeCallbacks(effectDeadline)
                        effectCallback?.invoke(Result.success(Unit))
                    }
                    if (current.playbackState == Player.STATE_READY && pending != null) {
                        val tracks = current.currentTracks.groups
                        val format = tracks.firstOrNull { it.type == C.TRACK_TYPE_VIDEO }?.getTrackFormat(0)
                        if (plan.isEmpty() && (format == null || format.width <= 0 || format.height <= 0 || current.duration <= 0)) {
                            fail("unsupported-media", "A finite, decodable video track is required.")
                            return
                        }
                        val rotated = format?.rotationDegrees == 90 || format?.rotationDegrees == 270
                        val width = if (rotated) format?.height else format?.width
                        val height = if (rotated) format?.width else format?.height
                        loaded = true
                        timeout?.let { handler?.removeCallbacks(it) }
                        timeout = null
                        val completion = pending
                        pending = null
                        emit(NativePlaybackStatus.READY)
                        val result = if (plan.isEmpty()) NativeMediaMetadata(path, current.duration, width!!.toLong(), height!!.toLong(), tracks.any { it.type == C.TRACK_TYPE_AUDIO }, format!!.frameRate.toDouble().takeIf { it > 0 && it.isFinite() }) else NativeMediaMetadata(path, (plan.last().startUs + plan.last().durationUs) / 1000, projectWidth, projectHeight, true, projectRate)
                        mediaMetadata = result
                        videoAspect = result.width.toDouble() / result.height
                        fitVideo()
                        completion?.invoke(Result.success(result))
                    }
                    emit()
                    handler?.removeCallbacks(tick)
                    if (current.isPlaying || current.playbackState == Player.STATE_BUFFERING) handler?.postDelayed(tick, 200)
                }
                override fun onPlayerError(error: PlaybackException) {
                    if (this@VnEditorPlugin.player === current) fail("playback-failed", "The video could not be decoded. Try another local video.")
                }
            })
            timeout = Runnable { if (player === current && pending != null) fail("media-timeout", "The video did not become ready within 30 seconds.") }.also { handler?.postDelayed(it, 30_000) }
            fun prepare() {
              if (plan.isEmpty()) current.setMediaItem(MediaItem.fromUri(Uri.fromFile(file!!)))
              else {
                val compiled = gpuComposition(plan, projectWidth.toInt(), projectHeight.toInt())
                renderPlan = compiled
                (current as CompositionPlayer).setComposition(compiled)
              }
              applySegment(current)
              current.prepare()
              handler?.post(tick)
            }
            if (plan.isEmpty()) prepare()
            else {
              val token = preparationGeneration
              val deadline = System.nanoTime() + 30_000_000_000L
              preparation.execute {
                val validation = runCatching {
                    for (clip in plan.filter { it.path.isNotEmpty() }) {
                        if (token != preparationGeneration || System.nanoTime() > deadline) throw FlutterError("operation-cancelled", "Timeline preparation cancelled or timed out.")
                        val retriever = MediaMetadataRetriever()
                        try {
                            retriever.setDataSource(localMediaFile(clip.path).path)
                            val duration = (retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0) * 1000
                            if (clip.sourceOutUs > duration || retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) != "yes") throw FlutterError("invalid-composition", "A clip exceeds its source or has no video track.")
                        } finally { retriever.release() }
                    }
                }
                handler?.post {
                    if (player === current && initialized) validation.fold({
                        try { prepare() } catch (_: Throwable) { fail("media-open-failed", "A timeline source became unavailable during preparation.") }
                    }, { fail("invalid-composition", "A timeline source is invalid or exceeds its duration.") })
                }
              }
            }
        } catch (error: Throwable) {
            val code = (error as? FlutterError)?.code ?: "media-open-failed"
            fail(code, (error as? FlutterError)?.message ?: "The video could not be opened.")
        }
    }

    private fun applySegment(current: Player) {
        if (player !== current) return
        fitVideo()
    }

    private fun fitVideo() {
        val texture = preview?.get()?.texture ?: return
        if (texture.width <= 0 || texture.height <= 0) return
        val container = preview?.get()?.container ?: return
        if (container.width <= 0 || container.height <= 0) return
        val aspect = container.width.toDouble() / container.height
        val width = if (videoAspect < aspect) (container.height * videoAspect).toInt() else container.width
        val height = if (videoAspect > aspect) (container.width / videoAspect).toInt() else container.height
        if (texture.layoutParams.width != width || texture.layoutParams.height != height) texture.layoutParams = FrameLayout.LayoutParams(width, height, Gravity.CENTER)
    }

    private fun timelinePosition(current: Player?, buffered: Boolean = false): Long {
        if (current == null) return 0
        val position = (if (buffered) current.bufferedPosition else current.currentPosition).coerceAtLeast(0)
        return position
    }

    private fun fail(code: String, message: String) {
        val completion = pending
        pending = null
        releaseMedia()
        emit(NativePlaybackStatus.FAILED, message)
        completion?.invoke(Result.failure(FlutterError(code, message)))
    }

    private fun emit(status: NativePlaybackStatus? = null, error: String? = null) {
        if (!initialized) return
        val current = player
        val actual = status ?: when {
            current == null -> NativePlaybackStatus.IDLE
            current.playbackState == Player.STATE_BUFFERING -> NativePlaybackStatus.LOADING
            current.playbackState == Player.STATE_ENDED -> NativePlaybackStatus.ENDED
            current.isPlaying -> NativePlaybackStatus.PLAYING
            loaded -> NativePlaybackStatus.PAUSED
            else -> NativePlaybackStatus.LOADING
        }
        events?.onPlaybackStateChanged(NativePlaybackEvent(actual, timelinePosition(current), timelinePosition(current, true), sessionId, requestId, error)) { /* No retry after Dart detaches. */ }
    }

    override fun play() {
        val current = requireMedia()
        if (current.playbackState == Player.STATE_ENDED) {
            if (current is CompositionPlayer) current.stop()
            current.seekTo(0)
            current.prepare()
            applySegment(current)
        }
        current.play()
    }
    override fun pause() { requireMedia().pause(); emit() }
    override fun seekTo(positionMilliseconds: Long) {
        requireInitialized()
        if (positionMilliseconds < 0) throw FlutterError("invalid-position", "Seek position must not be negative.")
        val current = requireMedia()
        val total = composition.lastOrNull()?.let { (it.startUs + it.durationUs) / 1000 } ?: current.duration
        if (positionMilliseconds > total) throw FlutterError("invalid-position", "Seek position exceeds the playback duration.")
        current.seekTo(positionMilliseconds)
        emit()
    }
    private fun requireMedia(): Player {
        requireInitialized()
        if (!loaded) throw FlutterError("no-media", "Open a video and wait until it is ready.")
        return player ?: throw FlutterError("no-media", "No video is open.")
    }
    private fun requireInitialized() {
        if (!initialized) throw FlutterError("not-initialized", "Initialize the editor before sending commands.")
    }
    override fun applyEffect(effect: NativeEffectConfiguration, callback: (Result<Unit>) -> Unit) {
      try {
        val current = requireMedia() as? ExoPlayer ?: throw FlutterError("timeline-edit-required", "Use project commands to edit timeline effects.")
        val next = if (sourceEffects.any { it.instanceId == effect.instanceId }) sourceEffects.map { if (it.instanceId == effect.instanceId) effect else it } else sourceEffects + effect
        validateEffects(next)
        setSourceEffects(current, next, callback)
      } catch (error: Throwable) { callback(Result.failure(error)) }
    }
    override fun removeEffect(effectId: String, callback: (Result<Unit>) -> Unit) {
      try {
        val current = requireMedia() as? ExoPlayer ?: throw FlutterError("timeline-edit-required", "Use project commands to edit timeline effects.")
        val next = sourceEffects.filter { it.instanceId != effectId }
        setSourceEffects(current, next, callback)
      } catch (error: Throwable) { callback(Result.failure(error)) }
    }
    private fun setSourceEffects(current: ExoPlayer, next: List<NativeEffectConfiguration>, callback: (Result<Unit>) -> Unit) {
        if (effectCompletion != null) throw FlutterError("effect-in-progress", "Wait for the current effect update.")
        val position = current.currentPosition
        // Reprepare invalidates the decoded paused frame and installs the new GPU chain.
        current.stop()
        current.setVideoEffects(next.map { GpuEffect(it) })
        sourceEffects = next
        current.seekTo(position)
        effectCompletion = callback
        handler?.postDelayed(effectDeadline, 30_000)
        current.prepare()
    }
    override fun supportedEffects(): List<String> { requireInitialized(); return effectSpecs.map { it.id } }
    override fun capturePreviewFrame(callback: (Result<String>) -> Unit) {
        try {
            requireMedia()
            if (capturing) throw FlutterError("capture-in-progress", "Wait for the current capture.")
            if (android.os.Build.VERSION.SDK_INT < 24) throw FlutterError("feature-unavailable", "Frame capture requires API 24.")
            val view = preview?.get()?.texture ?: throw FlutterError("no-preview", "Mount the native preview first.")
            if (view.width <= 0 || view.height <= 0 || !view.holder.surface.isValid) throw FlutterError("no-preview", "Wait for the native preview layout.")
            val bitmap = Bitmap.createBitmap(view.width.coerceAtMost(1920), view.height.coerceAtMost(1920), Bitmap.Config.ARGB_8888)
            val token = preparationGeneration
            val cacheDir = context!!.cacheDir
            val completionHandler = handler!!
            capturing = true
            PixelCopy.request(view, bitmap, { result ->
                if (result != PixelCopy.SUCCESS || token != preparationGeneration) {
                    capturing = false; bitmap.recycle(); callback(Result.failure(FlutterError("capture-failed", "Preview changed or has no frame.")))
                } else {
                    preparation.execute {
                        val outcome = runCatching {
                            val file = File.createTempFile("vn-frame-", ".png", cacheDir)
                            try { file.outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) } }
                            catch (error: Throwable) { file.delete(); throw error }
                            file.path
                        }
                        bitmap.recycle()
                        completionHandler.post {
                            capturing = false
                            if (token != preparationGeneration) {
                                outcome.getOrNull()?.let { File(it).delete() }
                                callback(Result.failure(FlutterError("operation-cancelled", "Preview capture cancelled.")))
                            } else callback(outcome)
                        }
                    }
                }
            }, completionHandler)
        } catch (error: Throwable) { callback(Result.failure(error)) }
    }
    override fun startExport(configuration: NativeExportConfiguration, callback: (Result<String>) -> Unit) {
        try {
            requireMedia()
            if (exporter != null) throw FlutterError("export-in-progress", "Wait for the current export.")
            val metadata = mediaMetadata!!
            if (configuration.width != metadata.width || configuration.height != metadata.height) throw FlutterError("unsupported-export", "Verification export uses the current render dimensions.")
            val plan = renderPlan ?: gpuComposition(listOf(NativeTimelineSegment(sourcePath!!, 0, metadata.durationMilliseconds * 1000, 0, metadata.durationMilliseconds * 1000, 1.0, 1.0, sourceEffects)), configuration.width.toInt(), configuration.height.toInt(), includeAudio = metadata.hasAudio)
            val job = ProofExporter(context!!)
            exporter = job
            try { job.start(plan, configuration, metadata.durationMilliseconds) { result -> if (exporter === job) exporter = null; callback(result) } }
            catch (error: Throwable) { if (exporter === job) exporter = null; throw error }
        } catch (error: Throwable) { callback(Result.failure(error)) }
    }
    override fun cancelExport(exportId: String) {
        requireInitialized()
        val job = exporter ?: return
        if (job.outputPath != exportId) throw FlutterError("invalid-export", "The export path does not identify the active job.")
        job.cancel()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detachActivity()
        disposeEditor()
        preparation.shutdown()
        VnEditorHostApi.setUp(binding.binaryMessenger, null)
        context = null
        events = null
        handler = null
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        detachActivity()
        activity = binding.activity
        activity?.application?.registerActivityLifecycleCallbacks(activityCallbacks)
    }
    private fun detachActivity() {
        activity?.application?.unregisterActivityLifecycleCallbacks(activityCallbacks)
        activity = null
        player?.pause()
    }
    override fun onDetachedFromActivityForConfigChanges() = detachActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() = detachActivity()
}
