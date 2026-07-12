package auravation.arbiter.mock_server

import android.content.Context
import android.net.Uri
import android.util.Log
import com.antonkarpenko.ffmpegkit.FFmpegKit
import com.antonkarpenko.ffmpegkit.FFmpegKitConfig
import com.antonkarpenko.ffmpegkit.ReturnCode
import java.io.File

/** Outcome of a one-shot HLS conversion; [reason] is diagnostic (ffmpeg log tail) on failure. */
data class HlsConvertResult(val ok: Boolean, val reason: String? = null)

/**
 * Phase T2/T3 proof-of-concept: converts a media file to a VOD-style fMP4 HLS package
 * (init segment + media segments + playlist) via FFmpegKit.
 *
 * Encodes with `libvpx-vp9` (software) rather than a hardware encoder: FFmpeg's
 * `h264_mediacodec` wrapper hung on this device's Samsung Exynos AVC encoder
 * (`OMXNodeInstance` `UnsupportedIndex` errors, encoder never left the CONFIGURED
 * state) — confirmed independently when a direct Android `MediaCodec` call hit the
 * exact same hang, ruling out the wrapper itself as the culprit. See
 * [VideoTranscoder]'s kdoc for the full story; Safari's native HLS doesn't support
 * VP9, an accepted tradeoff for Tier-3-only content.
 *
 * This is a one-shot (batch) conversion — [convert] blocks the calling thread until the
 * whole file is encoded. It exists to prove the FFmpegKit pipeline actually works
 * on-device (task.md's suggested build order, step 5) before building the
 * live/incremental session manager (Phase T2's `/stream/{id}/...` routes, step 6) on top
 * of it. Caller is responsible for running this off the request-handling thread.
 */
object HlsConverter {
    private const val TAG = "HlsConverter"

    fun convert(context: Context, srcUri: Uri, outputDir: File): HlsConvertResult {
        outputDir.mkdirs()
        val safInput = FFmpegKitConfig.getSafParameterForRead(context, srcUri)
        val playlist = File(outputDir, "master.m3u8")
        val initSegment = File(outputDir, "init.mp4")
        val segmentPattern = File(outputDir, "seg%03d.m4s")

        val args = arrayOf(
            "-y",
            "-i", safInput,
            // Explicit stream selection: without this, ffmpeg pulls in every stream —
            // including embedded subtitle tracks (see SubtitleTrackDetector) — and the
            // HLS muxer stalls trying to also emit a webvtt output alongside the segments.
            // Subtitles are served independently via /subs; the transcode wants video+audio
            // only.
            "-map", "0:v:0",
            "-map", "0:a:0",
            "-c:v", "libvpx-vp9",
            "-deadline", "realtime",
            "-cpu-used", "8",
            "-b:v", "2M",
            "-c:a", "aac",
            "-b:a", "128k",
            "-f", "hls",
            "-hls_time", "6",
            "-hls_segment_type", "fmp4",
            "-hls_fmp4_init_filename", initSegment.name,
            "-hls_playlist_type", "vod",
            "-hls_segment_filename", segmentPattern.absolutePath,
            playlist.absolutePath,
        )

        return try {
            val session = FFmpegKit.executeWithArguments(args)
            val rc = session.returnCode
            if (rc != null && ReturnCode.isSuccess(rc) && playlist.exists()) {
                HlsConvertResult(true)
            } else {
                val reason = session.failStackTrace
                    ?: session.allLogsAsString?.takeLast(1000)
                    ?: "unknown ffmpeg failure (return code $rc)"
                Log.w(TAG, "HLS conversion failed for $srcUri: $reason")
                HlsConvertResult(false, reason)
            }
        } catch (e: Exception) {
            Log.w(TAG, "HLS conversion threw for $srcUri: ${e.message}")
            HlsConvertResult(false, e.message)
        }
    }
}
