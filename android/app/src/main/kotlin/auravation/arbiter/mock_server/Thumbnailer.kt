package auravation.arbiter.mock_server

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.util.Log
import java.io.File
import java.io.FileOutputStream

/**
 * Generates and caches JPEG thumbnails for scanned video files.
 *
 * Frames are grabbed at 10% of the video duration (avoids black opening frames),
 * scaled down to fit within [MAX_W]x[MAX_H], compressed at [JPEG_QUALITY], and written
 * to the app's private cache under a filename derived from the source URI's hash.
 * Extraction failures never propagate — the caller falls back to a placeholder.
 */
object Thumbnailer {

    private const val TAG = "Thumbnailer"
    private const val MAX_W = 320
    private const val MAX_H = 180
    private const val JPEG_QUALITY = 85

    private fun cacheDir(context: Context): File =
        File(context.cacheDir, "media_thumbs").apply { if (!exists()) mkdirs() }

    /** Deterministic cache path for a given source URI (does not create the file). */
    fun cachePathFor(context: Context, sourceUri: String): File =
        File(cacheDir(context), "${sourceUri.hashCode().toUInt()}.jpg")

    /**
     * Extracts a thumbnail from an already-opened [retriever] and writes it to cache.
     * Returns the absolute path, or null on any failure. Reuses [retriever] so the
     * scanner opens the file only once for both metadata and thumbnail.
     */
    fun generate(context: Context, sourceUri: String, retriever: MediaMetadataRetriever): String? {
        return try {
            val out = cachePathFor(context, sourceUri)
            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            val timeUs = if (durationMs > 0) durationMs * 1000L / 10 else 0L // 10% in

            val frame: Bitmap = retriever.getFrameAtTime(
                timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
            ) ?: return null

            val scaled = scaleDown(frame)
            FileOutputStream(out).use { fos ->
                scaled.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, fos)
            }
            if (scaled !== frame) scaled.recycle()
            frame.recycle()
            out.absolutePath
        } catch (e: Exception) {
            Log.w(TAG, "Thumbnail generation failed for $sourceUri: ${e.message}")
            null
        }
    }

    private fun scaleDown(src: Bitmap): Bitmap {
        val w = src.width
        val h = src.height
        if (w <= MAX_W && h <= MAX_H) return src
        val ratio = minOf(MAX_W.toFloat() / w, MAX_H.toFloat() / h)
        val nw = (w * ratio).toInt().coerceAtLeast(1)
        val nh = (h * ratio).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, nw, nh, true)
    }

    /** Deletes cached thumbnails whose source path is no longer in [keepPaths]. */
    fun evictExcept(context: Context, keepPaths: Set<String>) {
        val keepFiles = keepPaths.map { cachePathFor(context, it).name }.toHashSet()
        cacheDir(context).listFiles()?.forEach { f ->
            if (f.name !in keepFiles) f.delete()
        }
    }
}
