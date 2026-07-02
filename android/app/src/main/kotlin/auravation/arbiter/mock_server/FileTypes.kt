package auravation.arbiter.mock_server

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Extension-driven helpers for the file server: MIME types, display icons, and
 * human-readable size/date formatting. Kept separate from [FileServer] so the
 * routing logic stays readable.
 */
object FileTypes {

    /** MIME types the browser <video>/<audio> element can potentially play. */
    private val PLAYABLE_MIME_PREFIXES = listOf("video/", "audio/")

    private val MIME_BY_EXT = mapOf(
        // video
        "mp4" to "video/mp4", "m4v" to "video/mp4", "webm" to "video/webm",
        "ogv" to "video/ogg", "mov" to "video/quicktime", "mkv" to "video/x-matroska",
        "avi" to "video/x-msvideo", "3gp" to "video/3gpp", "flv" to "video/x-flv",
        "ts" to "video/mp2t", "m2ts" to "video/mp2t", "mts" to "video/mp2t",
        // audio
        "mp3" to "audio/mpeg", "m4a" to "audio/mp4", "aac" to "audio/aac",
        "ogg" to "audio/ogg", "oga" to "audio/ogg", "wav" to "audio/wav",
        "flac" to "audio/flac", "opus" to "audio/opus",
        // images
        "jpg" to "image/jpeg", "jpeg" to "image/jpeg", "png" to "image/png",
        "gif" to "image/gif", "webp" to "image/webp", "bmp" to "image/bmp",
        "svg" to "image/svg+xml", "heic" to "image/heic",
        // documents / text
        "pdf" to "application/pdf", "txt" to "text/plain", "md" to "text/markdown",
        "json" to "application/json", "xml" to "application/xml",
        "html" to "text/html", "htm" to "text/html", "csv" to "text/csv",
        "srt" to "application/x-subrip", "vtt" to "text/vtt",
        "zip" to "application/zip", "apk" to "application/vnd.android.package-archive",
    )

    fun extensionOf(name: String): String =
        name.substringAfterLast('.', "").lowercase(Locale.ROOT)

    fun mimeFor(name: String): String =
        MIME_BY_EXT[extensionOf(name)] ?: "application/octet-stream"

    /** True if the file is a video/audio type worth surfacing a Play button for. */
    fun isPlayable(name: String): Boolean {
        val mime = mimeFor(name)
        return PLAYABLE_MIME_PREFIXES.any { mime.startsWith(it) }
    }

    fun isVideo(name: String): Boolean = mimeFor(name).startsWith("video/")

    fun isImage(name: String): Boolean = mimeFor(name).startsWith("image/")

    /**
     * True if the file renders directly in a browser tab (image, PDF, or text), so a
     * "View" action can just open the raw bytes inline instead of the media player.
     */
    fun isViewableInline(name: String): Boolean {
        val mime = mimeFor(name)
        return mime.startsWith("image/") ||
            mime.startsWith("text/") ||
            mime == "application/pdf" ||
            mime == "application/json" ||
            mime == "application/xml"
    }

    fun iconFor(name: String, isDirectory: Boolean): String {
        if (isDirectory) return "📁" // 📁
        return when (extensionOf(name)) {
            "mp4", "m4v", "webm", "ogv", "mov", "mkv", "avi", "3gp", "flv",
            "ts", "m2ts", "mts" -> "🎬" // 🎬
            "mp3", "m4a", "aac", "ogg", "oga", "wav", "flac", "opus" -> "🎵" // 🎵
            "jpg", "jpeg", "png", "gif", "webp", "bmp", "svg", "heic" -> "🖼️" // 🖼️
            "pdf" -> "📕" // 📕
            "txt", "md", "json", "xml", "html", "htm", "csv" -> "📄" // 📄
            "zip", "apk" -> "📦" // 📦
            else -> "📄" // 📄
        }
    }

    fun humanSize(bytes: Long): String {
        if (bytes < 0) return "—"
        if (bytes < 1024) return "$bytes B"
        val units = listOf("KB", "MB", "GB", "TB")
        var value = bytes.toDouble() / 1024
        var i = 0
        while (value >= 1024 && i < units.size - 1) {
            value /= 1024
            i++
        }
        return String.format(Locale.ROOT, "%.1f %s", value, units[i])
    }

    fun formatDate(millis: Long): String {
        if (millis <= 0) return "—"
        return SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.ROOT).format(Date(millis))
    }
}
