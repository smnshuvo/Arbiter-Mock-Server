package auravation.arbiter.mock_server

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import java.net.Inet4Address
import java.net.NetworkInterface

/**
 * Foreground service that owns the native [FileServer] lifecycle and keeps it alive
 * while the app is backgrounded. Deliberately separate from [ForegroundService] (the
 * mock server) so the two have independent notifications and lifecycles — they can run
 * concurrently. Uses its own notification channel + id to avoid collisions.
 */
class FileServerService : Service() {

    companion object {
        private const val TAG = "FileServerService"
        private const val CHANNEL_ID = "file_server_channel"
        private const val NOTIFICATION_ID = 2001
        private const val ACTION_STOP = "action_stop_file_server"

        const val EXTRA_PORT = "extra_port"
        const val EXTRA_ROOT_URI = "extra_root_uri"
        const val EXTRA_STOP_IF_IDLE = "extra_stop_if_idle"

        /** Auto-stop the server after this much inactivity when "stop if idle" is on. */
        private const val IDLE_TIMEOUT_MS = 60L * 60L * 1000L // 1 hour

        /** Broadcast fired when the notification "Stop" button is tapped. */
        const val ACTION_STOP_SERVER_BROADCAST =
            "auravation.arbiter.mock_server.ACTION_STOP_FILE_SERVER"

        fun startService(context: Context, port: Int, rootUri: String, stopIfIdle: Boolean) {
            val intent = Intent(context, FileServerService::class.java).apply {
                putExtra(EXTRA_PORT, port)
                putExtra(EXTRA_ROOT_URI, rootUri)
                putExtra(EXTRA_STOP_IF_IDLE, stopIfIdle)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopService(context: Context) {
            context.stopService(Intent(context, FileServerService::class.java))
        }

        /** The device's current Wi-Fi/local IPv4 address, or null if not connected. */
        fun getLocalIpAddress(): String? {
            return try {
                NetworkInterface.getNetworkInterfaces().asSequence()
                    .filter { it.isUp && !it.isLoopback }
                    .flatMap { it.inetAddresses.asSequence() }
                    .filterIsInstance<Inet4Address>()
                    .firstOrNull { !it.isLoopbackAddress }
                    ?.hostAddress
            } catch (e: Exception) {
                Log.e(TAG, "Failed to resolve local IP: ${e.message}")
                null
            }
        }
    }

    private var server: FileServer? = null
    private var port: Int = 8080
    private var stopIfIdle: Boolean = true
    private var idleWatchdog: java.util.concurrent.ScheduledExecutorService? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            Log.d(TAG, "Stop action received from notification")
            stopSelf()
            return START_NOT_STICKY
        }

        port = intent?.getIntExtra(EXTRA_PORT, 8080) ?: 8080
        stopIfIdle = intent?.getBooleanExtra(EXTRA_STOP_IF_IDLE, true) ?: true
        val rootUriString = intent?.getStringExtra(EXTRA_ROOT_URI)

        // Show the notification first so we satisfy the foreground-service contract even
        // if the server fails to bind.
        startForeground(NOTIFICATION_ID, buildNotification(urlText()))

        if (rootUriString.isNullOrEmpty()) {
            Log.e(TAG, "No root URI supplied; stopping")
            stopSelf()
            return START_NOT_STICKY
        }

        try {
            stopServerInstance()
            // Traffic stats are per server session.
            FileServer.totalBytes.set(0)
            FileServer.lastActivityAt = System.currentTimeMillis()
            server = FileServer(applicationContext, Uri.parse(rootUriString), port).also {
                it.start(NanoHttpdConstants.SOCKET_READ_TIMEOUT, false)
            }
            Log.d(TAG, "File server started on port $port (stopIfIdle=$stopIfIdle)")
            startIdleWatchdog()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start file server: ${e.message}")
            stopSelf()
            return START_NOT_STICKY
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        stopServerInstance()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(NOTIFICATION_ID)
    }

    private fun stopServerInstance() {
        idleWatchdog?.shutdownNow()
        idleWatchdog = null
        try {
            server?.stop()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping server: ${e.message}")
        }
        server = null
    }

    /**
     * When "stop if idle" is enabled, poll once a minute and stop the server once it has
     * gone [IDLE_TIMEOUT_MS] without a request — but never while a download/stream is
     * still in flight. Notifies Dart so the UI flips back to the stopped state.
     */
    private fun startIdleWatchdog() {
        idleWatchdog?.shutdownNow()
        if (!stopIfIdle) {
            idleWatchdog = null
            return
        }
        val exec = java.util.concurrent.Executors.newSingleThreadScheduledExecutor()
        idleWatchdog = exec
        exec.scheduleWithFixedDelay(
            {
                try {
                    if (FileServer.idleMillis() >= IDLE_TIMEOUT_MS &&
                        FileServer.activeStreamCount() == 0
                    ) {
                        Log.d(TAG, "Idle timeout reached; auto-stopping file server")
                        FileServerEvents.serverStopped()
                        stopSelf()
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Idle watchdog error: ${e.message}")
                }
            },
            60L, 60L, java.util.concurrent.TimeUnit.SECONDS,
        )
    }

    private fun urlText(): String {
        val ip = getLocalIpAddress() ?: return "Waiting for Wi-Fi…"
        return "http://$ip:$port"
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "File Server Service",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Notification channel for the Wi-Fi file server"
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(contentText: String): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentPendingIntent = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val stopIntent = Intent(this, FileServerService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("File Server Running")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(contentPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPendingIntent)
            .build()
    }
}

/** NanoHTTPD's default socket read timeout, kept here to avoid a magic number. */
object NanoHttpdConstants {
    const val SOCKET_READ_TIMEOUT = 10_000
}
