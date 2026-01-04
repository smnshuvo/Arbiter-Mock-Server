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
import androidx.core.app.NotificationCompat

class ForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "mock_server_channel"
        private const val NOTIFICATION_ID = 1001
        private const val ACTION_STOP = "action_stop"
        const val ACTION_STOP_SERVER_BROADCAST = "auravation.arbiter.mock_server.ACTION_STOP_SERVER"
        const val ACTION_STOP_FROM_NOTIFICATION = "auravation.arbiter.mock_server.STOP_FROM_NOTIFICATION"
        
        fun startService(context: Context) {
            val intent = Intent(context, ForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun stopService(context: Context) {
            val intent = Intent(context, ForegroundService::class.java)
            context.stopService(intent)
        }
        
        fun updateNotification(context: Context, method: String, path: String, timestamp: String, endpointName: String? = null) {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // Create intent to open the app when notification is clicked
            val notificationIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            
            val contentPendingIntent = PendingIntent.getActivity(
                context,
                0,
                notificationIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            
            val stopIntent = Intent(context, ForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            
            val stopPendingIntent = PendingIntent.getService(
                context,
                1,
                stopIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )

            val contentText = if (method.isNotEmpty() && path.isNotEmpty()) {
                val endpointInfo = if (endpointName != null && endpointName.isNotEmpty()) {
                    "Endpoint: $endpointName\n"
                } else {
                    ""
                }
                "Last hit: $endpointInfo$method $path\n$timestamp"
            } else {
                "Server is running"
            }

            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setContentTitle("Mock Server Running")
                .setContentText(contentText)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setContentIntent(contentPendingIntent)
                .addAction(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "Stop",
                    stopPendingIntent
                )
                .build()
            
            notificationManager.notify(NOTIFICATION_ID, notification)
        }
    }

    private var currentMethod: String = ""
    private var currentPath: String = ""
    private var currentTimestamp: String = ""
    private var currentEndpointName: String? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // DIAGNOSTIC: Log when onStartCommand is called
        android.util.Log.d("ForegroundService", "onStartCommand called")
        android.util.Log.d("ForegroundService", "Intent action: ${intent?.action}")
        
        // Check if ACTION_STOP is received
        if (intent?.action == ACTION_STOP) {
            android.util.Log.d("ForegroundService", "ACTION_STOP received - stop button pressed")
            
            // Send broadcast to MainActivity to stop the server
            // DO NOT stop the service here - let Flutter stop the server first, then stop the service
            val stopIntent = Intent(ACTION_STOP_SERVER_BROADCAST)
            sendBroadcast(stopIntent)
            android.util.Log.d("ForegroundService", "Broadcast sent to stop server")
            
            // Don't stop the service yet - wait for Flutter to stop the server
            return START_NOT_STICKY
        }
        
        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Mock Server Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Notification channel for Mock Server foreground service"
                setShowBadge(false)
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        // Create intent to open the app when notification is clicked
        val notificationIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        
        val contentPendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val stopIntent = Intent(this, ForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val contentText = if (currentMethod.isNotEmpty() && currentPath.isNotEmpty()) {
            val endpointInfo = if (currentEndpointName != null && currentEndpointName!!.isNotEmpty()) {
                "Endpoint: $currentEndpointName\n"
            } else {
                ""
            }
            "Last hit: $endpointInfo$currentMethod $currentPath\n$currentTimestamp"
        } else {
            "Server is running"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Mock Server Running")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(contentPendingIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Stop",
                stopPendingIntent
            )
            .build()
    }

    fun updateNotification(method: String, path: String, timestamp: String, endpointName: String? = null) {
        currentMethod = method
        currentPath = path
        currentTimestamp = timestamp
        currentEndpointName = endpointName
        
        val notification = createNotification()
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    override fun onDestroy() {
        super.onDestroy()
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(NOTIFICATION_ID)
    }
}
