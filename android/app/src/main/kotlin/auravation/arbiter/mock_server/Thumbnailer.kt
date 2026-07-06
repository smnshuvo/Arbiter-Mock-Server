package auravation.arbiter.mock_server

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
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

    /**
     * Downscales an image [input] stream to a cached JPEG thumbnail and returns its path,
     * or null on any failure. Decodes bounds first so a huge photo is sub-sampled instead of
     * fully decoded into memory. Writes via a temp file + rename so a concurrent reader never
     * sees a half-written thumbnail.
     */
    fun generateImageThumb(context: Context, sourceUri: String, input: java.io.InputStream): String? {
        return try {
            val bytes = input.readBytes()
            val bounds = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
            android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            val opts = android.graphics.BitmapFactory.Options().apply {
                inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight)
            }
            val decoded = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
                ?: return null
            val scaled = scaleDown(decoded)
            val out = cachePathFor(context, sourceUri)
            val tmp = File(out.parentFile, out.name + ".tmp")
            FileOutputStream(tmp).use { fos ->
                scaled.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, fos)
            }
            if (scaled !== decoded) scaled.recycle()
            decoded.recycle()
            if (tmp.renameTo(out)) out.absolutePath else { tmp.delete(); null }
        } catch (e: Exception) {
            Log.w(TAG, "Image thumbnail failed for $sourceUri: ${e.message}")
            null
        }
    }

    /** Largest power-of-two sub-sample that keeps the image at/above the thumbnail box. */
    private fun sampleSize(w: Int, h: Int): Int {
        if (w <= 0 || h <= 0) return 1
        var s = 1
        while (w / (s * 2) >= MAX_W && h / (s * 2) >= MAX_H) s *= 2
        return s
    }

    /** A generated seek-preview sprite sheet: [frames] tiles of [SB_W]x[SB_H] in [cols] columns. */
    data class Storyboard(val path: String, val frames: Int, val intervalMs: Long, val cols: Int)

    private const val SB_W = 160
    private const val SB_H = 90
    private const val SB_COLS = 6
    private const val SB_MAX_FRAMES = 60
    private const val SB_MIN_INTERVAL_MS = 10_000L
    private const val SB_JPEG_QUALITY = 70

    /** Deterministic sprite-sheet cache path for a source URI (does not create the file). */
    fun storyboardPathFor(context: Context, sourceUri: String): File =
        File(cacheDir(context), "${sourceUri.hashCode().toUInt()}_sb.jpg")

    /**
     * Builds a Netflix-style seek-preview sprite: one tiny frame every ~[SB_MIN_INTERVAL_MS]
     * (stretched so long videos cap at [SB_MAX_FRAMES] frames), tiled left-to-right,
     * top-to-bottom into a single JPEG. The player fetches it once and scrubs by shifting
     * the background position — no video data is touched while seeking.
     *
     * Returns null on any failure or when [isCancelled] flips mid-extraction; never throws.
     */
    fun generateStoryboard(
        context: Context,
        sourceUri: String,
        retriever: MediaMetadataRetriever,
        durationMs: Long,
        isCancelled: () -> Boolean = { false },
    ): Storyboard? {
        if (durationMs <= 0) return null
        var sheet: Bitmap? = null
        return try {
            val intervalMs = maxOf(SB_MIN_INTERVAL_MS, durationMs / SB_MAX_FRAMES)
            val frames = (durationMs / intervalMs).toInt().coerceIn(1, SB_MAX_FRAMES)
            val cols = minOf(SB_COLS, frames)
            val rows = (frames + cols - 1) / cols
            val grid = Bitmap.createBitmap(cols * SB_W, rows * SB_H, Bitmap.Config.RGB_565)
            sheet = grid
            val canvas = Canvas(grid)
            val paint = Paint(Paint.FILTER_BITMAP_FLAG)
            var drawn = 0
            for (i in 0 until frames) {
                if (isCancelled()) return null
                val frame = try {
                    retriever.getFrameAtTime(
                        i * intervalMs * 1000L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    )
                } catch (e: Exception) {
                    null
                } ?: continue
                canvas.drawBitmap(frame, null, fitCell(frame, i, cols), paint)
                frame.recycle()
                drawn++
            }
            if (drawn == 0) return null
            val out = storyboardPathFor(context, sourceUri)
            FileOutputStream(out).use { fos ->
                grid.compress(Bitmap.CompressFormat.JPEG, SB_JPEG_QUALITY, fos)
            }
            Storyboard(out.absolutePath, frames, intervalMs, cols)
        } catch (e: Exception) {
            Log.w(TAG, "Storyboard generation failed for $sourceUri: ${e.message}")
            null
        } finally {
            sheet?.recycle()
        }
    }

    /** Aspect-fit destination rect for [frame] centered in sprite cell [index]. */
    private fun fitCell(frame: Bitmap, index: Int, cols: Int): Rect {
        val cellLeft = (index % cols) * SB_W
        val cellTop = (index / cols) * SB_H
        val ratio = minOf(SB_W.toFloat() / frame.width, SB_H.toFloat() / frame.height)
        val w = (frame.width * ratio).toInt().coerceAtLeast(1)
        val h = (frame.height * ratio).toInt().coerceAtLeast(1)
        val dx = cellLeft + (SB_W - w) / 2
        val dy = cellTop + (SB_H - h) / 2
        return Rect(dx, dy, dx + w, dy + h)
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

    /** Deletes cached thumbnails/storyboards whose source path is no longer in [keepPaths]. */
    fun evictExcept(context: Context, keepPaths: Set<String>) {
        val keepFiles = keepPaths.flatMap {
            listOf(cachePathFor(context, it).name, storyboardPathFor(context, it).name)
        }.toHashSet()
        cacheDir(context).listFiles()?.forEach { f ->
            if (f.name !in keepFiles) f.delete()
        }
    }
}
