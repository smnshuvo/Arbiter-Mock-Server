package auravation.arbiter.mock_server

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.util.Log

/**
 * Detects embedded (in-container) subtitle tracks via [MediaExtractor] track enumeration —
 * no FFmpeg dependency. This only classifies tracks; extracting sample data into WebVTT is
 * a separate step (see the `/subs/{media_id}/{track_index}.vtt` route).
 *
 * Known limitation: the framework's Matroska/MP4 extractors reliably expose SRT
 * (`application/x-subrip`) and mov_text/tx3g tracks, but there is no public MIME constant
 * for ASS/SSA — AOSP's extractor may not vend those tracks at all. If ASS tracks turn up
 * missing on a real MKV, that confirms the gap and full extraction will need FFmpeg
 * (already anticipated in task.md's build order) rather than a MediaExtractor fix.
 */
object SubtitleTrackDetector {
    private const val TAG = "SubtitleTrackDetector"

    private val BITMAP_MIME_HINTS = listOf("pgs", "vobsub", "dvb")

    /**
     * True if [mime] looks like a text-based subtitle track we can plausibly convert to
     * WebVTT. Matches by substring (not just the documented MIMETYPE_TEXT_* constants)
     * since OEM extractor builds are inconsistent about exact strings.
     */
    private fun isTextMime(mime: String): Boolean {
        val m = mime.lowercase()
        return m == MediaFormat.MIMETYPE_TEXT_SUBRIP ||
            m == MediaFormat.MIMETYPE_TEXT_VTT ||
            m.contains("subrip") ||
            m.contains("tx3g") ||
            m.contains("3gpp-tt") ||
            m.contains("mov_text") ||
            m.contains("ssa") ||
            m.contains("ass")
    }

    private fun isBitmapMime(mime: String): Boolean {
        val m = mime.lowercase()
        return BITMAP_MIME_HINTS.any { m.contains(it) }
    }

    /**
     * Returns every subtitle track found in [uri]'s container, or an empty list on any
     * failure (corrupt/DRM/unreadable file — never throws, matching [LibraryScanner]'s
     * one-bad-file-must-not-abort-the-scan contract). [mediaId] is stamped onto each
     * result; track ids are left at 0 for the caller/DB layer to assign.
     */
    fun detect(context: Context, uri: Uri, mediaId: Long): List<SubtitleTrack> {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(context, uri, null)
            val out = ArrayList<SubtitleTrack>()
            for (i in 0 until extractor.trackCount) {
                val format = try {
                    extractor.getTrackFormat(i)
                } catch (e: Exception) {
                    continue
                }
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                val isText = isTextMime(mime)
                val isBitmap = !isText && isBitmapMime(mime)
                if (!isText && !isBitmap) continue // video/audio/unrecognized track

                val language = runCatching { format.getString(MediaFormat.KEY_LANGUAGE) }
                    .getOrNull()
                    ?.takeIf { it.isNotBlank() && it != "und" }

                out.add(
                    SubtitleTrack(
                        id = 0,
                        mediaId = mediaId,
                        trackIndex = i,
                        codec = mime,
                        language = language,
                        title = null, // MediaFormat exposes no standard track-title key
                        isText = isText,
                    ),
                )
            }
            out
        } catch (e: Exception) {
            Log.w(TAG, "Subtitle track detection failed for $uri: ${e.message}")
            emptyList()
        } finally {
            try {
                extractor.release()
            } catch (_: Exception) {
            }
        }
    }
}
