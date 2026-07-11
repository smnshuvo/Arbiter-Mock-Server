package auravation.arbiter.mock_server

import android.content.Context
import android.media.MediaExtractor
import android.net.Uri
import android.util.Log
import java.nio.ByteBuffer
import java.util.Locale

/**
 * Extracts a single embedded text-subtitle track (as detected by [SubtitleTrackDetector])
 * into WebVTT, using only [MediaExtractor] sample reads — no FFmpeg.
 *
 * Known gap: the public MediaExtractor API exposes each subtitle sample's *start* time
 * ([MediaExtractor.getSampleTime]) but not its duration — Matroska's BlockDuration isn't
 * surfaced. So a cue's end time is inferred as the next cue's start, capped at [MAX_GAP_US]
 * so a cue doesn't visually linger across a long silent gap; the final cue falls back to
 * [TAIL_DURATION_US]. This is a heuristic, not exact — acceptable for dialogue-paced SRT,
 * documented here per task.md's "note known limitations" convention.
 */
object EmbeddedSubtitleExtractor {
    private const val TAG = "EmbeddedSubtitleExtractor"
    private const val MAX_GAP_US = 8_000_000L
    private const val TAIL_DURATION_US = 4_000_000L
    private const val READ_BUFFER_BYTES = 256 * 1024
    private const val MAX_CUES = 20_000

    private data class Cue(val startUs: Long, val text: String)

    /** Returns WebVTT text for [trackIndex] in [uri]'s container, or null on any failure. */
    fun extractToWebVtt(context: Context, uri: Uri, trackIndex: Int): String? {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(context, uri, null)
            if (trackIndex !in 0 until extractor.trackCount) return null
            extractor.selectTrack(trackIndex)

            val buffer = ByteBuffer.allocateDirect(READ_BUFFER_BYTES)
            val cues = ArrayList<Cue>()
            while (cues.size < MAX_CUES) {
                buffer.clear()
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                val startUs = extractor.sampleTime
                val bytes = ByteArray(size)
                buffer.position(0)
                buffer.get(bytes, 0, size)
                // Matroska text samples are often CRLF-terminated internally (not just at
                // the ends), which trim() alone doesn't reach — a stray \r before each \n
                // renders as a visible glyph in the browser. Normalize before trimming.
                // SubtitleEncoding falls back off strict UTF-8 for non-compliant muxers.
                val text = SubtitleEncoding.decode(bytes)
                    .replace("\r\n", "\n")
                    .replace('\r', '\n')
                    .trim()
                if (text.isNotEmpty()) cues.add(Cue(startUs, text))
                extractor.advance()
            }
            if (cues.isEmpty()) return null
            buildWebVtt(cues)
        } catch (e: Exception) {
            Log.w(TAG, "Extraction failed for $uri track $trackIndex: ${e.message}")
            null
        } finally {
            try {
                extractor.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun buildWebVtt(cues: List<Cue>): String {
        val sb = StringBuilder("WEBVTT\n\n")
        for (i in cues.indices) {
            val cue = cues[i]
            val nextStart = cues.getOrNull(i + 1)?.startUs
            val endUs = when {
                nextStart == null -> cue.startUs + TAIL_DURATION_US
                nextStart - cue.startUs <= MAX_GAP_US -> nextStart
                else -> cue.startUs + MAX_GAP_US
            }
            sb.append(vttTimestamp(cue.startUs)).append(" --> ")
                .append(vttTimestamp(endUs)).append('\n')
                .append(cue.text).append("\n\n")
        }
        return sb.toString()
    }

    private fun vttTimestamp(us: Long): String {
        val totalMs = us / 1000
        val h = totalMs / 3_600_000
        val m = (totalMs % 3_600_000) / 60_000
        val s = (totalMs % 60_000) / 1000
        val ms = totalMs % 1000
        return String.format(Locale.ROOT, "%02d:%02d:%02d.%03d", h, m, s, ms)
    }
}
