import 'package:flutter/services.dart';

/// Posts/cancels the Android notification for an active alarm.
///
/// Reuses the exact same native mechanism as the gateway connect/disconnect
/// notification — `NotificationCompat`/`NotificationManager` in
/// `AlarmNotifications.kt`, invoked over the same
/// `"com.example.ble_application/ble_service"` MethodChannel already used
/// for `startWatching`/`stopWatching` — rather than a separate plugin. That
/// channel is registered on both the foreground engine (MainActivity) and
/// the headless background BLE isolate (BleForegroundService), so this
/// works the same way whether or not the app is in the foreground.
/// [requestPermission] should be called once, up front, from the
/// foreground app (see [BleGatewayApp]) rather than relying on
/// `startWatching`'s own request — that only fires once a real gateway is
/// connected, which never happens for a Demo Mode-only session.
class AlarmNotificationService {
  static const _channel = MethodChannel('com.example.ble_application/ble_service');

  /// No native-side setup needed — the channel creates its notification
  /// channel lazily on first use, same as the connection-status one does.
  /// Kept as a method (rather than removed) so callers don't need to know
  /// that, matching AppDependencies.standard()'s init-then-use pattern for
  /// its other services.
  Future<void> init() async {}

  /// Requests `POST_NOTIFICATIONS` if not already granted/denied — a no-op
  /// on Android <13 or once the user has already answered once. Must be
  /// called from the foreground app (needs an Activity); silently no-ops
  /// elsewhere (desktop, the headless background isolate, tests).
  Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (_) {
      // No-op — see doc comment above.
    }
  }

  /// Never throws — a failed notification must not break alarm evaluation
  /// or telemetry processing, which run on the same call chain (see
  /// AlarmMonitorService._onTriggered). Also silently no-ops on platforms
  /// with no native handler for this channel (desktop, tests).
  Future<void> notify({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await _channel.invokeMethod('postAlarmNotification', {
        'id': id,
        'title': title,
        'text': body,
      });
    } catch (_) {
      // No-op — see doc comment above.
    }
  }

  /// Never throws — see [notify].
  Future<void> cancel(int id) async {
    try {
      await _channel.invokeMethod('cancelAlarmNotification', {'id': id});
    } catch (_) {
      // No-op — see doc comment above.
    }
  }
}
