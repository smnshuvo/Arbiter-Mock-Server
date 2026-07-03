package auravation.arbiter.mock_server

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "auravation.arbiter.mock_server/foreground_service"
    private val OVERLAY_CHANNEL = "auravation.arbiter.mock_server/overlay"
    private val FILE_SERVER_CHANNEL = "auravation.arbiter.mock_server/file_server"
    private val FILE_SERVER_EVENTS = "auravation.arbiter.mock_server/file_server_events"
    private var methodChannel: MethodChannel? = null
    private var overlayChannel: MethodChannel? = null
    private var fileServerChannel: MethodChannel? = null
    private var fileServerEvents: EventChannel? = null
    private var stopServerReceiver: BroadcastReceiver? = null
    private var isReceiverRegistered = false
    private var pendingFolderResult: MethodChannel.Result? = null

    companion object {
        private const val REQUEST_PICK_FOLDER = 4201
        private const val FILE_SERVER_PREFS = "file_server_prefs"
        private const val KEY_ROOT_URI = "root_uri"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        overlayChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OVERLAY_CHANNEL)
        overlayChannel?.setMethodCallHandler { call, result -> handleOverlay(call, result) }
        OverlayController.attachChannel(overlayChannel)

        fileServerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_SERVER_CHANNEL)
        fileServerChannel?.setMethodCallHandler { call, result -> handleFileServer(call, result) }

        // Native → Dart stream for scan progress + live request counter.
        fileServerEvents = EventChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_SERVER_EVENTS)
        fileServerEvents?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                FileServerEvents.attach(events)
                ScanController.progressListener = { done, total, complete ->
                    FileServerEvents.scanProgress(done, total, complete)
                }
            }

            override fun onCancel(arguments: Any?) {
                ScanController.progressListener = null
                FileServerEvents.detach()
            }
        })

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    try {
                        ForegroundService.startService(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to start foreground service", e.message)
                    }
                }
                "stopForegroundService" -> {
                    try {
                        ForegroundService.stopService(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to stop foreground service", e.message)
                    }
                }
                "updateNotification" -> {
                    try {
                        val method = call.argument<String>("method") ?: ""
                        val path = call.argument<String>("path") ?: ""
                        val timestamp = call.argument<String>("timestamp") ?: ""
                        val endpointName = call.argument<String>("endpointName")
                        
                        // Get the running service instance and update notification
                        val intent = Intent(this, ForegroundService::class.java)
                        // We need to send a broadcast or use a singleton to update the notification
                        // For simplicity, we'll use a static method approach
                        ForegroundService.updateNotification(this, method, path, timestamp, endpointName)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to update notification", e.message)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    /** Floating overlay channel: Dart drives the system-wide overlay window. */
    private fun handleOverlay(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "hasOverlayPermission" -> result.success(OverlayController.hasPermission(this))
                "requestOverlayPermission" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                }
                "showOverlay" -> { OverlayController.show(this); result.success(OverlayController.isShowing) }
                "hideOverlay" -> { OverlayController.hide(); result.success(true) }
                "setServerStatus" -> {
                    OverlayController.setServerStatus(
                        call.argument<String>("address") ?: "localhost",
                        call.argument<Int>("port") ?: 0,
                    )
                    result.success(true)
                }
                "pushLog" -> {
                    OverlayController.pushLog(
                        call.argument<String>("method") ?: "GET",
                        call.argument<String>("path") ?: "/",
                        call.argument<Int>("statusCode") ?: 0,
                        call.argument<Int>("responseTimeMs") ?: 0,
                    )
                    result.success(true)
                }
                "setOverlayContent" -> {
                    OverlayController.setOverlayContent(
                        call.argument<Boolean>("method") ?: true,
                        call.argument<Boolean>("endpoint") ?: true,
                        call.argument<Boolean>("status") ?: true,
                        call.argument<Boolean>("time") ?: false,
                    )
                    result.success(true)
                }
                "setInterceptionEnabled" -> {
                    OverlayController.setInterceptionEnabled(call.argument<Boolean>("enabled") ?: false)
                    result.success(true)
                }
                "setIntercepted" -> {
                    OverlayController.setIntercepted(
                        call.argument<String>("id") ?: "",
                        call.argument<String>("type") == "response",
                        call.argument<String>("method") ?: "GET",
                        call.argument<String>("url") ?: "/",
                        call.argument<Int>("statusCode"),
                        call.argument<String>("body"),
                    )
                    result.success(true)
                }
                "clearIntercepted" -> { OverlayController.clearIntercepted(); result.success(true) }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("OVERLAY_ERROR", e.message, null)
        }
    }

    /** File-server channel: Dart drives the native NanoHTTPD Wi-Fi file server. */
    private fun handleFileServer(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "startServer" -> {
                    val port = call.argument<Int>("port") ?: 8080
                    val rootUri = call.argument<String>("rootUri")
                    if (rootUri.isNullOrEmpty()) {
                        result.error("NO_ROOT_URI", "A shared folder must be picked first", null)
                        return
                    }
                    FileServer.uploadsEnabled =
                        call.argument<Boolean>("uploadsEnabled") ?: false
                    FileServer.authUser =
                        call.argument<String>("authUser")?.takeIf { it.isNotBlank() }
                    FileServer.authPass = call.argument<String>("authPass")
                    val stopIfIdle = call.argument<Boolean>("stopIfIdle") ?: true
                    FileServerService.startService(this, port, rootUri, stopIfIdle)
                    result.success(true)
                }
                "setUploadsEnabled" -> {
                    FileServer.uploadsEnabled = call.argument<Boolean>("enabled") ?: false
                    result.success(true)
                }
                "setAuth" -> {
                    FileServer.authUser =
                        call.argument<String>("user")?.takeIf { it.isNotBlank() }
                    FileServer.authPass = call.argument<String>("pass")
                    result.success(true)
                }
                "sendRemoteKey" -> {
                    FileServer.pushRemote(call.argument<String>("key") ?: "")
                    result.success(true)
                }
                "sendRemoteText" -> {
                    FileServer.pushRemote("text:" + (call.argument<String>("text") ?: ""))
                    result.success(true)
                }
                "getRemoteClients" -> result.success(FileServer.remoteClientCount())
                "hapticTick" -> {
                    performHapticTick()
                    result.success(true)
                }
                "getTrafficStats" ->
                    result.success(mapOf("totalBytes" to FileServer.totalBytes.get()))
                "stopServer" -> {
                    FileServerService.stopService(this)
                    result.success(true)
                }
                "getLocalIp" -> result.success(FileServerService.getLocalIpAddress())
                "pickFolder" -> pickSharedFolder(result)
                "getSavedFolder" -> result.success(savedFolder())
                "scanLibrary" -> {
                    val uriString = call.argument<String>("rootUri")
                        ?: savedFolder()?.get("uri")
                    if (uriString.isNullOrEmpty()) {
                        result.error("NO_ROOT_URI", "No shared folder to scan", null)
                    } else {
                        ScanController.start(applicationContext, Uri.parse(uriString))
                        result.success(true)
                    }
                }
                "cancelScan" -> {
                    ScanController.cancel()
                    result.success(true)
                }
                "isScanning" -> result.success(ScanController.isScanning())
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("FILE_SERVER_ERROR", e.message, null)
        }
    }

    /**
     * A crisp click vibration for the TV-remote buttons. Uses the Vibrator service
     * directly — Flutter's HapticFeedback maps to performHapticFeedback(), which many
     * devices gate behind the system "touch feedback" setting and is barely felt.
     */
    private fun performHapticTick() {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val manager =
                    getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager
                manager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as android.os.Vibrator
            }
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> vibrator.vibrate(
                    android.os.VibrationEffect.createPredefined(
                        android.os.VibrationEffect.EFFECT_CLICK,
                    ),
                )
                else -> vibrator.vibrate(
                    android.os.VibrationEffect.createOneShot(
                        20, android.os.VibrationEffect.DEFAULT_AMPLITUDE,
                    ),
                )
            }
        } catch (_: Exception) {
            // Missing/blocked vibrator: silently skip, feedback is non-essential.
        }
    }

    /**
     * Launches the SAF folder picker. The result is delivered asynchronously in
     * [onActivityResult], which is why [pendingFolderResult] is held until then.
     */
    private fun pickSharedFolder(result: MethodChannel.Result) {
        if (pendingFolderResult != null) {
            result.error("PICKER_BUSY", "A folder picker is already open", null)
            return
        }
        pendingFolderResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    // Write is needed for browser uploads into the shared folder.
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        try {
            startActivityForResult(intent, REQUEST_PICK_FOLDER)
        } catch (e: Exception) {
            pendingFolderResult = null
            result.error("PICKER_ERROR", e.message, null)
        }
    }

    /** Returns the persisted shared folder as {uri, name}, or null if none/lost. */
    private fun savedFolder(): Map<String, String>? {
        val prefs = getSharedPreferences(FILE_SERVER_PREFS, Context.MODE_PRIVATE)
        val uriString = prefs.getString(KEY_ROOT_URI, null) ?: return null
        val uri = Uri.parse(uriString)
        // Confirm the persisted permission still holds (it can be revoked/lost on reboot).
        val stillGranted = contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isReadPermission
        }
        if (!stillGranted) return null
        val name = DocumentFile.fromTreeUri(this, uri)?.name ?: "Shared folder"
        return mapOf("uri" to uriString, "name" to name)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_FOLDER) return
        val result = pendingFolderResult
        pendingFolderResult = null
        if (result == null) return

        val treeUri = data?.data
        if (resultCode != Activity.RESULT_OK || treeUri == null) {
            result.success(null) // user cancelled
            return
        }
        try {
            // MANDATORY: persist the grant or access breaks after a reboot. Write is
            // included so browser uploads can create files; folders picked before this
            // change hold a read-only grant until re-picked.
            contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
            getSharedPreferences(FILE_SERVER_PREFS, Context.MODE_PRIVATE).edit()
                .putString(KEY_ROOT_URI, treeUri.toString())
                .apply()
            val name = DocumentFile.fromTreeUri(this, treeUri)?.name ?: "Shared folder"
            result.success(mapOf("uri" to treeUri.toString(), "name" to name))
        } catch (e: Exception) {
            result.error("PERSIST_ERROR", e.message, null)
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d("MainActivity", "============================================")
        Log.d("MainActivity", "onCreate called - Registering broadcast receiver")
        // Register broadcast receiver to listen for stop server action from notification
        // We register it here instead of onResume so it persists even when app is in background
        registerStopServerReceiver()
        Log.d("MainActivity", "============================================")
    }

    override fun onResume() {
        super.onResume()
        Log.d("MainActivity", "============================================")
        Log.d("MainActivity", "onResume called - Activity is now in FOREGROUND")
        Log.d("MainActivity", "Receiver is already registered from onCreate")
        Log.d("MainActivity", "============================================")
    }

    override fun onPause() {
        super.onPause()
        Log.d("MainActivity", "============================================")
        Log.d("MainActivity", "onPause called - Activity is going to BACKGROUND")
        Log.d("MainActivity", "NOT unregistering receiver - keeping it registered for background stop button")
        Log.d("MainActivity", "============================================")
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d("MainActivity", "============================================")
        Log.d("MainActivity", "onDestroy called - Unregistering broadcast receiver")
        // Only unregister when activity is completely destroyed
        unregisterStopServerReceiver()
        // The engine is torn down with the activity; drop the stale channel reference.
        OverlayController.attachChannel(null)
        Log.d("MainActivity", "============================================")
    }

    override fun onStop() {
        super.onStop()
        Log.d("MainActivity", "onStop called - Activity is no longer visible")
    }

    override fun onStart() {
        super.onStart()
        Log.d("MainActivity", "onStart called - Activity is becoming visible")
    }

    private fun registerStopServerReceiver() {
        Log.d("MainActivity", "registerStopServerReceiver: Creating receiver")
        stopServerReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                Log.d("MainActivity", "============================================")
                Log.d("MainActivity", "onReceive: Broadcast received!")
                Log.d("MainActivity", "onReceive: Broadcast action: ${intent?.action}")
                Log.d("MainActivity", "onReceive: Expected action: ${ForegroundService.ACTION_STOP_SERVER_BROADCAST}")
                Log.d("MainActivity", "onReceive: Receiver is registered: $isReceiverRegistered")
                
                if (intent?.action == ForegroundService.ACTION_STOP_SERVER_BROADCAST) {
                    Log.d("MainActivity", "onReceive: ✓ Action matches - Stop server broadcast received")
                    Log.d("MainActivity", "onReceive: methodChannel is ${if (methodChannel != null) "available" else "NULL"}")
                    
                    // Communicate with Flutter to stop the server
                    Log.d("MainActivity", "onReceive: Invoking stopServer method on MethodChannel...")
                    methodChannel?.invokeMethod("stopServer", null, object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            Log.d("MainActivity", "onReceive: MethodChannel SUCCESS - Server stopped with result: $result")
                            if (result is Boolean && result) {
                                Log.d("MainActivity", "onReceive: ✓ Server stopped successfully")
                            } else {
                                Log.e("MainActivity", "onReceive: ✗ Server stop failed - result: $result")
                            }
                        }
                        
                        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                            Log.e("MainActivity", "onReceive: ✗ MethodChannel ERROR - Code: $errorCode, Message: $errorMessage, Details: $errorDetails")
                        }
                        
                        override fun notImplemented() {
                            Log.e("MainActivity", "onReceive: ✗ MethodChannel NOT_IMPLEMENTED - stopServer method not implemented in Flutter")
                        }
                    }) ?: Log.e("MainActivity", "onReceive: ✗ methodChannel is NULL - cannot invoke stopServer")
                } else {
                    Log.w("MainActivity", "onReceive: ✗ Action does not match - Received: ${intent?.action}, Expected: ${ForegroundService.ACTION_STOP_SERVER_BROADCAST}")
                }
                Log.d("MainActivity", "============================================")
            }
        }
        
        val filter = IntentFilter(ForegroundService.ACTION_STOP_SERVER_BROADCAST)
        // Use RECEIVER_EXPORTED since ForegroundService (same app) sends broadcast to this receiver
        // RECEIVER_NOT_EXPORTED would prevent the broadcast from being received
        registerReceiver(stopServerReceiver, filter, Context.RECEIVER_EXPORTED)
        isReceiverRegistered = true
        Log.d("MainActivity", "registerStopServerReceiver: ✓ Receiver registered successfully with RECEIVER_EXPORTED")
    }

    private fun unregisterStopServerReceiver() {
        Log.d("MainActivity", "unregisterStopServerReceiver: Attempting to unregister receiver (isReceiverRegistered: $isReceiverRegistered)")
        try {
            stopServerReceiver?.let {
                unregisterReceiver(it)
                isReceiverRegistered = false
                Log.d("MainActivity", "unregisterStopServerReceiver: ✓ Receiver unregistered successfully")
            } ?: Log.w("MainActivity", "unregisterStopServerReceiver: Receiver was already null")
        } catch (e: Exception) {
            Log.e("MainActivity", "unregisterStopServerReceiver: ✗ Error unregistering receiver: ${e.message}")
        }
    }
}
