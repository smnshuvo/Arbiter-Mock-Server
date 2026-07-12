package auravation.arbiter.mock_server

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.util.Log
import com.antonkarpenko.ffmpegkit.FFmpegKit
import com.antonkarpenko.ffmpegkit.FFmpegKitConfig
import com.antonkarpenko.ffmpegkit.FFmpegSession
import com.antonkarpenko.ffmpegkit.ReturnCode
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Outcome of a full Tier-3 transcode; [reason] is a user-presentable failure summary. */
data class TranscodeResult(val ok: Boolean, val reason: String? = null)

/**
 * Phase T3 — full transcode for files whose video codec itself is unsupported (Tier 3:
 * HEVC on an old device, VP9-in-MKV, MPEG4/Xvid, etc.).
 *
 * Encodes with FFmpeg's `libvpx-vp9` — pure CPU software encoding — rather than a
 * hardware encoder. Two independent hardware-encoder paths were tried and abandoned
 * first: FFmpeg's own `h264_mediacodec` wrapper, and Android's `MediaCodec` H.264
 * encoder called directly. Both hung on this device's Samsung Exynos AVC encoder
 * (`OMXNodeInstance` `UnsupportedIndex` errors; encoder never left the CONFIGURED
 * state). Software VP9 sidesteps the vendor hardware encoder entirely.
 *
 * Accepted tradeoff: Safari's native HLS/`<video>` doesn't support VP9, so files
 * transcoded here won't play in Safari specifically — Direct Play and Remux (Tiers 1-2,
 * which stay H.264) are unaffected. Audio uses FFmpeg's own built-in `aac` encoder
 * (already proven working — it succeeded even in the earlier abandoned attempts, only
 * the video encoder was ever the problem).
 */
object VideoTranscoder {
    private const val TAG = "VideoTranscoder"

    fun transcode(
        context: Context,
        srcUri: Uri,
        outFile: File,
        onProgress: (Int) -> Unit = {},
        isCancelled: () -> Boolean = { false },
    ): TranscodeResult {
        outFile.parentFile?.mkdirs()
        val safInput = FFmpegKitConfig.getSafParameterForRead(context, srcUri)
        val durationMs = probeDurationMs(context, srcUri)

        val args = arrayOf(
            "-y", "-i", safInput,
            "-map", "0:v:0",
            "-map", "0:a:0",
            "-c:v", "libvpx-vp9",
            "-deadline", "realtime",
            "-cpu-used", "8",
            "-b:v", "2M",
            "-c:a", "aac",
            "-b:a", "128k",
            "-f", "mp4",
            outFile.absolutePath,
        )

        val latch = CountDownLatch(1)
        var finalSession: FFmpegSession? = null
        val session = FFmpegKit.executeWithArgumentsAsync(
            args,
            { s -> finalSession = s; latch.countDown() },
            null,
        ) { stats ->
            if (durationMs > 0) {
                val pct = ((stats.time * 100L) / durationMs).toInt().coerceIn(0, 99)
                onProgress(pct)
            }
        }

        while (!latch.await(500, TimeUnit.MILLISECONDS)) {
            if (isCancelled()) {
                FFmpegKit.cancel(session.sessionId)
                latch.await(5, TimeUnit.SECONDS)
                outFile.delete()
                return TranscodeResult(false, "cancelled")
            }
        }

        val rc = finalSession?.returnCode
        return if (rc != null && ReturnCode.isSuccess(rc) && outFile.exists() && outFile.length() > 0) {
            onProgress(100)
            TranscodeResult(true)
        } else {
            outFile.delete()
            val reason = finalSession?.failStackTrace
                ?: finalSession?.allLogsAsString?.takeLast(1000)
                ?: "unknown ffmpeg failure (return code $rc)"
            Log.w(TAG, "Transcode failed for $srcUri: $reason")
            TranscodeResult(false, reason)
        }
    }

    /** Reads duration from the container for progress percentage — works even though the
     * codec itself can't be decoded, since demuxing only needs to parse the container. */
    private fun probeDurationMs(context: Context, srcUri: Uri): Long {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(context, srcUri, null)
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("video/")) continue
                val durationUs = runCatching { format.getLong(MediaFormat.KEY_DURATION) }
                    .getOrDefault(0L)
                return durationUs / 1000
            }
            0L
        } catch (e: Exception) {
            0L
        } finally {
            try {
                extractor.release()
            } catch (_: Exception) {
            }
        }
    }
}
