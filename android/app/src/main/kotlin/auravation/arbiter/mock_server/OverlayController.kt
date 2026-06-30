package auravation.arbiter.mock_server

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.Animation
import android.view.animation.TranslateAnimation
import android.widget.Chronometer
import android.widget.Switch
import android.widget.TextView
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

/**
 * Draggable, system-wide floating overlay ("chat-head" style) for the Arbiter
 * live activity. Process-scoped so it survives the Activity lifecycle while the
 * foreground service keeps the process alive.
 *
 * Collapsed it is a small draggable bubble (last endpoint + status); tapping it
 * expands to the live request feed; a held request/response flips it to a
 * Continue / Edit / Drop call-to-action. Dart pushes state over a MethodChannel;
 * the action views call back into Flutter through the same channel.
 */
object OverlayController {

    private data class LogEntry(val method: String, val path: String, val statusCode: Int, val responseTimeMs: Int)
    private data class Intercept(
        val id: String,
        val isResponse: Boolean,
        val method: String,
        val url: String,
        val statusCode: Int?,
        val body: String?,
        val heldBase: Long,
    )

    private const val MAX_ROWS = 4

    private var windowManager: WindowManager? = null
    private var rootView: View? = null
    private var params: WindowManager.LayoutParams? = null
    private var appContext: Context? = null
    private var channel: MethodChannel? = null

    private var address = "localhost"
    private var port = 0
    private var totalReqs = 0
    private var errorCount = 0
    private var feedPaused = false
    private var expanded = false
    private val recentLogs = ArrayDeque<LogEntry>()
    private var intercept: Intercept? = null
    private var lastSweepId: String? = null

    // What the collapsed bubble shows (configurable in Settings).
    private var showMethod = true
    private var showEndpoint = true
    private var showStatus = true
    private var showTime = false

    private var interceptionEnabled = false
    private var updatingSwitch = false

    val isShowing: Boolean get() = rootView != null

    fun attachChannel(channel: MethodChannel?) {
        this.channel = channel
    }

    fun hasPermission(context: Context): Boolean = Settings.canDrawOverlays(context)

    @SuppressLint("ClickableViewAccessibility", "InflateParams")
    fun show(context: Context) {
        if (rootView != null) return
        if (!hasPermission(context)) return
        val ctx = context.applicationContext
        appContext = ctx

        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val view = LayoutInflater.from(ctx).inflate(R.layout.overlay_root, null)

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(ctx, 16)
            y = dp(ctx, 120)
        }

        wm.addView(view, lp)
        windowManager = wm
        rootView = view
        params = lp

