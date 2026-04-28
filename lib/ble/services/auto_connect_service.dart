import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_gateway_transport.dart';

/// Watches the transport and automatically reconnects to the known gateway
/// whenever the app is in the foreground and BLE is powered on.
///
/// Call [start] once after [knownDeviceId] is available.
/// Call [dispose] when the owning widget/service is torn down.
class AutoConnectService extends ChangeNotifier {
  AutoConnectService({required this.transport});

  final BleGatewayTransportService transport;

  String? _knownDeviceId;
  bool _running = false;
  bool _attemptInProgress = false;
  String _status = '';

  bool get isRunning => _running;
  String get status => _status;

  /// Start auto-connect for [deviceId]. Safe to call multiple times —
  /// does nothing if already watching the same device.
  void start(String deviceId) {
    if (_running && _knownDeviceId == deviceId) return;
    _knownDeviceId = deviceId;
    _running = true;
    transport.addListener(_onTransportChanged);
    _onTransportChanged();
  }

  void stop() {
    _running = false;
    transport.removeListener(_onTransportChanged);
    _knownDeviceId = null;
    _status = '';
    notifyListeners();
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

      // Start a brief scan to discover the known device.
      await transport.startScan();
      await Future<void>.delayed(const Duration(seconds: 4));
      await transport.stopScan();

      if (!_running) {
        _attemptInProgress = false;
        return;
      }

      // Re-check: user may have manually connected during the scan delay.
      if (transport.isConnected) {
        _status = 'Connected';
        _attemptInProgress = false;
        notifyListeners();
        return;
      }

      // Look for the known device in what was discovered.
      final discovered = transport.devices;
      final target =
          discovered.where((d) => d.device.remoteId.str == deviceId).firstOrNull;

      if (target == null) {
        _status = 'Gateway not found nearby';
        notifyListeners();
        _attemptInProgress = false;
        return;
      }

      await transport.connect(target);
      _status = transport.isConnected ? 'Connected' : transport.status;
    } catch (error) {
      _status = 'Auto-connect failed: $error';
    } finally {
      _attemptInProgress = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    transport.removeListener(_onTransportChanged);
    super.dispose();
  }
}
