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
 * Runs [VideoTranscoder] jobs one at a time (single-thread dispatcher — a hardware
 * encoder session and two concurrent jobs would fight over the same codec resources) and
 * tracks per-item status for the player's polling. Mirrors [RemuxController]'s shape
 * exactly, but is gated behind [FileServer.transcodeAllowed] since a full re-encode is
 * far more battery/thermal-costly than a stream-copy remux — the user opts in via
 * Settings (task.md Phase T4's "transcode is expensive, ask first" spirit).
 */
object TranscodeController {

    data class Status(val state: String, val pct: Int, val reason: String? = null)

    /** One finished job, newest first, for the Settings screen's transcode log. */
    data class LogEntry(
        val mediaId: Long,
        val title: String,
        val startedAt: Long,
        val finishedAt: Long,
        val outcome: String, // "ready" | "failed" | "cancelled"
        val reason: String? = null,
    )

    private const val MAX_CACHE_BYTES = 4L * 1024 * 1024 * 1024 // 4 GB
    private const val MAX_LOG_ENTRIES = 20

    private val scope = CoroutineScope(
        Executors.newSingleThreadExecutor { r ->
            Thread(r, "transcode-worker").apply { priority = Thread.MIN_PRIORITY }
        }.asCoroutineDispatcher() + SupervisorJob(),
    )
    private val statuses = ConcurrentHashMap<Long, Status>()
    private val startedAt = ConcurrentHashMap<Long, Long>()
    private val titles = ConcurrentHashMap<Long, String>()
    private val log = java.util.Collections.synchronizedList(ArrayList<LogEntry>())

    private fun addLogEntry(entry: LogEntry) {
        synchronized(log) {
            log.add(0, entry)
            while (log.size > MAX_LOG_ENTRIES) log.removeAt(log.size - 1)
        }
    }

    /** Finished jobs, newest first (bounded to the last [MAX_LOG_ENTRIES]). */
    fun recentLog(): List<LogEntry> = synchronized(log) { log.toList() }

    /** Jobs currently in progress, for a live "what's happening now" view. */
    fun ongoing(): List<Map<String, Any?>> = statuses.entries
        .filter { it.value.state == "working" }
        .map { (id, s) ->
            mapOf(
                "mediaId" to id,
                "title" to (titles[id] ?: "Unknown"),
                "pct" to s.pct,
                "startedAt" to (startedAt[id] ?: 0L),
            )
        }

    private fun cacheDir(context: Context): File =
        File(context.cacheDir, "transcode").apply { if (!exists()) mkdirs() }

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

    /** Kicks a transcode for [item]; a no-op when disallowed, already converted, or busy. */
    fun start(context: Context, item: MediaItem): Status {
        if (!FileServer.transcodeAllowed) {
            return Status("disallowed", 0, "On-device transcoding is off in Settings")
        }
        val out = outputFor(context, item)
        if (out.exists() && out.length() > 0) return Status("ready", 100)
        if (statuses[item.id]?.state == "working") return Status("working", 0)
        statuses[item.id] = Status("working", 0)
        val jobStart = System.currentTimeMillis()
        startedAt[item.id] = jobStart
        titles[item.id] = item.title

        val appContext = context.applicationContext
        scope.launch {
            val tmp = File(out.absolutePath + ".part")
            val result = VideoTranscoder.transcode(
                appContext, Uri.parse(item.filePath), tmp,
                onProgress = { pct -> statuses[item.id] = Status("working", pct) },
            )
            val finishedAt = System.currentTimeMillis()
            if (result.ok && tmp.renameTo(out)) {
                statuses.remove(item.id)
                addLogEntry(LogEntry(item.id, item.title, jobStart, finishedAt, "ready"))
                evictOverBudget(appContext, keep = out)
            } else {
                tmp.delete()
                statuses[item.id] = Status("failed", 0, result.reason)
                addLogEntry(
                    LogEntry(item.id, item.title, jobStart, finishedAt, "failed", result.reason),
                )
            }
            startedAt.remove(item.id)
            titles.remove(item.id)
        }
        return Status("working", 0)
    }

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
