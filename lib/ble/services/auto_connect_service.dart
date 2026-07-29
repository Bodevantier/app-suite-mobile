import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_background_service.dart';
import 'ble_gateway_transport.dart';

/// Watches the transport and automatically reconnects to the known gateway
/// whenever BLE is powered on — in the foreground, on a periodic retry while
/// backgrounded (kept alive on Android by [BleBackgroundService]), and every
/// time the app returns to the foreground.
///
/// NOTE: an earlier version of this also armed Android's native
/// autoConnect:true as a second, passive reconnect path running alongside
/// this one. That created two independent GATT connections to the same
/// device racing each other (duplicate subscriptions, corrupted/duplicated
/// notification data, connections that wouldn't fully tear down on
/// Disconnect). Removed — this is the single, exclusive reconnect path.
///
/// Call [start] once after [knownDeviceId] is available.
/// Call [dispose] when the owning widget/service is torn down.
class AutoConnectService extends ChangeNotifier {
  AutoConnectService({required this.transport});

  final BleGatewayTransportService transport;

  // Retried periodically (not just on transport changes) so a background
  // watch — kept alive by the Android foreground service — keeps trying
  // even when nothing else nudges it, e.g. while the app is minimized and
  // the gateway hasn't come back into range yet.
  static const _retryInterval = Duration(seconds: 20);
  static const _directConnectTimeout = Duration(seconds: 6);
  static const _scanFallbackTimeout = Duration(seconds: 6);

  String? _knownDeviceId;
  bool _running = false;
  bool _attemptInProgress = false;
  String _status = '';
  Timer? _retryTimer;

  bool get isRunning => _running;
  String get status => _status;

  /// Start auto-connect for [deviceId]. Safe to call multiple times —
  /// does nothing if already watching the same device (use [retryNow] to
  /// force an immediate attempt on an already-running watch).
  void start(String deviceId) {
    if (_running && _knownDeviceId == deviceId) return;
    _knownDeviceId = deviceId;
    _running = true;
    transport.addListener(_onTransportChanged);
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(_retryInterval, (_) => _onTransportChanged());
    unawaited(
      BleBackgroundService.startWatching(
        title: 'SDolve',
        text: 'Watching for gateway…',
        deviceId: deviceId,
      ),
    );
    _onTransportChanged();
  }

  /// Forces an immediate reconnect attempt on an already-running watch.
  /// Used when the app returns to the foreground — [start] is a no-op in
  /// that case since the watch is already active for the same device.
  void retryNow() {
    if (!_running) return;
    _onTransportChanged();
  }

  /// Stops watching but keeps [knownDeviceId] remembered — used by an
  /// explicit user Disconnect/Cancel. Auto-connect resumes on the next
  /// [start] call (app resume/relaunch) or manual reconnect, but will NOT
  /// immediately fight the user's choice by reconnecting on its own, the
  /// way [_onTransportChanged] would otherwise do the instant the transport
  /// reports "not connected".
  void pause() {
    _running = false;
    transport.removeListener(_onTransportChanged);
    _retryTimer?.cancel();
    _retryTimer = null;
    _status = '';
    notifyListeners();
    unawaited(BleBackgroundService.stopWatching());
  }

  /// Stops watching AND forgets the device — used by Forget.
  void stop() {
    pause();
    _knownDeviceId = null;
  }

  void _onTransportChanged() {
    if (!_running) return;
    if (transport.isConnected || transport.isConnecting || _attemptInProgress) {
      return;
    }
    unawaited(_tryConnect());
  }

