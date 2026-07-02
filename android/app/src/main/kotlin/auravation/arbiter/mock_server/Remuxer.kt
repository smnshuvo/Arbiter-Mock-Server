package auravation.arbiter.mock_server

import android.content.Context
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import android.util.Log
import java.io.File
import java.nio.ByteBuffer

/** Outcome of a conversion attempt; [reason] is user-presentable when [ok] is false. */
data class RemuxResult(val ok: Boolean, val reason: String? = null)

/**
 * Container conversion into browser-playable MP4.
 *
 * The video stream (H.264/HEVC) is always stream-copied — never re-encoded, so the job
 * runs at disk speed. Audio is stream-copied when MP4 can carry it (AAC/MP3); any other
 * audio the device can decode (AC3/EAC3/DTS/Vorbis/Opus/…) is transcoded to AAC-LC via
 * [AudioTranscoder] — audio transcoding runs many times faster than realtime, so it
 * barely changes the total time. Files whose video is incompatible, or whose audio has
 * no on-device decoder, fail with a user-presentable reason.
 */
object Remuxer {

    private const val TAG = "Remuxer"
    internal const val TIMEOUT_US = 10_000L
    private const val COPY_BUFFER_BYTES = 2 * 1024 * 1024

    /** Priming holds early video samples in RAM; interleaved sources need only a few. */
    private const val MAX_HELD_VIDEO_BYTES = 64L * 1024 * 1024

    private val VIDEO_MIMES = setOf(
        MediaFormat.MIMETYPE_VIDEO_AVC,
        MediaFormat.MIMETYPE_VIDEO_HEVC,
    )

    /** Audio MP4 carries as-is; everything else goes through the transcoder. */
    private val AUDIO_COPY_MIMES = setOf(
        MediaFormat.MIMETYPE_AUDIO_AAC,
        MediaFormat.MIMETYPE_AUDIO_MPEG,
    )

