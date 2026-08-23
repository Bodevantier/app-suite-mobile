package com.example.ble_application

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * Posts/cancels the one-shot notification for an active boat alarm (tank
 * level, temperature, ...). Deliberately built the same way as the ongoing
 * gateway-connection notification in [BleForegroundService] — same
 * `NotificationCompat`/`NotificationManager` approach, just a separate
 * high-importance channel and no foreground service attached, since this
 * one is dismissible rather than persistent.
 *
 * Callable from both the foreground app (MainActivity) and the headless
 * background engine (BleForegroundService.bootHeadlessEngineIfNeeded) —
 * both register a MethodChannel handler that calls into this object, so
 * alarms notify the same way whether or not the app is in the foreground.
 */
object AlarmNotifications {
    private const val CHANNEL_ID = "boat_alarms"

    fun post(context: Context, id: Int, title: String, text: String) {
        createChannelIfNeeded(context)
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pendingIntent = PendingIntent.getActivity(
            context,
            id,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(id, notification)
    }

    fun cancel(context: Context, id: Int) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(id)
    }

    private fun createChannelIfNeeded(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager?.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Boat alarms",
                    NotificationManager.IMPORTANCE_HIGH
                )
                channel.description =
                    "Warnings when a tank, temperature or other monitored value crosses its alarm threshold"
                manager?.createNotificationChannel(channel)
            }
        }
    }
}
