package auravation.arbiter.mock_server

import android.content.Context
import android.net.Uri
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.launch
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Runs [Remuxer] jobs one at a time (single-thread dispatcher — remuxing is IO-bound and
 * two concurrent jobs would just thrash the disk) and tracks per-item status for the
 * player's polling. Outputs live in cache/remux with the source mtime baked into the
 * filename, so an edited source automatically misses the cache; the folder is LRU-capped.
 */
object RemuxController {

    data class Status(val state: String, val pct: Int, val reason: String? = null)

    private const val MAX_CACHE_BYTES = 4L * 1024 * 1024 * 1024 // 4 GB

    private val scope = CoroutineScope(
        // Lowest priority: a conversion must never starve the HTTP threads that are
        // actively streaming to the browser (they share the phone's disk and CPU).
        Executors.newSingleThreadExecutor { r ->
            Thread(r, "remux-worker").apply { priority = Thread.MIN_PRIORITY }
        }.asCoroutineDispatcher() + SupervisorJob(),
    )
    private val statuses = ConcurrentHashMap<Long, Status>()

    private fun cacheDir(context: Context): File =
        File(context.cacheDir, "remux").apply { if (!exists()) mkdirs() }

    /** Deterministic output path; mtime in the name invalidates stale conversions. */
    fun outputFor(context: Context, item: MediaItem): File = File(
        cacheDir(context),
        "${item.filePath.hashCode().toUInt()}_${item.lastModified}.mp4",
    )

    fun status(context: Context, item: MediaItem): Status {
        statuses[item.id]?.let { s -> if (s.state == "working" || s.state == "failed") return s }
        val out = outputFor(context, item)
        return if (out.exists() && out.length() > 0) Status("ready", 100) else Status("none", 0)
    }

    /** Kicks a remux for [item]; a no-op when already converted or in progress. */
    fun start(context: Context, item: MediaItem) {
        val out = outputFor(context, item)
        if (out.exists() && out.length() > 0) return
        if (statuses[item.id]?.state == "working") return
        // A previous "failed" is retried deliberately: unsupported files fail again
        // within milliseconds (track scan only), so the retry is cheap.
        statuses[item.id] = Status("working", 0)

        val appContext = context.applicationContext
        scope.launch {
            val tmp = File(out.absolutePath + ".part")
            val result = Remuxer.remux(
                appContext, Uri.parse(item.filePath), tmp,
                onProgress = { pct -> statuses[item.id] = Status("working", pct) },
            )
            if (result.ok && tmp.renameTo(out)) {
                statuses.remove(item.id) // status() now reports "ready" from the file
                evictOverBudget(appContext, keep = out)
            } else {
                tmp.delete()
                statuses[item.id] = Status("failed", 0, result.reason)
            }
        }
    }

    /** Deletes oldest conversions (never [keep]) until the folder fits the budget. */
    private fun evictOverBudget(context: Context, keep: File) {
        val files = cacheDir(context)
            .listFiles()?.filter { it.name.endsWith(".mp4") } ?: return
        var total = files.sumOf { it.length() }
        if (total <= MAX_CACHE_BYTES) return
        for (f in files.sortedBy { it.lastModified() }) {
            if (f.absolutePath == keep.absolutePath) continue
            total -= f.length()
            f.delete()
            if (total <= MAX_CACHE_BYTES) break
        }
    }
}
