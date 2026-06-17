package com.gurfdev.light_compressor_v2

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/**
 * Minimal foreground service that acts as a process-lifetime anchor while a
 * video compression runs, surfacing live status in its ongoing notification:
 * a progress bar + percentage, an elapsed-time chronometer, the current file /
 * batch position (as body text) and a Cancel action.
 *
 * It does **not** perform the compression itself — that keeps running in the
 * plugin's coroutine inside the same process. Promoting the process to the
 * foreground raises its importance so Android does not kill it while the app is
 * backgrounded or the screen is off.
 *
 * Started and stopped explicitly by [LightCompressorPlugin] around a single
 * compression call; progress and status are pushed in via [updateProgress].
 */
class CompressionForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: DEFAULT_TITLE
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: DEFAULT_TEXT

        activeTitle = title
        activeText = text
        createChannelIfNeeded(this)
        // Indeterminate bar until the first progress update arrives.
        val notification = buildNotification(this, title, text, null)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        // The service is started/stopped explicitly by the plugin around one
        // compression, so it must not be recreated if the process is killed.
        return START_NOT_STICKY
    }

    companion object {
        private const val CHANNEL_ID = "light_compressor_compression"
        private const val CHANNEL_NAME = "Video compression"
        private const val NOTIFICATION_ID = 0xC0FFEE
        private const val DEFAULT_TITLE = "Compressing video"
        private const val DEFAULT_TEXT = "Video compression in progress…"

        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"

        // State for the currently running compression. Held here so progress
        // updates can rebuild the notification in place. Only one runs at a time.
        @Volatile private var activeTitle: String? = null
        @Volatile private var activeText: String? = null
        @Volatile private var lastPercent = -1
        @Volatile private var startWhen = 0L

        /** Starts the foreground service with the given notification content. */
        fun start(context: Context, title: String, text: String) {
            activeTitle = title
            activeText = text
            lastPercent = -1
            startWhen = System.currentTimeMillis()
            val intent = Intent(context, CompressionForegroundService::class.java).apply {
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_TEXT, text)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /**
         * Updates the ongoing notification with [percent] (0–100) and, when
         * provided, a new body [text] (e.g. the current file / batch position).
         * Posting to the same notification id updates it in place. De-duplicates
         * when neither percent nor text changed, and is a no-op when the service
         * is not running or notifications are not granted.
         */
        fun updateProgress(context: Context, percent: Int, text: String?) {
            val title = activeTitle ?: return
            val clamped = percent.coerceIn(0, 100)
            val newText = text ?: activeText
            if (clamped == lastPercent && newText == activeText) return
            lastPercent = clamped
            if (newText != null) activeText = newText
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(
                    context, Manifest.permission.POST_NOTIFICATIONS,
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                return
            }
            NotificationManagerCompat.from(context).notify(
                NOTIFICATION_ID,
                buildNotification(context, title, activeText ?: DEFAULT_TEXT, clamped),
            )
        }

        /** Stops the foreground service if it is running. */
        fun stop(context: Context) {
            activeTitle = null
            activeText = null
            lastPercent = -1
            startWhen = 0L
            context.stopService(Intent(context, CompressionForegroundService::class.java))
        }

        /**
         * Builds the ongoing notification. A null [percent] renders an
         * indeterminate bar; a value renders a determinate `0..100` bar plus a
         * percentage sub-text. Always includes an elapsed-time chronometer and
         * a Cancel action.
         */
        private fun buildNotification(
            context: Context,
            title: String,
            text: String,
            percent: Int?,
        ): Notification {
            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(text)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setShowWhen(true)
                .setWhen(if (startWhen > 0L) startWhen else System.currentTimeMillis())
                .setUsesChronometer(true)
                .addAction(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    // System string, auto-localized by the OS (Cancel / Отмена / …).
                    context.getString(android.R.string.cancel),
                    cancelIntent(context),
                )
            if (percent == null) {
                builder.setProgress(0, 0, true)
            } else {
                val p = percent.coerceIn(0, 100)
                builder.setProgress(100, p, false)
                builder.setSubText("$p%")
            }
            return builder.build()
        }

        private fun pendingFlags(): Int =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

        /** The Cancel action broadcasts to [CompressionCancelReceiver]. */
        private fun cancelIntent(context: Context): PendingIntent {
            val intent = Intent(context, CompressionCancelReceiver::class.java)
            return PendingIntent.getBroadcast(context, 1, intent, pendingFlags())
        }

        private fun createChannelIfNeeded(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val manager =
                    context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                    manager.createNotificationChannel(
                        NotificationChannel(
                            CHANNEL_ID,
                            CHANNEL_NAME,
                            NotificationManager.IMPORTANCE_LOW,
                        )
                    )
                }
            }
        }
    }
}
