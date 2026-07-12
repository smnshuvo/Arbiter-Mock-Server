package auravation.arbiter.mock_server

import android.content.Context
import android.net.Uri
import android.util.Log
import com.antonkarpenko.ffmpegkit.FFmpegKit
import com.antonkarpenko.ffmpegkit.FFmpegKitConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/**
 * Phase T2 — live/incremental HLS session manager, replacing [VideoTranscoder]'s one-shot
 * batch approach for Tier-3 playback: instead of making the user wait for the whole file
 * to convert (28+ minutes for a long clip, worse under thermal throttling — see the
 * on-device 4K test that dropped from 0.44x to 0.244x realtime mid-job), FFmpeg produces
 * short HLS segments and the browser starts playing as soon as the first few exist while
 * encoding continues in the background.
 *
 * One active session per media item. A seek to a different offset kills the current
 * FFmpeg process and starts a fresh one at the new position — task.md's documented
 * seek-handling strategy. `-output_ts_offset` shifts the new session's segment timestamps
 * to start at the seek offset rather than zero, so the independently-served WebVTT
 * subtitles (timed in absolute source time — see [EmbeddedSubtitleExtractor]) stay in
 * sync with the `<video>` element's `currentTime` after a seek, per task.md's explicit
 * note on this ("keep the HLS timeline anchored to source timestamps").
 */
object StreamController {
    private const val TAG = "StreamController"
    private const val IDLE_TIMEOUT_MS = 30_000L
    private const val WATCHDOG_INTERVAL_MS = 10_000L

    data class Session(
        val mediaId: Long,
        val offsetSec: Int,
        val outputDir: File,
        val ffmpegSessionId: Long,
    ) {
        @Volatile var lastAccessAt: Long = System.currentTimeMillis()
    }

    private val sessions = ConcurrentHashMap<Long, Session>()
    private val scope = CoroutineScope(SupervisorJob())
    private var watchdogStarted = false
    private val dirCounter = java.util.concurrent.atomic.AtomicLong(0)

    /** Each session generation gets its own directory (mediaId + a monotonic counter),
     * never reused — a restarted (seeked) session's fresh ffmpeg process can never
     * collide with the previous generation's still-exiting one over the same files. */
    private fun sessionDir(context: Context, mediaId: Long): File =
        File(context.cacheDir, "stream/${mediaId}_${dirCounter.incrementAndGet()}")

    /** Marks [mediaId]'s session as recently used — call on every playlist/segment request
     * so the idle watchdog doesn't kill a session someone is actively watching. */
    fun touch(mediaId: Long) {
        sessions[mediaId]?.lastAccessAt = System.currentTimeMillis()
    }

    fun activeSession(mediaId: Long): Session? = sessions[mediaId]

    /**
     * Returns the session for [item] at [offsetSec], starting one if none exists or
     * restarting FFmpeg if the existing session is at a different offset (a seek).
     */
    @Synchronized
    fun startOrGetSession(context: Context, item: MediaItem, offsetSec: Int): Session {
        ensureWatchdog()
        val existing = sessions[item.id]
        if (existing != null && existing.offsetSec == offsetSec) {
            touch(item.id)
            return existing
        }
        existing?.let { killInternal(it) }

        val dir = sessionDir(context, item.id)
        dir.mkdirs()
        val safInput = FFmpegKitConfig.getSafParameterForRead(context, Uri.parse(item.filePath))
        val args = arrayOf(
            "-y",
            "-ss", offsetSec.toString(),
            "-i", safInput,
            "-map", "0:v:0",
            "-map", "0:a:0",
            "-c:v", "libvpx-vp9",
            "-deadline", "realtime",
            "-cpu-used", "8",
            "-b:v", "2M",
            "-c:a", "aac",
            "-b:a", "128k",
            "-output_ts_offset", offsetSec.toString(),
            "-f", "hls",
            "-hls_time", "6",
            "-hls_segment_type", "fmp4",
            "-hls_fmp4_init_filename", "init.mp4",
            "-hls_flags", "append_list",
            "-hls_segment_filename", File(dir, "seg%03d.m4s").absolutePath,
            File(dir, "master.m3u8").absolutePath,
        )
        // The completion callback needs to reference the Session object for the
        // conditional map removal below, but that object can't be constructed until
        // after this call returns (it needs ffSession.sessionId) — a mutable holder
        // captured by the closure bridges the ordering; the callback only ever fires
        // later, asynchronously, by which point sessionHolder[0] is always set.
        val sessionHolder = arrayOfNulls<Session>(1)
        val ffSession = FFmpegKit.executeWithArgumentsAsync(
            args,
            { s ->
                Log.i(TAG, "Stream session for media ${item.id} ended: ${s.returnCode}")
                // Cleanup lives in the completion callback (fires for natural finish AND
                // cancellation) rather than right after issuing cancel() — cancel() doesn't
                // stop the process synchronously, so deleting immediately raced its
                // still-exiting writes ("Failed to open file"/"failed to rename" seen
                // on-device). Each generation's unique directory means this can never
                // collide with a newer session started in the meantime.
                dir.deleteRecursively()
                // Conditional remove: only drops the map entry if it's still THIS
                // generation. Without this, a session that ends on its own (idle-kill,
                // natural finish, error) leaves a stale entry behind — the next request
                // for the same offset would reuse it and get "not ready" forever, since
                // no new ffmpeg process ever starts for a dead session. If a seek has
                // already installed a newer generation, this is correctly a no-op.
                sessionHolder[0]?.let { sessions.remove(item.id, it) }
            },
            null,
            null,
        )
        val session = Session(item.id, offsetSec, dir, ffSession.sessionId)
        sessionHolder[0] = session
        sessions[item.id] = session
        return session
    }

    /** Client-signaled stop (tab closed/unloaded) — kills immediately rather than waiting
     * for the idle timeout. */
    fun killSession(mediaId: Long) {
        sessions.remove(mediaId)?.let { killInternal(it) }
    }

    private fun killInternal(session: Session) {
        try {
            FFmpegKit.cancel(session.ffmpegSessionId)
        } catch (e: Exception) {
            Log.w(TAG, "Cancel failed for session ${session.ffmpegSessionId}: ${e.message}")
        }
        // Directory cleanup happens in this session's own completion callback (see
        // startOrGetSession) once ffmpeg actually stops, not here.
    }

    @Synchronized
    private fun ensureWatchdog() {
        if (watchdogStarted) return
        watchdogStarted = true
        scope.launch {
            while (true) {
                delay(WATCHDOG_INTERVAL_MS)
                val now = System.currentTimeMillis()
                val stale = sessions.values.filter { now - it.lastAccessAt > IDLE_TIMEOUT_MS }
                for (s in stale) {
                    Log.i(TAG, "Idle-killing stream session for media ${s.mediaId}")
                    killSession(s.mediaId)
                }
            }
        }
    }
}
