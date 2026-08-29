package com.avaca.player.avaca

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.view.Window
import android.widget.FrameLayout
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.embedding.engine.plugins.FlutterPlugin
import java.io.File
import java.util.Locale

private const val VIEW_TYPE = "avaca_player_native/video"
private const val CONTROL_CHANNEL = "avaca/player/control"
private const val EVENTS_CHANNEL = "avaca/player/events"
private const val LOG_TAG = "AvacaPlayerNative"

/** Private Android Media3 bridge. All callbacks and player work stay on the main thread. */
class AvacaPlayerNativePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val sessions = LinkedHashMap<String, NativePlayerSession>()
    private var eventSink: EventChannel.EventSink? = null
    private lateinit var appContext: Context
    private lateinit var controlChannel: MethodChannel
    private lateinit var eventsChannel: EventChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        controlChannel = MethodChannel(binding.binaryMessenger, CONTROL_CHANNEL)
        eventsChannel = EventChannel(binding.binaryMessenger, EVENTS_CHANNEL)
        controlChannel.setMethodCallHandler(this)
        eventsChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                eventSink = sink
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
        binding.platformViewRegistry.registerViewFactory(
            VIEW_TYPE,
            NativePlayerViewFactory(this),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        sessions.values.toList().forEach { it.close() }
        sessions.clear()
        eventSink = null
        controlChannel.setMethodCallHandler(null)
        eventsChannel.setStreamHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val sessionId = call.argument<String>("sessionId")
        if (call.method == "createSession") {
            if (sessionId.isNullOrBlank()) {
                result.error("INVALID_SESSION", "The player session id is missing.", null)
                return
            }
            session(sessionId)
            result.success(
                mapOf(
                    "surfaceType" to "androidPlatformView",
                    "viewType" to VIEW_TYPE,
                ),
            )
            return
        }
        if (sessionId.isNullOrBlank()) {
            result.error("INVALID_SESSION", "The player session id is missing.", null)
            return
        }

        val playerSession = session(sessionId)
        try {
            when (call.method) {
                "open" -> {
                    playerSession.open(call.argument<Map<*, *>>("request"))
                    result.success(null)
                }

                "play" -> {
                    playerSession.play()
                    result.success(null)
                }

                "pause" -> {
                    playerSession.pause()
                    result.success(null)
                }

                "seek" -> {
                    playerSession.seek(
                        call.argument<Number>("positionMs")?.toLong() ?: 0L,
                        call.argument<Number>("seekGeneration")?.toInt() ?: 0,
                    )
                    result.success(null)
                }

                "setSpeed" -> {
                    playerSession.setSpeed(call.argument<Number>("speed")?.toFloat() ?: 1f)
                    result.success(null)
                }

                "selectSubtitle" -> {
                    playerSession.selectSubtitle(call.argument<String>("trackId"))
                    result.success(null)
                }

                "setFullscreen" -> {
                    playerSession.setFullscreen(call.argument<Boolean>("fullscreen") == true)
                    result.success(null)
                }

                "getDiagnostics" -> result.success(playerSession.diagnostics())

                "close" -> {
                    playerSession.close()
                    sessions.remove(sessionId)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            playerSession.emitError(error)
            result.error("PLAYER_NATIVE_ERROR", "Native player operation failed.", null)
        }
    }

    internal fun session(sessionId: String): NativePlayerSession {
        return sessions.getOrPut(sessionId) {
            NativePlayerSession(sessionId, appContext, mainHandler, ::emit)
        }
    }

    internal fun emit(event: Map<String, Any?>) {
        eventSink?.success(event)
    }
}

private class NativePlayerViewFactory(
    private val plugin: AvacaPlayerNativePlugin,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val sessionId = (args as? Map<*, *>)?.get("sessionId")?.toString()
            ?: "view-$viewId"
        return NativePlayerPlatformView(context, plugin.session(sessionId))
    }
}