  Future<void> _tryConnect() async {
    final deviceId = _knownDeviceId;
    if (deviceId == null || !_running) return;
    if (transport.isConnected || transport.isConnecting) return;

    _attemptInProgress = true;
    _status = 'Connecting to gateway...';
    notifyListeners();

    try {
      await transport.ensureInitialized();

      // Check BLE availability first. Wait briefly if still initialising.
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        try {
          await FlutterBluePlus.adapterState
              .firstWhere((s) => s == BluetoothAdapterState.on)
              .timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
      final adapterState = FlutterBluePlus.adapterStateNow;
      if (adapterState != BluetoothAdapterState.on) {
        _status = 'Bluetooth ${adapterState.name} — waiting...';
        notifyListeners();
        _attemptInProgress = false;
        return;
      }

      // Wait for any previous disconnect's native teardown FIRST, unbounded
      // — Android can take many seconds here. This must happen before the
      // timeout below starts, not during it: if the 6s timeout fired while
      // this wait was still pending inside connectKnown(), it would abandon
      // (without cancelling — Dart futures can't be cancelled) that call,
      // which would keep running in the background and eventually issue
      // its own connect(), racing the scan-fallback attempt below. That
      // race was the actual cause of connects that intermittently
      // succeeded and then immediately got cancelled again.
      await transport.waitForPendingDisconnect();

      if (!_running) {
        _attemptInProgress = false;
        return;
      }

      // Fast path: connect straight to the known device by id, no scan.
      // This is what makes reconnects feel instant once the gateway has
      // been seen before — it's only when that fails (e.g. right after a
      // phone reboot, before the OS has cached the peripheral) that we
      // fall back to scanning below.
      try {
        await transport.connectKnown(deviceId).timeout(_directConnectTimeout);
      } catch (_) {}

      if (!_running) {
        // Told to pause/stop while this attempt was in flight — if it raced
        // to a successful connect anyway, tear it back down rather than
        // leaving a live connection behind a UI that says "disconnected".
        if (transport.isConnected) unawaited(transport.disconnect());
        _attemptInProgress = false;
        return;
      }
      if (transport.isConnected) {
        _status = 'Connected';
        _attemptInProgress = false;
        notifyListeners();
        unawaited(
          BleBackgroundService.startWatching(
            title: 'SDolve',
            text: 'Connected to gateway',
            deviceId: deviceId,
          ),
        );
        return;
      }

      // Fallback: scan, connecting the instant the known device is seen
      // instead of always waiting out a fixed window.
      await transport.startScan();
      final target = await _waitForKnownDevice(deviceId, _scanFallbackTimeout);
      await transport.stopScan();

      if (!_running) {
        _attemptInProgress = false;
        return;
      }

      // Re-check: user may have manually connected during the scan.
      if (transport.isConnected) {
        _status = 'Connected';
        _attemptInProgress = false;
        notifyListeners();
        unawaited(
          BleBackgroundService.startWatching(
            title: 'SDolve',
            text: 'Connected to gateway',
            deviceId: deviceId,
          ),
        );
        return;
      }

      if (target == null) {
        _status = 'Gateway not found nearby';
        notifyListeners();
        _attemptInProgress = false;
        return;
      }

      await transport.connect(target);

      if (!_running) {
        // Same race as above, for the scan-fallback connect path.
        if (transport.isConnected) unawaited(transport.disconnect());
        _attemptInProgress = false;
        return;
      }

      _status = transport.isConnected ? 'Connected' : transport.status;
      if (transport.isConnected) {
        unawaited(
          BleBackgroundService.startWatching(
            title: 'SDolve',
            text: 'Connected to gateway',
            deviceId: deviceId,
          ),
        );
      }
    } catch (error) {
      _status = 'Auto-connect failed: $error';
    } finally {
      _attemptInProgress = false;
      notifyListeners();
    }
  }

  /// Polls scan results for [deviceId], returning as soon as it's seen
  /// instead of always waiting out the full [timeout].
  Future<ScanResult?> _waitForKnownDevice(
    String deviceId,
    Duration timeout,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!_running) return null;
      final match = transport.devices
          .where((d) => d.device.remoteId.str == deviceId)
          .firstOrNull;
      if (match != null) return match;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return transport.devices
        .where((d) => d.device.remoteId.str == deviceId)
        .firstOrNull;
  }

  @override
  void dispose() {
    transport.removeListener(_onTransportChanged);
    _retryTimer?.cancel();
    super.dispose();
  }
}
