package com.avaca.player.avaca

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DataSource
import java.io.IOException

/** A copy-owned profile used only by a native Media3 DataSource factory. */
internal data class AndroidRemoteProfile(
    val serverId: String,
    val clientId: String,
    val host: String,
    val port: Int,
    val certificateSha256Pin: ByteArray,
    val pairingSecret: ByteArray,
) {
    fun copyForDataSource(): AndroidRemoteProfile = AndroidRemoteProfile(
        serverId,
        clientId,
        host,
        port,
        certificateSha256Pin.copyOf(),
        pairingSecret.copyOf(),
    )

    fun wipe() {
        certificateSha256Pin.fill(0)
        pairingSecret.fill(0)
    }
}

internal data class AndroidRemoteDescriptor(
    val playbackSessionId: String,
    val resourceId: String,
    val playbackGrant: ByteArray,
    val length: Long,
) {
    fun copyForDataSource(): AndroidRemoteDescriptor = AndroidRemoteDescriptor(
        playbackSessionId,
        resourceId,
        playbackGrant.copyOf(),
        length,
    )

    fun wipe() {
        playbackGrant.fill(0)
    }
}

internal class AvacaRemoteDataSourceFactory(
    private val profile: AndroidRemoteProfile,
    private val descriptor: AndroidRemoteDescriptor,
) : DataSource.Factory {
    override fun createDataSource(): DataSource = AvacaRemoteDataSource(
        profile.copyForDataSource(),
        descriptor.copyForDataSource(),
    )
}

/**
 * Media3 range adapter.  Every read is an absolute authenticated QUIC range
 * request in native code; this class never opens a URL or creates a file.
 */
internal class AvacaRemoteDataSource(
    private val profile: AndroidRemoteProfile,
    private val descriptor: AndroidRemoteDescriptor,
) : BaseDataSource(/* isNetwork = */ true) {
    private var dataSpec: DataSpec? = null
    private var uri: Uri? = null
    private var handle = 0L
    private var position = 0L
    private var bytesRemaining = 0L

    override fun open(dataSpec: DataSpec): Long {
        this.dataSpec = dataSpec
        uri = dataSpec.uri
        position = dataSpec.position
        val available = (descriptor.length - position).coerceAtLeast(0L)
        bytesRemaining = if (dataSpec.length == C.LENGTH_UNSET.toLong()) {
            available
        } else {
            dataSpec.length.coerceAtMost(available)
        }
        if (position < 0L || position > descriptor.length || bytesRemaining < 0L) {
            throw IOException("AVACA remote range is invalid")
        }
        handle = NativeRemoteQuic.nativeOpen(
            profile.serverId,
            profile.clientId,
            profile.host,
            profile.port,
            profile.certificateSha256Pin,
            profile.pairingSecret,
            descriptor.playbackSessionId,
            descriptor.resourceId,
            descriptor.playbackGrant,
            descriptor.length,
        )
        if (handle == 0L) {
            close()
            throw IOException("AVACA remote authentication or range open failed")
        }
        transferInitializing(dataSpec)
        transferStarted(dataSpec)
        return bytesRemaining
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        if (handle == 0L) throw IOException("AVACA remote source is not open")
        if (bytesRemaining == 0L) return C.RESULT_END_OF_INPUT
        val requested = minOf(length.toLong(), bytesRemaining).toInt()
        val read = NativeRemoteQuic.nativeRead(handle, position, buffer, offset, requested)
        if (read == -2) throw IOException("AVACA remote range read cancelled")
        if (read < 0) throw IOException("AVACA remote range read failed")
        if (read == 0) throw IOException("AVACA remote range read returned no data")
        position += read
        bytesRemaining -= read
        bytesTransferred(read)
        return read
    }

    override fun getUri(): Uri? = uri

    override fun close() {
        val current = handle
        handle = 0L
        if (current != 0L) {
            NativeRemoteQuic.nativeCancel(current)
            NativeRemoteQuic.nativeClose(current)
            transferEnded()
        }
        dataSpec = null
        uri = null
        profile.wipe()
        descriptor.wipe()
    }
}