private class NativePlayerPlatformView(
    context: Context,
    private val playerSession: NativePlayerSession,
) : PlatformView {
    private val playerView = PlayerView(context).apply {
        useController = false
        resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
        setShowBuffering(PlayerView.SHOW_BUFFERING_ALWAYS)
        layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        )
    }

    init {
        playerSession.attach(context, playerView)
    }

    override fun getView(): View = playerView

    override fun dispose() {
        playerSession.detach(playerView)
    }
}

internal class NativePlayerSession(
    private val sessionId: String,
    private val applicationContext: Context,
    private val handler: Handler,
    private val emitEvent: (Map<String, Any?>) -> Unit,
) {
    private val updateRunnable = object : Runnable {
        override fun run() {
            if (closed) return
            emitState()
            handler.postDelayed(this, 250L)
        }
    }

    private var player: ExoPlayer? = null
    private var playerView: PlayerView? = null
    private var activity: Activity? = null
    private var pendingRequest: Map<*, *>? = null
    private var sequence = 0
    private var speed = 1f
    private var selectedSubtitleTrackId: String? = null
    private var subtitleTracks: List<Map<String, Any?>> = emptyList()
    private var subtitleSelections: Map<String, SubtitleSelection> = emptyMap()
    private var fullscreen = false
    private var playbackError = false
    private var closed = false

    init {
        handler.post(updateRunnable)
    }

    fun attach(context: Context, view: PlayerView) {
        if (closed) return
        playerView = view
        activity = context.findActivity()
        if (player == null) {
            player = ExoPlayer.Builder(context).build().also { created ->
                created.addListener(listener)
                created.setPlaybackSpeed(speed)
            }
        }
        view.player = player
        pendingRequest?.let { request ->
            pendingRequest = null
            open(request)
        }
    }

    fun detach(view: PlayerView) {
        if (playerView === view) {
            view.player = null
            playerView = null
            activity = null
        }
    }

    fun open(request: Map<*, *>?) {
        if (request == null) throw IllegalArgumentException("Player request is missing.")
        pendingRequest = request
        val currentPlayer = player ?: return
        val source = request["source"] as? Map<*, *>
            ?: throw IllegalArgumentException("Player source is missing.")
        val sourceKind = source["kind"]?.toString()
        val mediaUri = when (sourceKind) {
            "local" -> Uri.fromFile(File(source["path"]?.toString() ?: ""))
            "remote" -> Uri.parse(source["uri"]?.toString() ?: "")
            else -> throw IllegalArgumentException("Unsupported player source.")
        }
        if (mediaUri.toString().isBlank()) {
            throw IllegalArgumentException("Player source URI is empty.")
        }

        val headers = mutableMapOf<String, String>()
        val rawHeaders = source["headers"] as? Map<*, *>
        rawHeaders?.forEach { (key, value) ->
            if (key != null && value != null) headers[key.toString()] = value.toString()
        }
        val httpFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setDefaultRequestProperties(headers)
        val dataSourceFactory = DefaultDataSource.Factory(applicationContext, httpFactory)
        val mediaItemBuilder = MediaItem.Builder()
            .setUri(mediaUri)
            .setMediaId(request["workCode"]?.toString() ?: sessionId)
        val mimeType = source["mimeType"]?.toString()
        if (!mimeType.isNullOrBlank()) mediaItemBuilder.setMimeType(mimeType)

        val mediaSource = ProgressiveMediaSource.Factory(dataSourceFactory)
            .createMediaSource(mediaItemBuilder.build())
        selectedSubtitleTrackId = null
        subtitleTracks = emptyList()
        subtitleSelections = emptyMap()
        playbackError = false
        currentPlayer.setMediaSource(mediaSource)
        currentPlayer.setPlaybackSpeed(speed)
        currentPlayer.prepare()
        val initialPosition = (request["initialPositionMs"] as? Number)?.toLong() ?: 0L
        currentPlayer.seekTo(initialPosition.coerceAtLeast(0L))
        currentPlayer.playWhenReady = false
        emitState(phase = "loading")
    }

    fun play() {
        requirePlayer().play()
    }

    fun pause() {
        requirePlayer().pause()
    }

    fun seek(positionMs: Long, generation: Int) {
        val targetMs = positionMs.coerceAtLeast(0L)
        requirePlayer().seekTo(targetMs)
        Log.i(
            LOG_TAG,
            "seek session=$sessionId generation=$generation targetMs=$targetMs",
        )
        emitState(seekGeneration = generation)
        handler.postDelayed({
            if (!closed) {
                Log.i(
                    LOG_TAG,
                    "seek_settled session=$sessionId " +
                        "generation=$generation positionMs=${player?.currentPosition ?: -1L}",
                )
            }
        }, 750L)
    }

    fun setSpeed(value: Float) {
        speed = value.coerceIn(0.5f, 4f)
        player?.setPlaybackSpeed(speed)
        Log.i(LOG_TAG, "speed session=$sessionId value=$speed")
        emitState()
    }

    fun selectSubtitle(trackId: String?) {
        val currentPlayer = requirePlayer()
        val builder = currentPlayer.trackSelectionParameters.buildUpon()
            .clearOverridesOfType(C.TRACK_TYPE_TEXT)
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, trackId == null)
        if (trackId != null) {
            val selection = subtitleSelections[trackId]
                ?: throw IllegalArgumentException("Subtitle track is unavailable.")
            builder.setOverrideForType(
                TrackSelectionOverride(selection.group, selection.index),
            )
        }
        currentPlayer.trackSelectionParameters = builder.build()
        selectedSubtitleTrackId = trackId
        emitState(subtitleSelectionChanged = true)
    }

    fun setFullscreen(value: Boolean) {
        fullscreen = value
        val window = activity?.window ?: return
        window.setFullscreenFlags(value)
        emitState()
    }

    fun diagnostics(): Map<String, Any?> {
        val currentPlayer = player
        return mapOf(
            "sessionId" to sessionId,
            "lastEvent" to "media3",
            "droppedEvents" to 0,
            "values" to mapOf(
                "backend" to "media3",
                "surface" to "android_platform_view",
                "videoMimeType" to currentPlayer?.videoFormat?.sampleMimeType,
                "audioMimeType" to currentPlayer?.audioFormat?.sampleMimeType,
            ),
        )
    }

    fun emitError(error: Throwable) {
        playbackError = true
        emitEvent(
            mapOf(
                "type" to "error",
                "sessionId" to sessionId,
                "sequence" to ++sequence,
                "errorType" to "unknown",
                "localizedMessageKey" to "playerErrorUnknown",
                "diagnosticCode" to "native_operation_failed",
                "recoverable" to true,
            ),
        )
        emitState(phase = "error")
    }

    fun close() {
        if (closed) return
        closed = true
        Log.i(LOG_TAG, "close session=$sessionId playerPresent=${player != null}")
        handler.removeCallbacks(updateRunnable)
        playerView?.player = null
        playerView = null
        activity = null
        player?.removeListener(listener)
        player?.release()
        player = null
        Log.i(LOG_TAG, "release_complete session=$sessionId")
    }

    private fun requirePlayer(): ExoPlayer {
        return player ?: throw IllegalStateException("The native player surface is not attached.")
    }

    private val listener = object : Player.Listener {
        override fun onTracksChanged(tracks: Tracks) {
            updateSubtitleTracks(tracks)
            emitState()
        }

        override fun onPlaybackParametersChanged(playbackParameters: PlaybackParameters) {
            speed = playbackParameters.speed
            emitState()
        }

        override fun onPlayerError(error: PlaybackException) {
            playbackError = true
            val errorType = when {
                error.errorCodeName.contains("DECODER", ignoreCase = true) -> "decoderFailure"
                error.errorCodeName.contains("AUDIO", ignoreCase = true) -> "audioFailure"
                error.errorCodeName.contains("RENDERER", ignoreCase = true) -> "rendererFailure"
                error.errorCodeName.contains("SOURCE", ignoreCase = true) -> "mediaOpenFailed"
                else -> "unknown"
            }
            emitEvent(
                mapOf(
                    "type" to "error",
                    "sessionId" to sessionId,
                    "sequence" to ++sequence,
                    "errorType" to errorType,
                    "localizedMessageKey" to "playerErrorMediaOpenFailed",
                    "diagnosticCode" to "media3_${error.errorCode}",
                    "recoverable" to true,
                ),
            )
            emitState(phase = "error")
        }
    }

    private fun updateSubtitleTracks(tracks: Tracks) {
        val nextTracks = mutableListOf<Map<String, Any?>>()
        val nextSelections = mutableMapOf<String, SubtitleSelection>()
        var selected: String? = null
        var index = 0
        for (group in tracks.groups) {
            if (group.type != C.TRACK_TYPE_TEXT) continue
            for (trackIndex in 0 until group.length) {
                val format = group.getTrackFormat(trackIndex)
                val id = (++index).toString()
                val formatName = subtitleFormat(format)
                nextTracks += mapOf(
                    "id" to id,
                    "title" to format.label,
                    "language" to format.language,
                    "format" to formatName,
                )
                nextSelections[id] = SubtitleSelection(group.mediaTrackGroup, trackIndex)
                if (group.isTrackSelected(trackIndex)) selected = id
            }
        }
        subtitleTracks = nextTracks
        subtitleSelections = nextSelections
        if (selectedSubtitleTrackId == null || selected != null) {
            selectedSubtitleTrackId = selected
        }
    }

    private fun subtitleFormat(format: Format): String {
        val mime = format.sampleMimeType?.lowercase(Locale.US).orEmpty()
        val codecs = format.codecs?.lowercase(Locale.US).orEmpty()
        val descriptor = "$mime $codecs"
        return when {
            descriptor.contains("ass") -> "ass"
            descriptor.contains("ssa") -> "ssa"
            else -> "other"
        }
    }

    private fun emitState(
        phase: String? = null,
        seekGeneration: Int? = null,
        subtitleSelectionChanged: Boolean = false,
    ) {
        val currentPlayer = player
        val playbackState = currentPlayer?.playbackState
        val resolvedPhase = phase ?: when {
            playbackError -> "error"
            currentPlayer == null -> "idle"
            playbackState == ExoPlayer.STATE_BUFFERING -> "buffering"
            playbackState == ExoPlayer.STATE_ENDED -> "completed"
            currentPlayer.isPlaying -> "playing"
            playbackState == ExoPlayer.STATE_READY -> "paused"
            else -> "loading"
        }
        emitEvent(
            mapOf(
                "type" to "state",
                "sessionId" to sessionId,
                "sequence" to ++sequence,
                "phase" to resolvedPhase,
                "positionMs" to (currentPlayer?.currentPosition ?: 0L),
                "durationMs" to (currentPlayer?.duration?.takeUnless { it == C.TIME_UNSET } ?: 0L),
                "bufferedPositionMs" to (currentPlayer?.bufferedPosition ?: 0L),
                "playing" to (currentPlayer?.isPlaying == true),
                "buffering" to (playbackState == ExoPlayer.STATE_BUFFERING),
                "completed" to (playbackState == ExoPlayer.STATE_ENDED),
                "tracks" to subtitleTracks,
                "selectedSubtitleTrackId" to selectedSubtitleTrackId,
                "subtitleSelectionChanged" to subtitleSelectionChanged,
                "speed" to speed.toDouble(),
                "fullscreen" to fullscreen,
                "seekGeneration" to seekGeneration,
            ),
        )
    }

    private data class SubtitleSelection(
        val group: androidx.media3.common.TrackGroup,
        val index: Int,
    )
}

private fun Context.findActivity(): Activity? {
    var current: Context = this
    while (current is ContextWrapper) {
        if (current is Activity) return current
        current = current.baseContext
    }
    return current as? Activity
}

private fun Window.setFullscreenFlags(enabled: Boolean) {
    decorView.systemUiVisibility = if (enabled) {
        View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
            View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
    } else {
        View.SYSTEM_UI_FLAG_LAYOUT_STABLE
    }
}
