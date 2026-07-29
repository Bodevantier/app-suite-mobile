package com.example.ble_application

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Registers/cancels a system-level BLE scan for the known gateway's MAC
 * address, delivered via [PendingIntent] rather than a live callback object.
 * Unlike a normal (foreground, callback-based) scan, this survives our app
 * process being killed — Android itself wakes [BleScanReceiver] when a
 * matching advertisement is seen, even from a cold start with no process
 * running at all. It does NOT survive the user explicitly Force Stopping
 * the app from Settings; no Android app can survive that, by design.
 *
 * The registration itself does not survive a phone reboot (the Bluetooth
 * stack resets) — [BootReceiver] re-registers it on
 * `android.intent.action.BOOT_COMPLETED`.
 */
object BleBackgroundScan {
    private const val TAG = "BleBackgroundScan"
    private const val REQUEST_CODE = 4177

    @SuppressLint("MissingPermission")
    fun register(context: Context, deviceId: String) {
        try {
            val manager =
                context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val scanner = manager?.adapter?.bluetoothLeScanner ?: return
            val filter = ScanFilter.Builder().setDeviceAddress(deviceId).build()
            val settings =
                ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_POWER).build()
            scanner.startScan(listOf(filter), settings, pendingIntent(context))
        } catch (e: Exception) {
            Log.w(TAG, "Failed to register background scan", e)
        }
    }

    @SuppressLint("MissingPermission")
    fun unregister(context: Context) {
        try {
            val manager =
                context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val scanner = manager?.adapter?.bluetoothLeScanner ?: return
            scanner.stopScan(pendingIntent(context))
        } catch (e: Exception) {
            Log.w(TAG, "Failed to unregister background scan", e)
        }
    }

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, BleScanReceiver::class.java)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE
            } else {
                0
            })
        // Must be mutable (API 31+) — the system needs to attach the scan
        // result extras to this intent when it fires.
        return PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
    }
}
