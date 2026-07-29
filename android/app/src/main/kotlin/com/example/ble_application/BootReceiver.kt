package com.example.ble_application

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Re-registers the background BLE scan after a phone reboot — the scan
 * registration itself does not survive the Bluetooth stack resetting.
 *
 * Reads the known gateway id directly from the same SharedPreferences file
 * the Dart `shared_preferences` plugin's `getInstance()` API writes to:
 * file "FlutterSharedPreferences", keys prefixed "flutter." (confirmed
 * against the installed shared_preferences_android/LegacySharedPreferences
 * Plugin source — this is the classic-API storage path, distinct from the
 * newer DataStore-backed async API which this app does not use). See
 * AppPreferencesService.knownGatewayId for the Dart-side reader.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val deviceId = prefs.getString("flutter.known_gateway_id", null) ?: return
        BleBackgroundScan.register(context, deviceId)
    }
}
