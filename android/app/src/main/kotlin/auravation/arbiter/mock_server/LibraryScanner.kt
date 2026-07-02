package auravation.arbiter.mock_server

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Log
import androidx.documentfile.provider.DocumentFile

/** Outcome of a scan pass. */
data class ScanResult(val processed: Int, val total: Int, val cancelled: Boolean)

/**
 * Walks the shared SAF folder and builds/refreshes the [LibraryDatabase] of media items.
 *
 * Design constraints from the plan:
 *  - Runs off the main thread (caller supplies the thread/coroutine).
 *  - Incremental: files whose last-modified is unchanged are skipped.
 *  - Robust: a single corrupt/DRM file must never crash the whole scan — every file is
 *    wrapped in try/catch and, worst case, stored with filename-only metadata.
 *  - Cancellable: [cancel] flips a flag checked between files.
 */
class LibraryScanner(
    private val context: Context,
    private val db: LibraryDatabase,
    private val rootUri: Uri,
) {

    companion object {
        private const val TAG = "LibraryScanner"
    }

    @Volatile
    private var cancelled = false

    fun cancel() {
        cancelled = true
    }

    /**
     * Runs a full incremental scan. [onProgress] is invoked as (done, total) after each
     * file. Safe to call on a background thread only.
     */
    fun scan(onProgress: (Int, Int) -> Unit): ScanResult {
        cancelled = false
        val root = DocumentFile.fromTreeUri(context, rootUri)
        if (root == null || !root.isDirectory) {
            return ScanResult(0, 0, false)
        }

        val mediaFiles = ArrayList<DocumentFile>()
        collectMedia(root, mediaFiles)
        val total = mediaFiles.size

        // Prune rows for files that no longer exist.
        val currentPaths = mediaFiles.map { it.uri.toString() }.toHashSet()
        for (path in db.allPaths()) {
            if (path !in currentPaths) db.deleteByPath(path)
        }

        var processed = 0
        for (file in mediaFiles) {
            if (cancelled) break
            try {
                processFile(file)
            } catch (e: Exception) {
                // Never let one bad file abort the scan.
                Log.w(TAG, "Skipping ${file.name}: ${e.message}")
            }
            processed++
            onProgress(processed, total)
        }

        // Drop orphaned thumbnails for files removed since last scan.
        try {
            Thumbnailer.evictExcept(context, db.allPaths())
        } catch (e: Exception) {
            Log.w(TAG, "Thumbnail eviction failed: ${e.message}")
        }

        return ScanResult(processed, total, cancelled)
    }

    /** Depth-first collection of video/audio files under [dir]. */
    private fun collectMedia(dir: DocumentFile, out: MutableList<DocumentFile>) {
        if (cancelled) return
        for (child in dir.listFiles()) {
            when {
                child.isDirectory -> collectMedia(child, out)
                child.isFile -> {
                    val name = child.name ?: continue
                    if (FileTypes.isPlayable(name)) out.add(child)
                }
            }
        }
    }

    private fun processFile(file: DocumentFile) {
        val path = file.uri.toString()
        val lastModified = file.lastModified()

        val name = file.name ?: "Unknown"
        val isVideo = FileTypes.isVideo(name)

        // Incremental: unchanged files are left as-is, except videos indexed before
        // storyboards existed — those get their seek-preview sprite backfilled.
        if (db.lastModifiedFor(path) == lastModified) {
            if (isVideo) backfillStoryboard(path, file)
            return
        }

        var title = name.substringBeforeLast('.', name)
        var duration = 0L
        var width = 0
        var height = 0
        var mime = FileTypes.mimeFor(name)
        var thumbPath: String? = null
        var storyboard: Thumbnailer.Storyboard? = null

        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(context, file.uri)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()?.let { duration = it }
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull()?.let { width = it }
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull()?.let { height = it }
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)
                ?.takeIf { it.isNotBlank() }?.let { title = it }
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE)
                ?.takeIf { it.isNotBlank() }?.let { mime = it }

            if (isVideo) {
                thumbPath = Thumbnailer.generate(context, path, retriever)
                storyboard = Thumbnailer.generateStoryboard(
                    context, path, retriever, duration,
                ) { cancelled }
            }
        } catch (e: Exception) {
            // Corrupt/DRM/unsupported: keep the row with filename-only metadata.
            Log.w(TAG, "Metadata extraction failed for $name: ${e.message}")
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }

        db.upsert(
            MediaItem(
                id = 0,
                filePath = path,
                title = title,
                durationMs = duration,
                width = width,
                height = height,
                mimeType = mime,
                thumbnailPath = thumbPath,
                lastModified = lastModified,
                addedAt = System.currentTimeMillis(),
                storyboardPath = storyboard?.path,
                storyboardFrames = storyboard?.frames ?: 0,
                storyboardIntervalMs = storyboard?.intervalMs ?: 0,
                storyboardCols = storyboard?.cols ?: 0,
            ),
        )
    }

    /** Generates the seek-preview sprite for a row scanned before storyboards existed. */
    private fun backfillStoryboard(path: String, file: DocumentFile) {
        val row = db.getByPath(path) ?: return
        val existing = row.storyboardPath
        if (!existing.isNullOrEmpty() && java.io.File(existing).exists()) return
        if (row.durationMs <= 0) return // metadata never extracted; nothing to preview

        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(context, file.uri)
            val sb = Thumbnailer.generateStoryboard(
                context, path, retriever, row.durationMs,
            ) { cancelled }
            if (sb != null) db.updateStoryboard(row.id, sb.path, sb.frames, sb.intervalMs, sb.cols)
        } catch (e: Exception) {
            Log.w(TAG, "Storyboard backfill failed for ${row.title}: ${e.message}")
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }
}
