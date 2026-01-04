package auravation.arbiter.mock_server

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "auravation.arbiter.mock_server/foreground_service"
    private var methodChannel: MethodChannel? = null
    private var stopServerReceiver: BroadcastReceiver? = null
    private var isReceiverRegistered = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
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
