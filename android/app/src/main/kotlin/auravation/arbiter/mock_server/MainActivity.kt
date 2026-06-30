package auravation.arbiter.mock_server

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "auravation.arbiter.mock_server/foreground_service"
    private var methodChannel: MethodChannel? = null
    private var actionReceiver: BroadcastReceiver? = null
    private var isReceiverRegistered = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> tryRun(result) { ForegroundService.startService(this) }
                "stopForegroundService" -> tryRun(result) { ForegroundService.stopService(this) }
                "setServerStatus" -> tryRun(result) {
                    ForegroundService.instance?.setServerStatus(
                        call.argument<String>("address") ?: "localhost",
                        call.argument<Int>("port") ?: 0,
                    )
                }
                "pushLog" -> tryRun(result) {
                    ForegroundService.instance?.pushLog(
                        call.argument<String>("method") ?: "GET",
                        call.argument<String>("path") ?: "/",
                        call.argument<Int>("statusCode") ?: 0,
                    )
                }
                "setIntercepted" -> tryRun(result) {
                    ForegroundService.instance?.setIntercepted(
                        call.argument<String>("id") ?: "",
                        call.argument<String>("type") == "response",
                        call.argument<String>("method") ?: "GET",
                        call.argument<String>("url") ?: "/",
                        call.argument<Int>("statusCode"),
                        call.argument<String>("body"),
                    )
                }
                "clearIntercepted" -> tryRun(result) { ForegroundService.instance?.clearIntercepted() }
                // Legacy text notification; superseded by the live-activity feed.
                "updateNotification" -> result.success(true)
                else -> result.notImplemented()
            }
        }
    }

    private inline fun tryRun(result: MethodChannel.Result, block: () -> Unit) {
        try {
            block()
            result.success(true)
        } catch (e: Exception) {
            result.error("SERVICE_ERROR", e.message, null)
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        registerActionReceiver()
        handleLaunchIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleLaunchIntent(intent)
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterActionReceiver()
    }

    /** Notification buttons that foreground the app (Logs / Edit) arrive as launch intents. */
    private fun handleLaunchIntent(intent: Intent?) {
        when (intent?.action) {
            ForegroundService.ACTION_OPEN_LOGS ->
                methodChannel?.invokeMethod("openLogs", null)
            ForegroundService.ACTION_EDIT ->
                methodChannel?.invokeMethod(
                    "interceptionEdit",
                    mapOf("id" to intent.getStringExtra(ForegroundService.EXTRA_INTERCEPT_ID)),
                )
        }
    }

    private fun registerActionReceiver() {
        actionReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val id = intent?.getStringExtra(ForegroundService.EXTRA_INTERCEPT_ID)
                when (intent?.action) {
                    ForegroundService.ACTION_STOP_SERVER_BROADCAST ->
                        methodChannel?.invokeMethod("stopServer", null)
                    ForegroundService.ACTION_CONTINUE ->
                        methodChannel?.invokeMethod("interceptionContinue", mapOf("id" to id))
                    ForegroundService.ACTION_DROP ->
                        methodChannel?.invokeMethod("interceptionDrop", mapOf("id" to id))
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(ForegroundService.ACTION_STOP_SERVER_BROADCAST)
            addAction(ForegroundService.ACTION_CONTINUE)
            addAction(ForegroundService.ACTION_DROP)
        }
        // Same-app broadcasts from the notification; must be exported to be delivered.
        registerReceiver(actionReceiver, filter, Context.RECEIVER_EXPORTED)
        isReceiverRegistered = true
    }

    private fun unregisterActionReceiver() {
        try {
            actionReceiver?.let {
                unregisterReceiver(it)
                isReceiverRegistered = false
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error unregistering receiver: ${e.message}")
        }
    }
}
