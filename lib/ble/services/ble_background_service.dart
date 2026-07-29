import 'dart:io';

import 'package:flutter/services.dart';

/// Thin wrapper around the Android foreground service ([BleForegroundService]
/// in the native project) that keeps the app process alive — with a
/// persistent low-priority notification — while auto-connect is watching for
/// or connected to the gateway. Without this, Android is free to kill the
/// process as soon as the app is backgrounded, which is why the BLE
/// connection previously never survived closing the app.
///
/// No-op on iOS/other platforms: iOS has no app-controlled foreground-service
/// concept. Its background reconnect story is handled separately via
/// CoreBluetooth state restoration (see `FlutterBluePlus.setOptions
/// (restoreState: true)` at app startup) and the `bluetooth-central`
/// UIBackgroundMode.
class BleBackgroundService {
  static const _channel =
      MethodChannel('com.example.ble_application/ble_service');

  /// Starts (or updates the notification text of) the background watch, and
  /// registers a system-level BLE scan filter for [deviceId] so Android can
  /// wake the app (via [BleScanReceiver]) when the gateway is seen again
  /// even if the app process isn't running at all — not just backgrounded.
  static Future<void> startWatching({
    required String title,
    required String text,
    required String deviceId,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('startWatching', {
        'title': title,
        'text': text,
        'deviceId': deviceId,
      });
    } catch (_) {
      // Best-effort — the app still works without the foreground service,
      // it just won't reliably survive backgrounding.
    }
  }

  /// Stops the foreground service AND cancels the system-level BLE scan
  /// registration — called on explicit Disconnect/Forget so we don't keep
  /// watching for (or waking the app up for) a device the user isn't
  /// interested in anymore.
  static Future<void> stopWatching() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopWatching');
    } catch (_) {}
  }

  /// Whether the app currently holds the one OS exemption that lets it
  /// start its foreground service (and actually connect) when Android wakes
  /// it for the known gateway while the app is fully closed. Without this,
  /// a detected gateway only shows a plain "open the app to connect"
  /// notification — confirmed against Android's own documented list of
  /// foreground-service background-start exemptions, which does not include
  /// BLE scan results. True (harmless default) on iOS/other platforms,
  /// where this concept doesn't apply and the UI prompt should stay hidden.
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Opens the system dialog that lets the user grant that exemption.
  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }
}
