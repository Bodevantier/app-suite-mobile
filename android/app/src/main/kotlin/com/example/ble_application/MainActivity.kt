package com.example.ble_application

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.ble_application/ble_service"

    /**
     * Runs before our own engine is created and starts connecting. If a
     * headless background-connect engine (see BleForegroundService /
     * BleScanReceiver) is already running — e.g. it woke up and connected
     * while the app was fully closed — destroy it first. Otherwise it and
     * our new UI engine would race to open a second GATT connection to the
     * same device, the same duplicate-connection bug fixed earlier in the
     * Dart auto-connect logic. Our own engine's normal reconnect is fast
     * (a few seconds), so trading a live handoff for this simpler, safer
     * teardown-then-reconnect is a good trade.
     */
    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        val cached = FlutterEngineCache.getInstance().get(BleForegroundService.HEADLESS_ENGINE_ID)
        if (cached != null) {
            FlutterEngineCache.getInstance().remove(BleForegroundService.HEADLESS_ENGINE_ID)
            cached.destroy()
        }
        return super.provideFlutterEngine(context)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startWatching" -> {
                        requestNotificationPermissionIfNeeded()
                        val title = call.argument<String>("title") ?: "SDolve"
                        val text = call.argument<String>("text") ?: "Watching for gateway"
                        val deviceId = call.argument<String>("deviceId")
                        val intent = Intent(this, BleForegroundService::class.java).apply {
                            putExtra(BleForegroundService.EXTRA_TITLE, title)
                            putExtra(BleForegroundService.EXTRA_TEXT, text)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        if (deviceId != null) {
                            BleBackgroundScan.register(applicationContext, deviceId)
                        }
                        result.success(null)
                    }
                    "stopWatching" -> {
                        stopService(Intent(this, BleForegroundService::class.java))
                        BleBackgroundScan.unregister(applicationContext)
                        result.success(null)
                    }
                    // Whether the app can reliably wake in the background when
                    // fully closed: without this OS exemption, a detected
                    // gateway only shows a plain notification (BleScanReceiver
                    // can't start the foreground service that does the actual
                    // connect — see its class doc for why).
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                        result.success(pm?.isIgnoringBatteryOptimizations(packageName) ?: true)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        try {
                            val intent = Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                        } catch (e: Exception) {
                            // Some OEM ROMs don't implement this action; nothing
                            // more we can do, the user can grant it manually.
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                1001
            )
        }
    }
}
