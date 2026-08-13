import 'dart:async';

import 'package:flutter/foundation.dart';

import '../controllers/ble_controller.dart';

/// The boat's current operating state, as classified from live telemetry.
///
/// Anchored and Docked aren't distinguishable from telemetry alone (there's
/// no shore-power/dock-sensor data yet) — both collapse to [stationary].
/// Callers that auto-switch dashboards should match [stationary] against a
/// layout tagged either `anchored` or `docked`.
enum DashboardAutoState { motoring, sailing, stationary }

/// Polls [telemetryController] and classifies the boat's state for optional
/// dashboard auto-switching (see Settings → Dashboard switching).
///
/// Classification is debounced: a new state must be observed consistently
/// for [stableFor] before [detectedState] changes, so a momentary RPM blip
/// or GPS noise doesn't flip dashboards back and forth.
class AutoModeDetector extends ChangeNotifier {
  AutoModeDetector({
    required BleController telemetryController,
    Duration pollInterval = const Duration(seconds: 3),
    Duration stableFor = const Duration(seconds: 6),
  })  : _telemetryController = telemetryController,
        _stablePolls =
            (stableFor.inMilliseconds / pollInterval.inMilliseconds).ceil() {
    _timer = Timer.periodic(pollInterval, (_) => _poll());
  }

  /// Engine considered "running" above this RPM.
  static const double _engineRunningRpm = 400;

  /// Boat considered "moving" above this speed (~1.5 kn).
  static const double _movingSogMs = 1.5 / 1.94384;

  final BleController _telemetryController;
  final int _stablePolls;
  Timer? _timer;

  DashboardAutoState? _pendingState;
  int _pendingCount = 0;

  DashboardAutoState? _detectedState;

  /// The last stably-classified state, or null if nothing has stabilized
  /// yet (e.g. no navigation device on the bus, so speed is unknown).
  DashboardAutoState? get detectedState => _detectedState;

  /// Runs one classification pass immediately, bypassing [pollInterval].
  /// Exposed only so tests can drive classification deterministically
  /// instead of racing a real [Timer].
  @visibleForTesting
  void debugPoll() => _poll();

  void _poll() {
    final raw = _classify();
    if (raw == null) return; // not enough data yet — keep the last detection

    if (_pendingState == raw) {
      _pendingCount++;
    } else {
      _pendingState = raw;
      _pendingCount = 1;
    }

    if (_pendingCount < _stablePolls) return;
    if (_detectedState == raw) return;

    _detectedState = raw;
    notifyListeners();
  }

  DashboardAutoState? _classify() {
    for (final device in _telemetryController.decodedDevices) {
      if (!device.isEngineDevice) continue;
      final rpm = _telemetryController.telemetryFor(device.src).engineRpm;
      if (rpm != null && rpm >= _engineRunningRpm) {
        return DashboardAutoState.motoring;
      }
    }

    final sog = _telemetryController.telemetry.sogMs;
    if (sog == null) return null; // no speed source — can't tell moving vs not
    return sog >= _movingSogMs
        ? DashboardAutoState.sailing
        : DashboardAutoState.stationary;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