    fun remux(
        context: Context,
        srcUri: Uri,
        outFile: File,
        onProgress: (Int) -> Unit = {},
        isCancelled: () -> Boolean = { false },
    ): RemuxResult {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        var transcoder: AudioTranscoder? = null
        try {
            extractor.setDataSource(context, srcUri, null)

            var videoTrack = -1
            var audioTrack = -1
            var audioCopy = false
            var durationUs = 0L
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (videoTrack < 0 && mime in VIDEO_MIMES) videoTrack = i
                if (audioTrack < 0 && mime.startsWith("audio/")) {
                    audioTrack = i
                    audioCopy = mime in AUDIO_COPY_MIMES
                }
                if (format.containsKey(MediaFormat.KEY_DURATION)) {
                    durationUs = maxOf(durationUs, format.getLong(MediaFormat.KEY_DURATION))
                }
            }
            if (videoTrack < 0) {
                return fail(outFile, "no browser-compatible video track")
            }

            if (audioTrack >= 0 && !audioCopy) {
                val srcFormat = extractor.getTrackFormat(audioTrack)
                transcoder = AudioTranscoder.create(srcFormat)
                    ?: return fail(
                        outFile,
                        "audio codec ${srcFormat.getString(MediaFormat.KEY_MIME)} " +
                            "is not supported by this device",
                    )
            }

            extractor.selectTrack(videoTrack)
            if (audioTrack >= 0) extractor.selectTrack(audioTrack)

            outFile.parentFile?.mkdirs()
            muxer = MediaMuxer(outFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            val copyBuffer = ByteBuffer.allocateDirect(COPY_BUFFER_BYTES)
            val heldVideo = ArrayList<Pair<MediaCodec.BufferInfo, ByteArray>>()

            // MediaMuxer must know every track format before start(), but the AAC
            // encoder's true output format (with csd-0) only exists after it has eaten
            // data. So when transcoding: prime the codec chain with audio samples first,
            // holding the video samples encountered meanwhile in memory.
            if (transcoder != null) {
                var heldBytes = 0L
                while (transcoder.outputFormat == null) {
                    if (isCancelled()) return fail(outFile, "cancelled")
                    val track = extractor.sampleTrackIndex
                    if (track < 0) break
                    if (track == videoTrack) {
                        copyBuffer.clear()
                        val size = extractor.readSampleData(copyBuffer, 0)
                        if (size < 0) break
                        val bytes = ByteArray(size)
                        copyBuffer.position(0)
                        copyBuffer.get(bytes, 0, size)
                        val bi = MediaCodec.BufferInfo()
                        bi.set(0, size, extractor.sampleTime, syncFlag(extractor))
                        heldVideo.add(bi to bytes)
                        heldBytes += size
                        if (heldBytes > MAX_HELD_VIDEO_BYTES) {
                            return fail(outFile, "audio starts too late in the file")
                        }
                    } else {
                        transcoder.queueSampleFrom(extractor, null)
                        transcoder.drain(null)
                    }
                    extractor.advance()
                }
                if (transcoder.outputFormat == null) {
                    return fail(outFile, "audio transcoder produced no output")
                }
            }

            val muxVideo = muxer.addTrack(extractor.getTrackFormat(videoTrack))
            val muxAudio = when {
                transcoder != null -> muxer.addTrack(transcoder.outputFormat!!)
                audioTrack >= 0 -> muxer.addTrack(extractor.getTrackFormat(audioTrack))
                else -> -1
            }
            muxer.start()
            val theMuxer = muxer
            val audioSink: (MediaCodec.BufferInfo, ByteBuffer) -> Unit =
                { bi, buf -> theMuxer.writeSampleData(muxAudio, buf, bi) }

            for ((bi, bytes) in heldVideo) {
                theMuxer.writeSampleData(muxVideo, ByteBuffer.wrap(bytes), bi)
            }
            heldVideo.clear()
            transcoder?.flushPending(audioSink)

            val info = MediaCodec.BufferInfo()
            var lastPct = -1
            while (true) {
                if (isCancelled()) return fail(outFile, "cancelled")
                val track = extractor.sampleTrackIndex
                if (track < 0) break
                val sampleTimeUs = extractor.sampleTime
                if (track == audioTrack && transcoder != null) {
                    transcoder.queueSampleFrom(extractor, audioSink)
                    extractor.advance()
                    transcoder.drain(audioSink)
                } else {
                    copyBuffer.clear()
                    info.offset = 0
                    info.size = extractor.readSampleData(copyBuffer, 0)
                    if (info.size < 0) break
                    info.presentationTimeUs = sampleTimeUs
                    info.flags = syncFlag(extractor)
                    theMuxer.writeSampleData(
                        if (track == videoTrack) muxVideo else muxAudio, copyBuffer, info,
                    )
                    extractor.advance()
                }
                if (durationUs > 0 && sampleTimeUs >= 0) {
                    val pct = (sampleTimeUs * 100 / durationUs).toInt().coerceIn(0, 99)
                    if (pct != lastPct) {
                        lastPct = pct
                        onProgress(pct)
                    }
                }
            }
            transcoder?.finish(audioSink)
            theMuxer.stop()
            onProgress(100)
            return RemuxResult(true)
        } catch (e: Exception) {
            Log.w(TAG, "Remux failed for $srcUri: ${e.message}")
            return fail(outFile, e.message ?: "conversion error")
        } finally {
            transcoder?.release()
            try {
                muxer?.release()
            } catch (_: Exception) {
            }
            try {
                extractor.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun syncFlag(extractor: MediaExtractor): Int =
        if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
            MediaCodec.BUFFER_FLAG_KEY_FRAME
        } else {
            0
        }

    private fun fail(outFile: File, reason: String): RemuxResult {
        Log.w(TAG, "Remux aborted: $reason")
        outFile.delete()
        return RemuxResult(false, reason)
    }
}

/**
 * Synchronous decode→re-encode chain producing AAC-LC. The encoder is created lazily
 * from the decoder's first output format, so channel count and sample rate always match
 * the PCM the decoder actually emits (which can differ from the container metadata,
 * e.g. decoders that downmix).
 */
private class AudioTranscoder private constructor(private val decoder: MediaCodec) {

    companion object {
        private const val TAG = "AudioTranscoder"

        /** Null when the device has no decoder for the track's codec. */
        fun create(srcFormat: MediaFormat): AudioTranscoder? = try {
            val mime = srcFormat.getString(MediaFormat.KEY_MIME)!!
            val decoder = MediaCodec.createDecoderByType(mime)
            decoder.configure(srcFormat, null, null, 0)
            decoder.start()
            AudioTranscoder(decoder)
        } catch (e: Exception) {
            Log.w(TAG, "No usable audio decoder: ${e.message}")
            null
        }
    }

    /** The AAC encoder's real output format (with csd-0); null until primed. */
    var outputFormat: MediaFormat? = null
        private set

    private var encoder: MediaCodec? = null
    private var encoderDone = false
    private var channels = 2
    private var sampleRate = 48_000
    private val pending = ArrayList<Pair<MediaCodec.BufferInfo, ByteArray>>()
    private val decInfo = MediaCodec.BufferInfo()
    private val encInfo = MediaCodec.BufferInfo()

    /** Pushes the extractor's current (audio) sample into the decoder, draining if full. */
    fun queueSampleFrom(
        extractor: MediaExtractor,
        sink: ((MediaCodec.BufferInfo, ByteBuffer) -> Unit)?,
    ) {
        var attempts = 0
        while (true) {
            val idx = decoder.dequeueInputBuffer(Remuxer.TIMEOUT_US)
            if (idx >= 0) {
                val buf = decoder.getInputBuffer(idx) ?: throw IllegalStateException("no buffer")
                buf.clear()
                val size = extractor.readSampleData(buf, 0)
                if (size < 0) {
                    decoder.queueInputBuffer(idx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                } else {
                    decoder.queueInputBuffer(idx, 0, size, extractor.sampleTime, 0)
                }
                return
            }
            drain(sink)
            if (++attempts > 1000) throw IllegalStateException("audio decoder stalled")
        }
    }

    /** Moves decoded PCM into the encoder and encoded AAC out to [sink] (or [pending]). */
    fun drain(sink: ((MediaCodec.BufferInfo, ByteBuffer) -> Unit)?) {
        loop@ while (true) {
            val idx = decoder.dequeueOutputBuffer(decInfo, 0)
            when {
                idx == MediaCodec.INFO_TRY_AGAIN_LATER -> break@loop
                idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED ->
                    onDecoderFormat(decoder.outputFormat)
                idx >= 0 -> {
                    if (decInfo.size > 0) {
                        if (encoder == null) onDecoderFormat(decoder.outputFormat)
                        val pcm = decoder.getOutputBuffer(idx)
                        if (pcm != null) {
                            pcm.position(decInfo.offset)
                            pcm.limit(decInfo.offset + decInfo.size)
                            feedEncoder(pcm, decInfo.presentationTimeUs, sink)
                        }
                    }
                    if (decInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        queueEncoderEos(sink)
                    }
                    decoder.releaseOutputBuffer(idx, false)
                }
                // Ignore legacy INFO_OUTPUT_BUFFERS_CHANGED.
            }
        }
        drainEncoder(sink)
    }

    /** Signals end-of-stream through the chain and drains until the encoder finishes. */
    fun finish(sink: (MediaCodec.BufferInfo, ByteBuffer) -> Unit) {
        var attempts = 0
        while (true) {
            val idx = decoder.dequeueInputBuffer(Remuxer.TIMEOUT_US)
            if (idx >= 0) {
                decoder.queueInputBuffer(idx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                break
            }
            drain(sink)
            if (++attempts > 1000) break
        }
        var spins = 0
        while (!encoderDone && ++spins < 10_000) drain(sink)
    }

    /** Writes AAC buffered before muxer start (priming output) into the muxer. */
    fun flushPending(sink: (MediaCodec.BufferInfo, ByteBuffer) -> Unit) {
        for ((bi, bytes) in pending) sink(bi, ByteBuffer.wrap(bytes))
        pending.clear()
    }

    fun release() {
        try {
            decoder.stop()
        } catch (_: Exception) {
        }
        try {
            decoder.release()
        } catch (_: Exception) {
        }
        try {
            encoder?.stop()
        } catch (_: Exception) {
        }
        try {
            encoder?.release()
        } catch (_: Exception) {
        }
    }

    private fun onDecoderFormat(format: MediaFormat) {
        channels = runCatching { format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) }
            .getOrDefault(channels)
        sampleRate = runCatching { format.getInteger(MediaFormat.KEY_SAMPLE_RATE) }
            .getOrDefault(sampleRate)
        if (encoder == null) {
            val fmt = MediaFormat.createAudioFormat(
                MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, channels,
            ).apply {
                setInteger(
                    MediaFormat.KEY_AAC_PROFILE,
                    MediaCodecInfo.CodecProfileLevel.AACObjectLC,
                )
                setInteger(MediaFormat.KEY_BIT_RATE, if (channels > 2) 384_000 else 192_000)
            }
            encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC).also {
                it.configure(fmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                it.start()
            }
        }
    }

    /** Chunks a PCM buffer into encoder input buffers, spreading timestamps by bytes. */
    private fun feedEncoder(
        pcm: ByteBuffer,
        ptsUs: Long,
        sink: ((MediaCodec.BufferInfo, ByteBuffer) -> Unit)?,
    ) {
        val enc = encoder ?: return
        var offsetBytes = 0L
        var attempts = 0
        while (pcm.hasRemaining()) {
            val idx = enc.dequeueInputBuffer(Remuxer.TIMEOUT_US)
            if (idx < 0) {
                drainEncoder(sink)
                if (++attempts > 1000) throw IllegalStateException("audio encoder stalled")
                continue
            }
            val inBuf = enc.getInputBuffer(idx) ?: continue
            inBuf.clear()
            val chunk = minOf(inBuf.remaining(), pcm.remaining())
            val chunkPts =
                ptsUs + (offsetBytes * 1_000_000L) / (sampleRate.toLong() * 2 * channels)
            val savedLimit = pcm.limit()
            pcm.limit(pcm.position() + chunk)
            inBuf.put(pcm)
            pcm.limit(savedLimit)
            enc.queueInputBuffer(idx, 0, chunk, chunkPts, 0)
            offsetBytes += chunk
        }
    }

    private fun queueEncoderEos(sink: ((MediaCodec.BufferInfo, ByteBuffer) -> Unit)?) {
        val enc = encoder ?: return
        var attempts = 0
        while (true) {
            val idx = enc.dequeueInputBuffer(Remuxer.TIMEOUT_US)
            if (idx >= 0) {
                enc.queueInputBuffer(idx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                return
            }
            drainEncoder(sink)
            if (++attempts > 1000) return
        }
    }

    private fun drainEncoder(sink: ((MediaCodec.BufferInfo, ByteBuffer) -> Unit)?) {
        val enc = encoder ?: return
        loop@ while (true) {
            val idx = enc.dequeueOutputBuffer(encInfo, 0)
            when {
                idx == MediaCodec.INFO_TRY_AGAIN_LATER -> break@loop
                idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> outputFormat = enc.outputFormat
                idx >= 0 -> {
                    if (encInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                        enc.releaseOutputBuffer(idx, false)
                        continue@loop
                    }
                    if (encInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        encoderDone = true
                    }
                    if (encInfo.size > 0) {
                        val buf = enc.getOutputBuffer(idx)
                        if (buf != null) {
                            if (sink != null) {
                                sink(encInfo, buf)
                            } else {
                                val copy = ByteArray(encInfo.size)
                                buf.position(encInfo.offset)
                                buf.get(copy)
                                val bi = MediaCodec.BufferInfo()
                                bi.set(0, encInfo.size, encInfo.presentationTimeUs, encInfo.flags)
                                pending.add(bi to copy)
                            }
                        }
                    }
                    enc.releaseOutputBuffer(idx, false)
                    if (encoderDone) break@loop
                }
            }
        }
    }
}
