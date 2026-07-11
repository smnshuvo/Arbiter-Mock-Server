package auravation.arbiter.mock_server

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.util.Log

/** Video/audio codec + container info for one file, with a default [PlaybackTier] guess. */
data class CodecInfo(
    val videoCodec: String?,
    val audioCodec: String?,
    val container: String,
    val bitrate: Long,
    val playbackTier: Int,
)

/**
 * Phase T1 — reads codec/container info at scan time via [MediaExtractor] (same track-
 * iteration pattern as [Remuxer]), so the library knows each file's playback tier before
 * anyone presses play.
 *
 * The stored [CodecInfo.playbackTier] is only a *default assumption*: Tier 1 (Direct Play)
 * is assumed solely for the common h264/aac-in-mp4 case, Tier 2 (Remux) for any other
 * combination [Remuxer] can stream-copy (matches [Remuxer.VIDEO_MIMES]/[Remuxer.AUDIO_COPY_MIMES]
 * exactly, since that's what would actually run), Tier 3 (Transcode) otherwise. This is
 * deliberately conservative — e.g. a native VP9/WebM file *could* Direct Play in Chrome but
 * is classified Transcode here — because the real per-browser decision is a client-side
 * canPlayType check (task.md Phase 5, not yet built) that overrides this default anyway.
 */
object CodecDetector {
    private const val TAG = "CodecDetector"

    private val DIRECT_PLAY_CONTAINERS = setOf("mp4", "m4v")

    /** Container-agnostic short codec name for common MIME types; falls back to the MIME
     * type's subtype (e.g. "audio/ac3" -> "ac3") for anything not explicitly listed. */
    private fun shortCodecName(mime: String): String = when (mime) {
        MediaFormat.MIMETYPE_VIDEO_AVC -> "h264"
        MediaFormat.MIMETYPE_VIDEO_HEVC -> "hevc"
        "video/x-vnd.on2.vp8" -> "vp8"
        "video/x-vnd.on2.vp9" -> "vp9"
        "video/av01" -> "av1"
        MediaFormat.MIMETYPE_VIDEO_MPEG4 -> "mpeg4"
        "video/mpeg2" -> "mpeg2"
        MediaFormat.MIMETYPE_AUDIO_AAC -> "aac"
        MediaFormat.MIMETYPE_AUDIO_MPEG -> "mp3"
        "audio/ac3" -> "ac3"
        "audio/eac3" -> "eac3"
        "audio/vorbis" -> "vorbis"
        "audio/opus" -> "opus"
        "audio/flac" -> "flac"
        else -> mime.substringAfter('/')
    }

    /**
     * Reads [uri]'s first video/audio track codecs. [fileSizeBytes] and [durationMs] are
     * passed in (already known from the scanner's other metadata pass) to compute an
     * overall bitrate — per-track KEY_BIT_RATE is unreliable for MKV via MediaExtractor,
     * file-size/duration is always available and close enough for quality decisions.
     * Returns null on any failure (corrupt/DRM file — caller already wraps in try/catch).
     */
    fun detect(
        context: Context,
        uri: Uri,
        container: String,
        fileSizeBytes: Long,
        durationMs: Long,
    ): CodecInfo? {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(context, uri, null)
            var videoMime: String? = null
            var audioMime: String? = null
            for (i in 0 until extractor.trackCount) {
                val format = try {
                    extractor.getTrackFormat(i)
                } catch (e: Exception) {
                    continue
                }
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (videoMime == null && mime.startsWith("video/")) videoMime = mime
                if (audioMime == null && mime.startsWith("audio/")) audioMime = mime
            }
            if (videoMime == null && audioMime == null) return null

            val bitrate = if (durationMs > 0) {
                fileSizeBytes * 8_000 / durationMs
            } else {
                0L
            }

            val videoCodec = videoMime?.let { shortCodecName(it) }
            val audioCodec = audioMime?.let { shortCodecName(it) }
            val videoCopyable = videoMime != null && videoMime in Remuxer.VIDEO_MIMES
            val audioCopyable = audioMime == null || audioMime in Remuxer.AUDIO_COPY_MIMES
            val tier = when {
                videoCopyable && audioCopyable && container in DIRECT_PLAY_CONTAINERS ->
                    PlaybackTier.DIRECT
                videoCopyable -> PlaybackTier.REMUX
                else -> PlaybackTier.TRANSCODE
            }

            CodecInfo(videoCodec, audioCodec, container, bitrate, tier)
        } catch (e: Exception) {
            Log.w(TAG, "Codec detection failed for $uri: ${e.message}")
            null
        } finally {
            try {
                extractor.release()
            } catch (_: Exception) {
            }
        }
    }
}
