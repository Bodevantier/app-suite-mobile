import 'package:flutter/foundation.dart';

import '../controllers/ble_controller.dart';
import '../models/n2k_device_info.dart';
import '../models/node_settings.dart';
import '../n2k/n2k_liveness.dart';
import 'alarm_notification_service.dart';
import 'incident_log_service.dart';
import 'node_settings_service.dart';

enum AlarmKind { tankLow, tankHigh, tempHigh, tempLow }

/// A tank alarm needs to rise/fall this many percentage points past its
/// threshold before clearing, and a temperature alarm this many degrees —
/// otherwise a reading hovering right at the threshold (a sloshing tank, a
/// borderline engine-bay temp) would flap the alarm on and off repeatedly.
/// Fixed constants rather than a user-facing setting, to keep the alarm UI
/// simple.
const double _tankLevelHysteresisPct = 5.0;
const double _tempHysteresisC = 1.0;

/// Single shared source of truth for "is this device's alarm currently
/// active", replacing three independent inline threshold checks that used
/// to live in the devices list, tank detail, and temperature detail pages.
///
/// Runs off live telemetry and reacts to alarm-setting changes, in both the
/// foreground app and the headless background BLE isolate (constructed the
/// same way in both — see AppDependencies.standard()). Every trigger/clear
/// transition is recorded to [IncidentLogService] and posted/cancelled via
/// [AlarmNotificationService].
class AlarmMonitorService extends ChangeNotifier {
  AlarmMonitorService({
    required this.telemetryController,
    required this.nodeSettings,
    required this.incidentLog,
    required this.notifications,
  }) {
    telemetryController.addListener(_recheckAll);
    nodeSettings.addListener(_recheckAll);
  }

  final BleController telemetryController;
  final NodeSettingsService nodeSettings;
  final IncidentLogService incidentLog;
  final AlarmNotificationService notifications;

  final Map<String, bool> _active = <String, bool>{};

  bool isActive(N2kDeviceInfo device, AlarmKind kind) =>
      _active[_key(device, kind)] ?? false;

  bool isDeviceAlarmActive(N2kDeviceInfo device) =>
      AlarmKind.values.any((kind) => isActive(device, kind));

  String _key(N2kDeviceInfo device, AlarmKind kind) =>
      '${nodeSettingsKey(device)}:${kind.name}';

  int _notificationId(N2kDeviceInfo device, AlarmKind kind) =>
      Object.hash(nodeSettingsKey(device), kind) & 0x7fffffff;

  void _recheckAll() {
    var changed = false;
    for (final device in telemetryController.decodedDevices) {
      // Freeze state while stale rather than auto-clearing — losing sensor
      // contact shouldn't silently wave off a real alarm.
      if (!isDeviceLive(device)) continue;

      final settings = nodeSettings.forDevice(device);
      final telemetry = telemetryController.telemetryFor(device.sourceAddress);

      if (device.isFluidLevelDevice) {
        final level = telemetry.fluidLevelPct;
        if (level != null) {
          changed |= _evaluate(
            device,
            AlarmKind.tankLow,
            enabled: settings.lowLevelAlarmEnabled,
            value: level,
            threshold: settings.lowLevelAlarmPct,
            band: _tankLevelHysteresisPct,
            highSide: false,
            unit: '%',
            label: 'Low tank level',
          );
          changed |= _evaluate(
            device,
            AlarmKind.tankHigh,
            enabled: settings.highLevelAlarmEnabled,
            value: level,
            threshold: settings.highLevelAlarmPct,
            band: _tankLevelHysteresisPct,
            highSide: true,
            unit: '%',
            label: 'High tank level',
          );
        }
      }

      if (device.isTemperatureDevice) {
        final tempC = telemetry.temperatureC;
        if (tempC != null) {
          changed |= _evaluate(
            device,
            AlarmKind.tempHigh,
            enabled: settings.highTempAlarmEnabled,
            value: tempC,
            threshold: settings.highTempAlarmC,
            band: _tempHysteresisC,
            highSide: true,
            unit: '°C',
            label: 'High temperature',
          );
          changed |= _evaluate(
            device,
            AlarmKind.tempLow,
            enabled: settings.lowTempAlarmEnabled,
            value: tempC,
            threshold: settings.lowTempAlarmC,
            band: _tempHysteresisC,
            highSide: false,
            unit: '°C',
            label: 'Low temperature',
          );
        }
      }
    }
    if (changed) notifyListeners();
  }

  /// Evaluates one (device, kind) alarm with hysteresis, updates internal
  /// state, and fires the incident-log/notification side effects on a
  /// trigger or clear transition. Returns true if this alarm's active state
  /// changed.
  bool _evaluate(
    N2kDeviceInfo device,
    AlarmKind kind, {
    required bool enabled,
    required double value,
    required double threshold,
    required double band,
    required bool highSide,
    required String unit,
    required String label,
  }) {
    final key = _key(device, kind);
    final wasActive = _active[key] ?? false;

    if (!enabled) {
      if (!wasActive) return false;
      _active[key] = false;
      _onCleared(device, kind, label, value, threshold, unit);
      return true;
    }

    final nowActive = highSide
        ? (wasActive ? value > threshold - band : value >= threshold)
        : (wasActive ? value < threshold + band : value <= threshold);

    if (nowActive == wasActive) return false;
    _active[key] = nowActive;
    if (nowActive) {
      _onTriggered(device, kind, label, value, threshold, unit);
    } else {
      _onCleared(device, kind, label, value, threshold, unit);
    }
    return true;
  }

  void _onTriggered(
    N2kDeviceInfo device,
    AlarmKind kind,
    String label,
    double value,
    double threshold,
    String unit,
  ) {
    final name = device.displayName;
    incidentLog.record(IncidentLogEntry(
      time: DateTime.now(),
      deviceKey: nodeSettingsKey(device),
      deviceName: name,
      alarmLabel: label,
      isTrigger: true,
      value: value,
      threshold: threshold,
      unit: unit,
    ));
    notifications.notify(
      id: _notificationId(device, kind),
      title: name,
      body: '$label — ${value.toStringAsFixed(1)}$unit '
          '(threshold ${threshold.toStringAsFixed(1)}$unit)',
    );
  }

  void _onCleared(
    N2kDeviceInfo device,
    AlarmKind kind,
    String label,
    double value,
    double threshold,
    String unit,
  ) {
    final name = device.displayName;
    incidentLog.record(IncidentLogEntry(
      time: DateTime.now(),
      deviceKey: nodeSettingsKey(device),
      deviceName: name,
      alarmLabel: label,
      isTrigger: false,
      value: value,
      threshold: threshold,
      unit: unit,
    ));
    notifications.cancel(_notificationId(device, kind));
  }

  @override
  void dispose() {
    telemetryController.removeListener(_recheckAll);
    nodeSettings.removeListener(_recheckAll);
    super.dispose();
  }
}