        bindInteractions(ctx, view)
        render()
    }

    fun hide() {
        val view = rootView ?: return
        try {
            windowManager?.removeView(view)
        } catch (_: Exception) {
        }
        rootView = null
        windowManager = null
        params = null
        expanded = false
        lastSweepId = null
    }

    // ── Update API (from the channel) ──────────────────────────────────────────

    fun setServerStatus(address: String, port: Int) {
        this.address = address
        this.port = port
        render()
    }

    fun pushLog(method: String, path: String, statusCode: Int, responseTimeMs: Int) {
        totalReqs++
        if (statusCode >= 400) errorCount++
        if (!feedPaused) {
            recentLogs.addFirst(LogEntry(method, path, statusCode, responseTimeMs))
            while (recentLogs.size > MAX_ROWS) recentLogs.removeLast()
        }
        render()
    }

    fun setOverlayContent(method: Boolean, endpoint: Boolean, status: Boolean, time: Boolean) {
        showMethod = method
        showEndpoint = endpoint
        showStatus = status
        showTime = time
        render()
    }

    fun setInterceptionEnabled(enabled: Boolean) {
        interceptionEnabled = enabled
        render()
    }

    fun setIntercepted(id: String, isResponse: Boolean, method: String, url: String, statusCode: Int?, body: String?) {
        intercept = Intercept(id, isResponse, method, url, statusCode, body, SystemClock.elapsedRealtime())
        render()
    }

    fun clearIntercepted() {
        intercept = null
        lastSweepId = null
        rootView?.findViewById<View>(R.id.ov_int_sweep)?.clearAnimation()
        render()
    }

    // ── Interactions ───────────────────────────────────────────────────────────

    @SuppressLint("ClickableViewAccessibility")
    private fun bindInteractions(ctx: Context, view: View) {
        view.findViewById<View>(R.id.ov_bubble)
            .setOnTouchListener(dragListener(ctx) { expanded = true; render() })
        view.findViewById<View>(R.id.ov_feed_header)
            .setOnTouchListener(dragListener(ctx) { expanded = false; render() })
        view.findViewById<View>(R.id.ov_int_header)
            .setOnTouchListener(dragListener(ctx) {})

        view.findViewById<View>(R.id.ov_feed_collapse).setOnClickListener { expanded = false; render() }
        view.findViewById<Switch>(R.id.ov_interception_switch).setOnCheckedChangeListener { _, isChecked ->
            if (updatingSwitch) return@setOnCheckedChangeListener
            channel?.invokeMethod("toggleInterception", mapOf("enabled" to isChecked))
        }
        view.findViewById<View>(R.id.ov_action_pause).setOnClickListener { feedPaused = !feedPaused; render() }
        view.findViewById<View>(R.id.ov_action_stop).setOnClickListener { channel?.invokeMethod("stopServer", null) }
        view.findViewById<View>(R.id.ov_action_logs).setOnClickListener {
            openApp(ctx)
            channel?.invokeMethod("openLogs", null)
        }

        view.findViewById<View>(R.id.ov_int_continue).setOnClickListener {
            channel?.invokeMethod("interceptionContinue", mapOf("id" to intercept?.id))
        }
        view.findViewById<View>(R.id.ov_int_drop).setOnClickListener {
            channel?.invokeMethod("interceptionDrop", mapOf("id" to intercept?.id))
        }
        view.findViewById<View>(R.id.ov_int_edit).setOnClickListener { openApp(ctx) }
    }

    private fun openApp(ctx: Context) {
        val intent = Intent(ctx, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        ctx.startActivity(intent)
    }

    /** Drag the window; if the finger barely moved, treat it as a click. */
    private fun dragListener(ctx: Context, onClick: () -> Unit): View.OnTouchListener {
        val slop = ViewConfiguration.get(ctx).scaledTouchSlop
        var startX = 0
        var startY = 0
        var touchX = 0f
        var touchY = 0f
        var moved = false
        return View.OnTouchListener { _, event ->
            val lp = params ?: return@OnTouchListener false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = lp.x; startY = lp.y
                    touchX = event.rawX; touchY = event.rawY
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - touchX).toInt()
                    val dy = (event.rawY - touchY).toInt()
                    if (abs(dx) > slop || abs(dy) > slop) moved = true
                    lp.x = startX + dx
                    lp.y = startY + dy
                    rootView?.let { windowManager?.updateViewLayout(it, lp) }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) onClick()
                    true
                }
                else -> false
            }
        }
    }

    // ── Rendering ──────────────────────────────────────────────────────────────

    private fun render() {
        val view = rootView ?: return
        view.post {
            val held = intercept
            view.findViewById<View>(R.id.ov_bubble).visibility =
                if (held == null && !expanded) View.VISIBLE else View.GONE
            view.findViewById<View>(R.id.ov_feed).visibility =
                if (held == null && expanded) View.VISIBLE else View.GONE
            view.findViewById<View>(R.id.ov_intercept).visibility =
                if (held != null) View.VISIBLE else View.GONE

            if (held != null) renderIntercept(view, held) else if (expanded) renderFeed(view) else renderBubble(view)

            params?.let { lp -> windowManager?.updateViewLayout(view, lp) }
        }
    }

    private fun renderBubble(view: View) {
        val last = recentLogs.firstOrNull()
        val method = view.findViewById<TextView>(R.id.ov_bubble_method)
        val path = view.findViewById<TextView>(R.id.ov_bubble_path)
        val status = view.findViewById<TextView>(R.id.ov_bubble_status)
        val time = view.findViewById<TextView>(R.id.ov_bubble_time)
        val idle = view.findViewById<TextView>(R.id.ov_bubble_idle)

        val showMethodNow = last != null && showMethod
        val showEndpointNow = last != null && showEndpoint
        val showStatusNow = last != null && showStatus
        val showTimeNow = last != null && showTime
        val anything = showMethodNow || showEndpointNow || showStatusNow || showTimeNow

        method.visibility = if (showMethodNow) View.VISIBLE else View.GONE
        path.visibility = if (showEndpointNow) View.VISIBLE else View.GONE
        status.visibility = if (showStatusNow) View.VISIBLE else View.GONE
        time.visibility = if (showTimeNow) View.VISIBLE else View.GONE
        idle.visibility = if (anything) View.GONE else View.VISIBLE

        if (last != null) {
            method.text = last.method
            method.setTextColor(methodColor(last.method))
            path.text = last.path
            status.text = last.statusCode.toString()
            status.setTextColor(statusColor(last.statusCode))
            time.text = "${last.responseTimeMs}ms"
        }
    }

    private fun renderFeed(view: View) {
        view.findViewById<TextView>(R.id.ov_feed_sub).text = "$endpoint · $totalReqs reqs · $errorCount errors"
        (view.findViewById<TextView>(R.id.ov_action_pause)).text = if (feedPaused) "RESUME" else "PAUSE"

        val sw = view.findViewById<Switch>(R.id.ov_interception_switch)
        if (sw.isChecked != interceptionEnabled) {
            updatingSwitch = true
            sw.isChecked = interceptionEnabled
            updatingSwitch = false
        }

        val rows = intArrayOf(R.id.ov_row0, R.id.ov_row1, R.id.ov_row2, R.id.ov_row3)
        val methods = intArrayOf(R.id.ov_row0_method, R.id.ov_row1_method, R.id.ov_row2_method, R.id.ov_row3_method)
        val paths = intArrayOf(R.id.ov_row0_path, R.id.ov_row1_path, R.id.ov_row2_path, R.id.ov_row3_path)
        val statuses = intArrayOf(R.id.ov_row0_status, R.id.ov_row1_status, R.id.ov_row2_status, R.id.ov_row3_status)

        val logs = recentLogs.toList()
        for (i in 0 until MAX_ROWS) {
            if (i < logs.size) {
                val log = logs[i]
                view.findViewById<View>(rows[i]).visibility = View.VISIBLE
                view.findViewById<TextView>(methods[i]).apply { text = log.method; setTextColor(methodColor(log.method)) }
                view.findViewById<TextView>(paths[i]).text = log.path
                view.findViewById<TextView>(statuses[i]).apply { text = log.statusCode.toString(); setTextColor(statusColor(log.statusCode)) }
            } else {
                view.findViewById<View>(rows[i]).visibility = View.GONE
            }
        }
    }

    private fun renderIntercept(view: View, held: Intercept) {
        val accent = ContextCompat.getColor(view.context, if (held.isResponse) R.color.ar_blue else R.color.ar_amber)
        // Translucent track + solid sweeping segment, recoloured per request/response.
        view.findViewById<View>(R.id.ov_int_accent).setBackgroundColor((accent and 0x00FFFFFF) or 0x40000000)
        val sweep = view.findViewById<View>(R.id.ov_int_sweep)
        sweep.setBackgroundColor(accent)
        if (lastSweepId != held.id) {
            lastSweepId = held.id
            sweep.startAnimation(
                TranslateAnimation(
                    Animation.RELATIVE_TO_SELF, -1f,
                    Animation.RELATIVE_TO_SELF, 2.5f,
                    Animation.RELATIVE_TO_SELF, 0f,
                    Animation.RELATIVE_TO_SELF, 0f,
                ).apply {
                    duration = 1400
                    repeatCount = Animation.INFINITE
                    interpolator = AccelerateDecelerateInterpolator()
                },
            )
        }
        view.findViewById<TextView>(R.id.ov_int_dot).setTextColor(accent)
        view.findViewById<TextView>(R.id.ov_int_title).apply {
            setTextColor(accent)
            text = if (held.isResponse) "Response intercepted" else "Request intercepted"
        }
        view.findViewById<TextView>(R.id.ov_int_sub).text =
            if (held.isResponse) "A response is held before delivery." else "An outbound request is being held."

        view.findViewById<Chronometer>(R.id.ov_int_timer).apply {
            base = held.heldBase
            format = "held %s"
            start()
        }

        view.findViewById<TextView>(R.id.ov_int_method).apply { text = held.method; setTextColor(methodColor(held.method)) }
        view.findViewById<TextView>(R.id.ov_int_path).text = held.url

        val statusView = view.findViewById<TextView>(R.id.ov_int_status)
        if (held.statusCode != null) {
            statusView.visibility = View.VISIBLE
            statusView.text = held.statusCode.toString()
            statusView.setTextColor(statusColor(held.statusCode))
        } else {
            statusView.visibility = View.GONE
        }

        val bodyView = view.findViewById<TextView>(R.id.ov_int_resp_body)
        if (!held.body.isNullOrBlank()) {
            bodyView.visibility = View.VISIBLE
            bodyView.text = held.body
        } else {
            bodyView.visibility = View.GONE
        }

        view.findViewById<TextView>(R.id.ov_int_edit).text = if (held.isResponse) "Edit body" else "Edit"
    }

    private val endpoint: String get() = if (port > 0) "$address:$port" else address

    private fun methodColor(method: String): Int = ContextCompat.getColor(
        appContext!!,
        when (method.uppercase()) {
            "GET", "HEAD", "OPTIONS" -> R.color.ar_blue
            "POST" -> R.color.ar_green
            "PUT", "PATCH" -> R.color.ar_amber
            "DELETE", "DEL" -> R.color.ar_red
            else -> R.color.ar_text
        },
    )

    private fun statusColor(code: Int): Int = ContextCompat.getColor(
        appContext!!,
        when {
            code in 200..299 -> R.color.ar_green
            code in 300..399 -> R.color.ar_amber
            code >= 400 -> R.color.ar_red
            else -> R.color.ar_text
        },
    )

    private fun dp(ctx: Context, value: Int): Int = (value * ctx.resources.displayMetrics.density).toInt()
}
