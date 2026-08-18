package com.example.ble_application

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Keeps the app process alive with a low-priority ongoing notification while
 * [AutoConnectService] (Dart side) is watching for or connected to the BLE
 * gateway. Without this, Android is free to kill the process shortly after
 * the app is backgrounded, which drops the GATT connection immediately.
 *
 * Started/stopped from Dart via the "com.example.ble_application/ble_service"
 * MethodChannel registered in [MainActivity]. Every start call rebuilds and
 * reposts the same notification id, so updating the text (e.g. "Watching..."
 * -> "Connected") never creates a duplicate.
 *
 * Also handles [ACTION_DEVICE_DETECTED], fired by [BleScanReceiver] when the
 * OS wakes the app for the known gateway's advertisement while the app
 * process isn't running at all (not just backgrounded) — see
 * [BleBackgroundScan]. In that case there is no running Dart isolate yet, so
 * this boots one headlessly (see [bootHeadlessEngineIfNeeded]) running the
 * exact same Dart connect logic ([AutoConnectService]) used everywhere else
 * in the app, rather than a second, separate native connection path.
 */
class BleForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "ble_gateway_connection"
        const val NOTIFICATION_ID = 1001
        const val EXTRA_TITLE = "extra_title"
        const val EXTRA_TEXT = "extra_text"
        const val ACTION_DEVICE_DETECTED =
            "com.example.ble_application.ACTION_DEVICE_DETECTED"
        const val HEADLESS_ENGINE_ID = "ble_background_connect_engine"
        private const val TAG = "BleForegroundService"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // startForeground() with foregroundServiceType="connectedDevice" throws
        // (SecurityException / ForegroundServiceStartNotAllowedException) on
        // Android 14+ if BLUETOOTH_CONNECT/BLUETOOTH_SCAN isn't already granted
        // at this exact moment — which is possible here since this can be
        // triggered by AutoConnectService.start() on app launch for a
        // previously-known gateway, ahead of the BLE permission prompt that
        // flutter_blue_plus only requests once an actual scan/connect is
        // attempted. Left uncaught this took the whole app down; failing to
        // start this best-effort background watch is fine — the app still
        // reconnects and requests BLE permissions normally once it's open.
        try {
            if (intent?.action == ACTION_DEVICE_DETECTED) {
                startForeground(
                    NOTIFICATION_ID,
                    buildNotification("SDolve", "Gateway detected — connecting…")
                )
                bootHeadlessEngineIfNeeded()
                return START_STICKY
            }
            val title = intent?.getStringExtra(EXTRA_TITLE) ?: "SDolve"
            val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Watching for gateway"
            startForeground(NOTIFICATION_ID, buildNotification(title, text))
            return START_STICKY
        } catch (e: Exception) {
            Log.w(TAG, "startForeground failed — BLE permission not granted yet?", e)
            stopSelf()
            return START_NOT_STICKY
        }
    }

    /**
     * Boots a headless [FlutterEngine] running `backgroundConnectMain` (see
     * lib/main.dart) — deliberately NOT the default `main` entrypoint, which
     * calls `runApp()` and would leave a splash-screen widget tree stuck
     * forever with no attached view to drive its animation. This engine is
     * cached under [HEADLESS_ENGINE_ID] so [MainActivity] can find and
     * destroy it (releasing its BLE connection) before starting its own,
     * the moment the user actually opens the app — see
     * `MainActivity.provideFlutterEngine`.
     */
    private fun bootHeadlessEngineIfNeeded() {
        if (FlutterEngineCache.getInstance().get(HEADLESS_ENGINE_ID) != null) {
            return // already running from an earlier detection
        }
        val loader = FlutterInjector.instance().flutterLoader()
        val mainHandler = Handler(Looper.getMainLooper())
        mainHandler.post {
            try {
                loader.startInitialization(applicationContext)
                loader.ensureInitializationCompleteAsync(
                    applicationContext,
                    null,
                    mainHandler
                ) {
                    if (FlutterEngineCache.getInstance().get(HEADLESS_ENGINE_ID) != null) {
                        return@ensureInitializationCompleteAsync
                    }
                    val engine = FlutterEngine(applicationContext)
                    val entrypoint = DartExecutor.DartEntrypoint(
                        loader.findAppBundlePath(),
                        "backgroundConnectMain"
                    )
                    engine.dartExecutor.executeDartEntrypoint(entrypoint)
                    FlutterEngineCache.getInstance().put(HEADLESS_ENGINE_ID, engine)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to boot headless connect engine", e)
            }
        }
    }

    private fun buildNotification(title: String, text: String): Notification {
        createChannelIfNeeded()
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun createChannelIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            if (manager?.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Gateway connection",
                    NotificationManager.IMPORTANCE_LOW
                )
                channel.description =
                    "Shows while the app is watching for or connected to the BLE gateway"
                manager?.createNotificationChannel(channel)
            }
        }
    }
}
