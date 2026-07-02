package auravation.arbiter.mock_server

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Bridges native file-server events (scan progress, live request count) to Dart over an
 * [EventChannel]. All emissions are marshalled to the main thread, since Flutter event
 * sinks must be invoked there. A no-op when nothing is listening.
 */
object FileServerEvents {

    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var sink: EventChannel.EventSink? = null

    fun attach(sink: EventChannel.EventSink?) {
        this.sink = sink
    }

    fun detach() {
        sink = null
    }

    /** Scan progress; [complete] is true on the final emission of a scan. */
    fun scanProgress(done: Int, total: Int, complete: Boolean) {
        send(
            mapOf(
                "type" to "scan",
                "done" to done,
                "total" to total,
                "complete" to complete,
            ),
        )
    }

    /** Running total of requests served since the server started. */
    fun requestCount(count: Int) {
        send(mapOf("type" to "requests", "count" to count))
    }

    private fun send(payload: Map<String, Any?>) {
        val current = sink ?: return
        main.post {
            try {
                current.success(payload)
            } catch (_: Exception) {
                // Sink may have been torn down between the null-check and post; ignore.
            }
        }
    }
}
