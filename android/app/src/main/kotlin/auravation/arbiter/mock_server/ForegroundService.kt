package auravation.arbiter.mock_server

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Foreground-service notification that doubles as the Android "Live Activity".
 *
 * Renders the Arbiter design with fully custom RemoteViews (dark card): collapsed
 * shows the last endpoint + status code; expanded shows the live request feed with
 * Pause / Stop / Logs; a held request or response flips it to a Continue / Edit /
 * Drop call-to-action. Dart pushes state in over the method channel; the action
 * buttons broadcast back to [MainActivity], which forwards them to Flutter.
 */
class ForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "mock_server_channel"
        private const val NOTIFICATION_ID = 1001
        private const val MAX_ROWS = 4

        const val ACTION_STOP_SERVER_BROADCAST = "auravation.arbiter.mock_server.ACTION_STOP_SERVER"
        const val ACTION_CONTINUE = "auravation.arbiter.mock_server.ACTION_CONTINUE"
        const val ACTION_DROP = "auravation.arbiter.mock_server.ACTION_DROP"
        const val ACTION_EDIT = "auravation.arbiter.mock_server.ACTION_EDIT"
        const val ACTION_OPEN_LOGS = "auravation.arbiter.mock_server.ACTION_OPEN_LOGS"
        const val EXTRA_INTERCEPT_ID = "intercept_id"

        private const val ACTION_PAUSE_FEED = "auravation.arbiter.mock_server.ACTION_PAUSE_FEED"

        /** Live instance, used to route channel updates to the running notification. */
        var instance: ForegroundService? = null
            private set

        fun startService(context: Context) {
            val intent = Intent(context, ForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopService(context: Context) {
            context.stopService(Intent(context, ForegroundService::class.java))
        }
    }

    private data class LogEntry(val method: String, val path: String, val statusCode: Int)
    private data class Intercept(
        val id: String,
        val isResponse: Boolean,
        val method: String,
        val url: String,
        val statusCode: Int?,
        val body: String?,
        val heldBase: Long,
    )

    private var address: String = "localhost"
    private var port: Int = 0
    private var totalReqs: Int = 0
    private var errorCount: Int = 0
    private var feedPaused: Boolean = false
    private val recentLogs = ArrayDeque<LogEntry>()
    private var intercept: Intercept? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_PAUSE_FEED) {
            feedPaused = !feedPaused
            refresh()
            return START_STICKY
        }
        startForeground(NOTIFICATION_ID, buildNotification())
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIFICATION_ID)
    }

    // ── Update API (invoked from MainActivity's channel handler) ───────────────

    fun setServerStatus(address: String, port: Int) {
        this.address = address
        this.port = port
        refresh()
    }

    fun pushLog(method: String, path: String, statusCode: Int) {
        totalReqs++
        if (statusCode >= 400) errorCount++
        if (!feedPaused) {
            recentLogs.addFirst(LogEntry(method, path, statusCode))
            while (recentLogs.size > MAX_ROWS) recentLogs.removeLast()
        }
        refresh()
    }

    fun setIntercepted(id: String, isResponse: Boolean, method: String, url: String, statusCode: Int?, body: String?) {
        intercept = Intercept(id, isResponse, method, url, statusCode, body, SystemClock.elapsedRealtime())
        refresh()
    }

    fun clearIntercepted() {
        intercept = null
        refresh()
    }

    private fun refresh() {
        if (instance == null) return
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIFICATION_ID, buildNotification())
    }

    // ── Notification building ──────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Mock Server Service",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Live activity for the Arbiter mock server"
                setShowBadge(false)
            }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_arbiter)
            .setColor(ContextCompat.getColor(this, R.color.ar_accent_blue))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openAppIntent(null, null))

        val held = intercept
        if (held != null) {
            val view = buildInterceptedView(held)
            builder.setCustomContentView(view).setCustomBigContentView(view)
        } else {
            builder.setCustomContentView(buildCollapsedView())
                .setCustomBigContentView(buildExpandedView())
        }
        return builder.build()
    }

    private fun buildCollapsedView(): RemoteViews {
        val rv = RemoteViews(packageName, R.layout.notif_collapsed)
        val last = recentLogs.firstOrNull()
        if (last != null) {
            rv.setTextViewText(R.id.collapsed_method, last.method)
            rv.setTextColor(R.id.collapsed_method, methodColor(last.method))
            rv.setTextViewText(R.id.collapsed_path, last.path)
            rv.setTextViewText(R.id.collapsed_status, last.statusCode.toString())
            rv.setTextColor(R.id.collapsed_status, statusColor(last.statusCode))
        } else {
            rv.setTextViewText(R.id.collapsed_method, "")
            rv.setTextViewText(R.id.collapsed_path, "Waiting for requests…")
            rv.setTextViewText(R.id.collapsed_status, "")
        }
        rv.setTextViewText(R.id.collapsed_sub, "Server running · $endpoint")
        return rv
    }

    private fun buildExpandedView(): RemoteViews {
        val rv = RemoteViews(packageName, R.layout.notif_expanded)
        rv.setTextViewText(R.id.exp_sub, "$endpoint · $totalReqs reqs · $errorCount errors")

        val rowIds = intArrayOf(R.id.row0, R.id.row1, R.id.row2, R.id.row3)
        val methodIds = intArrayOf(R.id.row0_method, R.id.row1_method, R.id.row2_method, R.id.row3_method)
        val pathIds = intArrayOf(R.id.row0_path, R.id.row1_path, R.id.row2_path, R.id.row3_path)
        val statusIds = intArrayOf(R.id.row0_status, R.id.row1_status, R.id.row2_status, R.id.row3_status)

        val logs = recentLogs.toList()
        for (i in 0 until MAX_ROWS) {
            if (i < logs.size) {
                val log = logs[i]
                rv.setViewVisibility(rowIds[i], View.VISIBLE)
                rv.setTextViewText(methodIds[i], log.method)
                rv.setTextColor(methodIds[i], methodColor(log.method))
                rv.setTextViewText(pathIds[i], log.path)
                rv.setTextViewText(statusIds[i], log.statusCode.toString())
                rv.setTextColor(statusIds[i], statusColor(log.statusCode))
            } else {
                rv.setViewVisibility(rowIds[i], View.GONE)
            }
        }

        rv.setTextViewText(R.id.action_pause, if (feedPaused) "RESUME" else "PAUSE")
        rv.setOnClickPendingIntent(R.id.action_pause, serviceIntent(ACTION_PAUSE_FEED, 20))
        rv.setOnClickPendingIntent(R.id.action_stop, broadcastIntent(ACTION_STOP_SERVER_BROADCAST, 21, null))
        rv.setOnClickPendingIntent(R.id.action_logs, openAppIntent(ACTION_OPEN_LOGS, null))
        return rv
    }

    private fun buildInterceptedView(held: Intercept): RemoteViews {
        val rv = RemoteViews(packageName, R.layout.notif_intercepted)
        val accent = ContextCompat.getColor(this, if (held.isResponse) R.color.ar_blue else R.color.ar_amber)

        rv.setInt(R.id.int_accent, "setBackgroundColor", accent)
        rv.setTextColor(R.id.int_dot, accent)
        rv.setTextColor(R.id.int_title, accent)
        rv.setTextViewText(R.id.int_title, if (held.isResponse) "Response intercepted" else "Request intercepted")
        rv.setTextViewText(
            R.id.int_sub,
            if (held.isResponse) "A response is held before delivery." else "An outbound request is being held.",
        )
        rv.setChronometer(R.id.int_timer, held.heldBase, "held %s", true)

        rv.setTextViewText(R.id.int_method, held.method)
        rv.setTextColor(R.id.int_method, methodColor(held.method))
        rv.setTextViewText(R.id.int_path, held.url)

        if (held.statusCode != null) {
            rv.setViewVisibility(R.id.int_status, View.VISIBLE)
            rv.setTextViewText(R.id.int_status, held.statusCode.toString())
            rv.setTextColor(R.id.int_status, statusColor(held.statusCode))
        } else {
            rv.setViewVisibility(R.id.int_status, View.GONE)
        }

        if (!held.body.isNullOrBlank()) {
            rv.setViewVisibility(R.id.int_body, View.VISIBLE)
            rv.setTextViewText(R.id.int_body, held.body)
        } else {
            rv.setViewVisibility(R.id.int_body, View.GONE)
        }

        rv.setTextViewText(R.id.int_edit, if (held.isResponse) "Edit body" else "Edit")
        rv.setOnClickPendingIntent(R.id.int_continue, broadcastIntent(ACTION_CONTINUE, 10, held.id))
        rv.setOnClickPendingIntent(R.id.int_edit, openAppIntent(ACTION_EDIT, held.id))
        rv.setOnClickPendingIntent(R.id.int_drop, broadcastIntent(ACTION_DROP, 12, held.id))
        return rv
    }

    private val endpoint: String get() = if (port > 0) "$address:$port" else address

    // ── PendingIntent helpers ──────────────────────────────────────────────────

    private val piFlags: Int
        get() = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT

    private fun broadcastIntent(action: String, requestCode: Int, interceptId: String?): PendingIntent {
        val intent = Intent(action).setPackage(packageName)
        if (interceptId != null) intent.putExtra(EXTRA_INTERCEPT_ID, interceptId)
        return PendingIntent.getBroadcast(this, requestCode, intent, piFlags)
    }

    private fun serviceIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, ForegroundService::class.java).setAction(action)
        return PendingIntent.getService(this, requestCode, intent, piFlags)
    }

    /** Opens (foregrounds) the app, optionally carrying a notification action to run. */
    private fun openAppIntent(naAction: String?, interceptId: String?): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (naAction != null) action = naAction
            if (interceptId != null) putExtra(EXTRA_INTERCEPT_ID, interceptId)
        }
        // Distinct request code per action so extras are not collapsed.
        val rc = when (naAction) {
            ACTION_OPEN_LOGS -> 30
            ACTION_EDIT -> 31
            else -> 0
        }
        return PendingIntent.getActivity(this, rc, intent, piFlags)
    }

    private fun methodColor(method: String): Int = ContextCompat.getColor(
        this,
        when (method.uppercase()) {
            "GET", "HEAD", "OPTIONS" -> R.color.ar_blue
            "POST" -> R.color.ar_green
            "PUT", "PATCH" -> R.color.ar_amber
            "DELETE", "DEL" -> R.color.ar_red
            else -> R.color.ar_text
        },
    )

    private fun statusColor(code: Int): Int = ContextCompat.getColor(
        this,
        when {
            code in 200..299 -> R.color.ar_green
            code in 300..399 -> R.color.ar_amber
            code >= 400 -> R.color.ar_red
            else -> R.color.ar_text
        },
    )
}
