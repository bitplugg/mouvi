package com.bitplugg.vpn_client

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

/**
 * Локальные уведомления о состоянии соединения.
 *
 * Это не «push» из интернета, а системные уведомления Android о том,
 * что туннель поднят или опущен. Разрешение POST_NOTIFICATIONS
 * запрашивается из Activity.
 */
class MouviNotifications(private val context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun isEnabled(): Boolean = prefs.getBoolean(KEY_ENABLED, false)

    fun setEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_ENABLED, enabled).apply()
        if (enabled) {
            ensureChannel()
        }
    }

    fun notifyConnection(
        type: String,
        serverName: String?,
        protocol: String?,
        titleOverride: String? = null,
        textOverride: String? = null,
    ) {
        if (!isEnabled()) {
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        try {
            ensureChannel()
            val connected = type == "connected"
            // Заголовок приходит из Dart уже на языке приложения.
            val title = titleOverride?.takeIf { it.isNotBlank() } ?: context.getString(
                if (connected) R.string.notification_connected else R.string.notification_disconnected,
            )
            val details = listOfNotNull(
                serverName?.takeIf { it.isNotBlank() },
                protocol?.takeIf { it.isNotBlank() },
            ).joinToString(" · ")
            val body = textOverride?.takeIf { it.isNotBlank() } ?: details
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            builder
                .setSmallIcon(R.drawable.ic_stat_mouvi)
                .setContentTitle(title)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setOnlyAlertOnce(true)
            if (body.isNotEmpty()) {
                builder.setContentText(body)
            }
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(NOTIFICATION_ID, builder.build())
        } catch (_: Throwable) {
            // Уведомление не должно влиять на работу VPN.
        }
    }

    fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) {
            return
        }
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = context.getString(R.string.notification_channel_description)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val PREFS_NAME = "mouvi_notifications"
        private const val KEY_ENABLED = "enabled"
        private const val CHANNEL_ID = "mouvi_connection"
        private const val NOTIFICATION_ID = 1001
    }
}
