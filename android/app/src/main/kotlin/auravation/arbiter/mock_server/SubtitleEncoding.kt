package auravation.arbiter.mock_server

import java.nio.ByteBuffer
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction

/**
 * Decodes subtitle bytes as UTF-8 when they're actually valid UTF-8, falling back to
 * Windows-1252 otherwise. Neither the Matroska spec (S_TEXT/UTF8 embedded tracks) nor
 * sidecar .srt files reliably honor UTF-8 in practice — many fansub/mux tools write
 * Windows-1252 (curly quotes, em dashes, single-byte ellipsis) while still declaring
 * UTF-8. Decoding those bytes as UTF-8 doesn't throw for *most* text but silently turns
 * the non-ASCII bytes into U+FFFD (the visible "?" glyph the player showed). Windows-1252
 * is a single-byte encoding that maps every byte value, so it's a safe universal fallback
 * for the common case; it won't be correct for other regional encodings, but those are
 * rarer in practice than the UTF-8/Windows-1252 split task.md's T0.2 anticipated.
 */
object SubtitleEncoding {
    private val WINDOWS_1252: Charset = Charset.forName("windows-1252")

    fun decode(bytes: ByteArray): String {
        val strictDecoder = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        return try {
            strictDecoder.decode(ByteBuffer.wrap(bytes)).toString()
        } catch (e: Exception) {
            String(bytes, WINDOWS_1252)
        }
    }
}
