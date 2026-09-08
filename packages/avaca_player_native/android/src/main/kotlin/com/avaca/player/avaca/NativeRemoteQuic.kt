package com.avaca.player.avaca

/** JNI boundary for the Android native playback data-plane. */
internal object NativeRemoteQuic {
    init {
        System.loadLibrary("avaca_remote_android")
    }

    external fun nativeOpen(
        serverId: String,
        clientId: String,
        host: String,
        port: Int,
        certificateSha256Pin: ByteArray,
        pairingSecret: ByteArray,
        playbackSessionId: String,
        resourceId: String,
        playbackGrant: ByteArray,
        resourceLength: Long,
    ): Long

    external fun nativeRead(
        handle: Long,
        offset: Long,
        destination: ByteArray,
        destinationOffset: Int,
        length: Int,
    ): Int

    external fun nativeCancel(handle: Long): Boolean

    external fun nativeClose(handle: Long)
}
