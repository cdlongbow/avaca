package com.avaca.player.avaca

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.net.Uri
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.view.Window
import android.widget.FrameLayout
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
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
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import java.util.Base64
import java.util.Locale

private const val VIEW_TYPE = "avaca_player_native/video"
private const val CONTROL_CHANNEL = "avaca/player/control"
private const val EVENTS_CHANNEL = "avaca/player/events"
private const val DISCOVERY_CHANNEL = "avaca/remote/discovery"
private const val DISCOVERY_EVENTS_CHANNEL = "avaca/remote/discovery_events"
private const val DISCOVERY_SERVICE_TYPE = "_avaca-remote._udp"
private const val LOG_TAG = "AvacaPlayerNative"
private const val PROFILE_KEY_ALIAS = "avaca_remote_profile_v2"
private const val PROFILE_PREFS = "avaca_remote_profiles_v2"

/** Private Android Media3 bridge. All callbacks and player work stay on the main thread. */
class AvacaPlayerNativePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val sessions = LinkedHashMap<String, NativePlayerSession>()
    private var eventSink: EventChannel.EventSink? = null
    private lateinit var appContext: Context
    private lateinit var controlChannel: MethodChannel
    private lateinit var profileChannel: MethodChannel
    private lateinit var eventsChannel: EventChannel
    private lateinit var discoveryChannel: MethodChannel
    private lateinit var discoveryEventsChannel: EventChannel
    private var discoveryEventSink: EventChannel.EventSink? = null
    private var discoveryManager: NsdManager? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        controlChannel = MethodChannel(binding.binaryMessenger, CONTROL_CHANNEL)
        profileChannel = MethodChannel(binding.binaryMessenger, "avaca/remote/profile_store")
        eventsChannel = EventChannel(binding.binaryMessenger, EVENTS_CHANNEL)
        discoveryChannel = MethodChannel(binding.binaryMessenger, DISCOVERY_CHANNEL)
        discoveryEventsChannel = EventChannel(
            binding.binaryMessenger,
            DISCOVERY_EVENTS_CHANNEL,
        )
        controlChannel.setMethodCallHandler(this)
        profileChannel.setMethodCallHandler(this)
        discoveryChannel.setMethodCallHandler(this)
        eventsChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                eventSink = sink
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
        discoveryEventsChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                discoveryEventSink = sink
            }

            override fun onCancel(arguments: Any?) {
                discoveryEventSink = null
            }
        })
        binding.platformViewRegistry.registerViewFactory(
            VIEW_TYPE,
            NativePlayerViewFactory(this),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopDiscoveryInternal()
        sessions.values.toList().forEach { it.close() }
        sessions.clear()
        eventSink = null
        discoveryEventSink = null
        controlChannel.setMethodCallHandler(null)
        profileChannel.setMethodCallHandler(null)
        discoveryChannel.setMethodCallHandler(null)
        eventsChannel.setStreamHandler(null)
        discoveryEventsChannel.setStreamHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "start") {
            startDiscovery(result)
            return
        }
        if (call.method == "stop") {
            stopDiscoveryInternal()
            result.success(null)
            return
        }
        if (call.method == "write" || call.method == "read" || call.method == "delete") {
            handleRemoteProfileStore(call, result)
            return
        }
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

                "configureRemote" -> {
                    playerSession.configureRemote(call.argument<Map<*, *>>("profile"))
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

    private fun startDiscovery(result: MethodChannel.Result) {
        if (discoveryListener != null) {
            result.success(null)
            return
        }
        val manager = appContext.getSystemService(Context.NSD_SERVICE) as? NsdManager
        if (manager == null) {
            result.error("DISCOVERY_UNAVAILABLE", "Android NSD is unavailable.", null)
            return
        }
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) = Unit

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (serviceInfo.serviceType.trimEnd('.') != DISCOVERY_SERVICE_TYPE) return
                try {
                    manager.resolveService(serviceInfo, object : NsdManager.ResolveListener {
                        override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {
                            Log.w(LOG_TAG, "NSD resolve failed code=$errorCode")
                        }

                        override fun onServiceResolved(info: NsdServiceInfo) {
                            val host = info.host?.hostAddress ?: info.host?.hostName
                            if (host.isNullOrBlank() || info.port !in 1..65535) return
                            val txt = linkedMapOf<String, String>()
                            for ((key, value) in info.attributes) {
                                val text = value.toString(Charsets.UTF_8)
                                if (key.isNotBlank() && text.isNotBlank()) {
                                    txt[key] = text
                                }
                            }
                            val event = mapOf<String, Any?>(
                                "host" to host,
                                "port" to info.port,
                                "txt" to txt,
                            )
                            mainHandler.post { discoveryEventSink?.success(event) }
                        }
                    })
                } catch (error: Throwable) {
                    Log.w(LOG_TAG, "NSD resolve request failed", error)
                }
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) = Unit

            override fun onDiscoveryStopped(serviceType: String) = Unit

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.w(LOG_TAG, "NSD discovery start failed code=$errorCode")
                try {
                    manager.stopServiceDiscovery(this)
                } catch (_: Throwable) {
                    // The listener is already terminal.
                }
                if (discoveryListener === this) discoveryListener = null
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.w(LOG_TAG, "NSD discovery stop failed code=$errorCode")
                if (discoveryListener === this) discoveryListener = null
            }
        }
        try {
            discoveryManager = manager
            discoveryListener = listener
            manager.discoverServices(
                DISCOVERY_SERVICE_TYPE,
                NsdManager.PROTOCOL_DNS_SD,
                listener,
            )
            result.success(null)
        } catch (error: Throwable) {
            discoveryListener = null
            discoveryManager = null
            result.error("DISCOVERY_START_FAILED", "Android NSD discovery failed.", null)
        }
    }

    private fun stopDiscoveryInternal() {
        val manager = discoveryManager
        val listener = discoveryListener
        discoveryListener = null
        discoveryManager = null
        if (manager != null && listener != null) {
            try {
                manager.stopServiceDiscovery(listener)
            } catch (_: Throwable) {
                // A listener that already failed is terminal.
            }
        }
    }

    private fun handleRemoteProfileStore(call: MethodCall, result: MethodChannel.Result) {
        // This method is intentionally hosted by the already bundled native
        // plugin so AVACA does not need a plaintext SharedPreferences fallback.
        // The preference value below is always IV || AES-GCM ciphertext.
        val key = call.argument<String>("key")
        if (key.isNullOrBlank() ||
            key.length > 320 ||
            !key.matches(Regex("^[A-Za-z0-9._~-]+$"))) {
            result.error("INVALID_PROFILE_KEY", "The remote profile key is invalid.", null)
            return
        }
        try {
            val preferences = appContext.getSharedPreferences(PROFILE_PREFS, Context.MODE_PRIVATE)
            when (call.method) {
                "write" -> {
                    val cleartext = call.argument<ByteArray>("value")
                    if (cleartext == null || cleartext.isEmpty() || cleartext.size > 64 * 1024) {
                        result.error("INVALID_PROFILE", "The remote profile payload is invalid.", null)
                        return
                    }
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    // Let Android Keystore choose the randomized GCM nonce.
                    // Supplying an app-generated nonce is rejected by newer
                    // Android providers with CALLER_NONCE_PROHIBITED.
                    cipher.init(Cipher.ENCRYPT_MODE, profileKey())
                    val iv = cipher.iv
                    val ciphertext = cipher.doFinal(cleartext)
                    val envelope = ByteArray(iv.size + ciphertext.size)
                    iv.copyInto(envelope, 0)
                    ciphertext.copyInto(envelope, iv.size)
                    preferences.edit()
                        .putString(key, Base64.getEncoder().withoutPadding().encodeToString(envelope))
                        .apply()
                    cleartext.fill(0)
                    result.success(null)
                }
                "read" -> {
                    val encoded = preferences.getString(key, null)
                    if (encoded == null) {
                        result.success(null)
                        return
                    }
                    val envelope = Base64.getDecoder().decode(encoded)
                    if (envelope.size < 12 + 16) {
                        result.error("PROFILE_CORRUPT", "The protected remote profile is invalid.", null)
                        return
                    }
                    val iv = envelope.copyOfRange(0, 12)
                    val ciphertext = envelope.copyOfRange(12, envelope.size)
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.DECRYPT_MODE, profileKey(), GCMParameterSpec(128, iv))
                    result.success(cipher.doFinal(ciphertext))
                }
                "delete" -> {
                    preferences.edit().remove(key).apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: Throwable) {
            result.error("PROFILE_STORAGE", "Secure remote profile storage failed.", null)
        }
    }

    private fun profileKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(PROFILE_KEY_ALIAS, null)
        if (existing is SecretKey) return existing
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                PROFILE_KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setKeySize(256)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return generator.generateKey()
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
    private var remoteProfile: AndroidRemoteProfile? = null

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

    fun configureRemote(profile: Map<*, *>?) {
        if (profile == null) throw IllegalArgumentException("Remote profile is missing.")
        val serverId = profile["serverId"]?.toString()?.trim().orEmpty()
        val clientId = profile["clientId"]?.toString()?.trim().orEmpty()
        val host = profile["host"]?.toString()?.trim().orEmpty()
        val port = (profile["port"] as? Number)?.toInt() ?: 0
        val pin = mapBytes(profile, "certificateSha256Pin")
        val secret = mapBytes(profile, "pairingSecret")
        if (serverId.isBlank() || clientId.isBlank() || host.isBlank() ||
            port !in 1..65535 || pin?.size != 32 || secret?.size != 32) {
            throw IllegalArgumentException("Remote client profile is invalid.")
        }
        remoteProfile?.wipe()
        remoteProfile = AndroidRemoteProfile(
            serverId,
            clientId,
            host,
            port,
            pin.copyOf(),
            secret.copyOf(),
        )
    }

    fun open(request: Map<*, *>?) {
        if (request == null) throw IllegalArgumentException("Player request is missing.")
        val source = request["source"] as? Map<*, *>
            ?: throw IllegalArgumentException("Player source is missing.")
        val sourceKind = source["kind"]?.toString()
        val uri = source["uri"]?.toString()?.trim().orEmpty()
        val prefix = "avaca-quic://"
        val opaqueResource = uri.removePrefix(prefix)
        if (sourceKind != "remote" ||
            !uri.startsWith(prefix) ||
            opaqueResource.isBlank() ||
            opaqueResource.any { it == '/' || it == '\\' || it == '?' || it == '#' } ||
            source.containsKey("headers")) {
            throw IllegalArgumentException(
                "Only an opaque AVACA QUIC resource is supported.",
            )
        }
        val sessionId = source["playbackSessionId"]?.toString()?.trim().orEmpty()
        val resourceId = source["resourceId"]?.toString()?.trim()
            ?.takeUnless { it.isEmpty() } ?: opaqueResource
        val grant = mapBytes(source, "playbackGrant")
        val contentLength = ((source["contentLength"] as? Number)
            ?: (source["length"] as? Number))?.toLong()
        if (sessionId.isBlank() || resourceId.isBlank() || grant?.size != 32 ||
            contentLength == null || contentLength < 0L) {
            throw IllegalArgumentException("AVACA remote playback descriptor is incomplete.")
        }
        val profileMap = source["profile"] as? Map<*, *>
        if (profileMap != null) configureRemote(profileMap)
        val currentPlayer = player ?: run {
            pendingRequest = request
            return
        }
        val configuredProfile = remoteProfile
            ?: throw IllegalStateException("An authenticated AVACA remote profile is required.")
        val descriptor = AndroidRemoteDescriptor(
            sessionId,
            resourceId,
            grant.copyOf(),
            contentLength,
        )
        try {
            val factory = AvacaRemoteDataSourceFactory(
                configuredProfile.copyForDataSource(),
                descriptor,
            )
            val mediaSource = ProgressiveMediaSource.Factory(factory)
                .createMediaSource(MediaItem.fromUri(Uri.parse(uri)))
            currentPlayer.stop()
            currentPlayer.setMediaSource(mediaSource)
            currentPlayer.prepare()
            playbackError = false
        } catch (error: Throwable) {
            descriptor.wipe()
            throw error
        }
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
        pendingRequest = null
        remoteProfile?.wipe()
        remoteProfile = null
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

private fun mapBytes(map: Map<*, *>, key: String): ByteArray? {
    return when (val value = map[key]) {
        is ByteArray -> value
        is List<*> -> {
            if (value.any { it !is Number }) null
            else value.map { (it as Number).toInt().toByte() }.toByteArray()
        }
        else -> null
    }
}
