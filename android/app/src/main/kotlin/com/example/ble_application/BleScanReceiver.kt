package com.example.ble_application

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.bluetooth.le.BluetoothLeScanner
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Fired by the OS (via the [PendingIntent] registered in [BleBackgroundScan])
 * when the known gateway's advertisement is seen — including when this
 * app's process isn't running at all. Starts [BleForegroundService], which
 * boots a headless Flutter engine to actually establish the connection,
 * reusing the exact same, already-hardened Dart connect logic used
 * everywhere else in the app rather than a second native connection path.
 *
 * IMPORTANT: Android 12+ does NOT allow starting a foreground service from
 * a background broadcast receiver unless the app holds a specific
 * documented exemption (confirmed against developer.android.com — a BLE
 * scan PendingIntent broadcast is NOT itself one of them). The one relevant
 * exemption here is "the user has disabled battery optimization for the
 * app" (see [BatteryOptimization]) — without it, [ForegroundServiceStart
 * NotAllowedException] is thrown. We check for the exemption first and, if
 * it isn't granted, fall back to a plain (non-foreground) notification
 * instead of crashing — the user opening the app manually still works and
 * is fast.
 */
class BleScanReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val errorCode = intent.getIntExtra(BluetoothLeScanner.EXTRA_ERROR_CODE, -1)
        if (errorCode != -1) return

        val hasExemption = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            isIgnoringBatteryOptimizations(context)

        if (!hasExemption) {
            postFallbackNotification(context)
            return
        }

        val serviceIntent = Intent(context, BleForegroundService::class.java).apply {
            action = BleForegroundService.ACTION_DEVICE_DETECTED
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(context, serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (e: Exception) {
            // Belt-and-braces: some OEM ROMs impose additional restrictions
            // beyond stock Android even when the documented exemption is
            // met. Never let this crash the receiver.
            postFallbackNotification(context)
        }
    }

    private fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        return pm?.isIgnoringBatteryOptimizations(context.packageName) ?: false
    }

    private fun postFallbackNotification(context: Context) {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                BleForegroundService.CHANNEL_ID,
                "Gateway connection",
                NotificationManager.IMPORTANCE_LOW
            )
            manager?.createNotificationChannel(channel)
        }
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val notification = NotificationCompat.Builder(context, BleForegroundService.CHANNEL_ID)
            .setContentTitle("SDolve")
            .setContentText("Gateway detected — open the app to connect")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()
        manager?.notify(BleForegroundService.NOTIFICATION_ID, notification)
    }
}
