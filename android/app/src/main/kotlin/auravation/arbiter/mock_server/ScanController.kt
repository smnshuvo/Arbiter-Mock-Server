package auravation.arbiter.mock_server

import android.content.Context
import android.net.Uri
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Owns the background library-scan lifecycle: one scan at a time, on an IO coroutine,
 * with progress delivered through [progressListener]. Kept as a process-wide singleton so
 * a scan survives short-lived UI churn and can be observed from the MethodChannel.
 */
object ScanController {

    /** (processed, total, completed) — completed=true fires once at the end. */
    @Volatile
    var progressListener: ((Int, Int, Boolean) -> Unit)? = null

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var scanner: LibraryScanner? = null
    private var job: Job? = null

    fun isScanning(): Boolean = job?.isActive == true

    /** Starts a scan of [rootUri]; no-op if one is already running. */
    fun start(context: Context, rootUri: Uri) {
        if (isScanning()) return
        val db = LibraryDatabase(context.applicationContext)
        val active = LibraryScanner(context.applicationContext, db, rootUri)
        scanner = active
        job = scope.launch {
            val result = active.scan { done, total ->
                progressListener?.invoke(done, total, false)
            }
            progressListener?.invoke(result.processed, result.total, true)
        }
    }

    fun cancel() {
        scanner?.cancel()
    }
}
