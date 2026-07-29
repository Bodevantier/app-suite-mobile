import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

@visibleForTesting
bool isTransientBleConnectError(Object error) {
  final message = '$error'.toLowerCase();
  // Android GATT error 133 (ANDROID_SPECIFIC_ERROR) is a transient
  // error that almost always succeeds on the next attempt.
  return message.contains('133') || message.contains('android_specific_error');
}

@visibleForTesting
bool isBleGatewayCandidate(ScanResult result, {required String serviceUuid}) {
  final target = Guid(serviceUuid);
  if (result.advertisementData.serviceUuids.contains(target)) {
    return true;
  }
  final rawName = (result.advertisementData.advName.isNotEmpty
          ? result.advertisementData.advName
          : result.device.platformName)
      .trim()
      .toLowerCase();
  if (rawName.isEmpty) return false;
  return rawName.startsWith('sdolve') ||
      rawName.contains('n2k ble') ||
      rawName.contains('ble gateway');
}

class BleTransportChunk {
  const BleTransportChunk({
    required this.bytes,
    required this.source,
    required this.isBinary,
  });

  final List<int> bytes;
  final String source;
  final bool isBinary;
}

class BleGatewayTransportService extends ChangeNotifier {
  BleGatewayTransportService({
    required this.gatewayServiceUuid,
    required this.notifyCharacteristicUuid,
    required this.binaryNotifyCharacteristicUuid,
    required this.commandCharacteristicUuid,
  });

  final String gatewayServiceUuid;
  final String notifyCharacteristicUuid;
  final String binaryNotifyCharacteristicUuid;
  final String commandCharacteristicUuid;

  var _devices = <ScanResult>[];
  final StreamController<BleTransportChunk> _chunkController =
      StreamController<BleTransportChunk>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<dynamic>? _textNotifySub;
  StreamSubscription<dynamic>? _binaryNotifySub;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _notifyCharacteristic;
  BluetoothCharacteristic? _binaryNotifyCharacteristic;
  BluetoothCharacteristic? _commandCharacteristic;
  bool _initialized = false;
  bool _isConnecting = false;
  String _status = 'Initializing BLE...';
  // Tracks the native BluetoothGatt teardown fired in the background by
  // disconnect() (see there for why it isn't awaited up front). A fresh
  // connect attempt must wait for this to actually finish first — issuing a
  // new connect() while the old GATT client hasn't finished closing is a
  // known cause of very slow/duplicate reconnects on Android.
  Future<void>? _pendingNativeDisconnect;

  List<ScanResult> get devices => List.unmodifiable(_devices);
  BluetoothDevice? get connectedDevice => _connectedDevice;
  bool get isScanning => FlutterBluePlus.isScanningNow;
  bool get isConnecting => _isConnecting;
  bool get isConnected => _connectedDevice != null;
  bool get hasNotifyCharacteristic => _notifyCharacteristic != null;
  bool get hasBinaryNotifyCharacteristic => _binaryNotifyCharacteristic != null;
  bool get hasCommandCharacteristic => _commandCharacteristic != null;
  String get status => _status;
  Stream<BleTransportChunk> get chunks => _chunkController.stream;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    // Retain scan results between scans so the device list stays visible
    // after a scan completes.  onScanResults would clear between scans.
    _scanSub = FlutterBluePlus.scanResults.listen(
      (results) {
        _devices = results.where((r) {
          final name = (r.advertisementData.advName.isNotEmpty
                  ? r.advertisementData.advName
                  : r.device.platformName)
              .trim()
              .toLowerCase();
          return name.contains('sdolve');
        }).toList();
        notifyListeners();
      },
      onError: (Object error) {
        _status = 'Scan error: $error';
        notifyListeners();
      },
    );

    // Rebuild the UI whenever scanning state changes so buttons enable/disable.
    _isScanSub = FlutterBluePlus.isScanning.listen((_) => notifyListeners());

    // Track adapter state so the UI reflects BT on/off/unknown reactively.
    // adapterStateNow may return unknown on startup before Android is ready.
    _adapterStateSub = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        if (!FlutterBluePlus.isScanningNow && _connectedDevice == null) {
          _status = 'Ready. Tap Start scan.';
        }
      } else {
        _status = 'Bluetooth is ${state.name}.';
      }
      notifyListeners();
    });

    // Set initial status based on current adapter state, but treat unknown
    // as 'wait for the stream event' rather than surfacing it as an error.
    final initial = FlutterBluePlus.adapterStateNow;
    _status = initial == BluetoothAdapterState.on
        ? 'Ready. Tap Start scan.'
        : 'Waiting for Bluetooth...';
    notifyListeners();
  }

  Future<void> startScan() async {
    // Wait up to 3 s for the adapter to come on if it is still initialising.
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.adapterState
            .firstWhere((s) => s == BluetoothAdapterState.on)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        // Timed out — adapter is genuinely off.
      }
    }
    final adapterState = FlutterBluePlus.adapterStateNow;
    if (adapterState != BluetoothAdapterState.on) {
      _status = 'Bluetooth is ${adapterState.name}. Please enable Bluetooth.';
      notifyListeners();
      return;
    }

    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
      _status = 'Scanning...';
      notifyListeners();

      // No OS-level service filter: let all devices through so isBleGatewayCandidate
      // can match by name ("sdolve" prefix) as well as by service UUID.
      // withServices would silently drop devices that don't include the UUID
      // in their advertisement packet even if they are valid gateways.
      await FlutterBluePlus.startScan();
    } catch (error) {
      _status = 'Scan failed: $error';
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _status = 'Scan stopped.';
    notifyListeners();
  }

  Future<void> connect(ScanResult result) => _connectDevice(result.device);

  /// Connects directly to a previously-known device by its remoteId, with no
  /// scan step first. Used by [AutoConnectService] so reconnecting (app
  /// launch/resume, or the gateway coming back into range) takes roughly one
  /// GATT-connect's worth of time instead of a multi-second scan window.
  Future<void> connectKnown(String remoteId) =>
      _connectDevice(BluetoothDevice.fromId(remoteId));

  /// Resolves once any in-flight native GATT teardown from a previous
  /// [disconnect] call has actually finished (Android is documented to
  /// sometimes take many seconds here, regardless of what this app does).
  ///
  /// [_connectDevice] already awaits this internally, so correctness never
  /// depends on callers remembering to call it. But callers that themselves
  /// wrap a connect attempt in a short timeout (e.g. AutoConnectService's
  /// bounded fast-path) MUST call this first, unbounded, before starting
  /// that timer — otherwise the timeout can expire while this wait is
  /// still pending inside _connectDevice, abandoning (but NOT cancelling —
  /// Dart futures can't be cancelled) that call, which keeps running in the
  /// background and eventually issues its own connect(), racing whatever
  /// the caller tries next. That race is what caused connects to
  /// intermittently succeed and then immediately get cancelled again.
  Future<void> waitForPendingDisconnect() async {
    final pending = _pendingNativeDisconnect;
    if (pending == null) return;
    _status = 'Finishing previous disconnect...';
    notifyListeners();
    await pending;
    _pendingNativeDisconnect = null;
  }

  Future<void> _connectDevice(BluetoothDevice device) async {
    if (_isConnecting) return;
    const settleDelay = Duration(milliseconds: 350);
    const retryDelay = Duration(milliseconds: 900);

    final deviceName = device.platformName.isNotEmpty
        ? device.platformName
        : device.remoteId.str;

    try {
      _isConnecting = true;
      _status = 'Connecting to $deviceName...';
      notifyListeners();

      await waitForPendingDisconnect();

      await _resetBeforeConnect(device);
      await Future<void>.delayed(settleDelay);

      Object? lastError;
      final maxAttempts =
          defaultTargetPlatform == TargetPlatform.android ? 2 : 1;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          if (attempt > 1) {
            _status = 'Retrying connection to $deviceName...';
            notifyListeners();
          }
          await _connectOnce(device);
          return;
        } catch (error) {
          lastError = error;
          await _resetAfterFailedConnect(device);
          if (attempt >= maxAttempts || !isTransientBleConnectError(error)) {
            break;
          }
          await Future<void>.delayed(retryDelay);
        }
      }

      _isConnecting = false;
      _status = _formatConnectFailure(lastError ?? 'unknown error');
      notifyListeners();
    } catch (error) {
      await _resetAfterFailedConnect(device);
      _isConnecting = false;
      _status = _formatConnectFailure(error);
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    final device = _connectedDevice;
    if (device == null) return;
    // A user-initiated disconnect should feel instant. Cancel our own local
    // stream subscriptions (fast, no BLE I/O) and update state right away —
    // don't wait for Android's own GATT teardown, which is documented to
    // sometimes take many seconds regardless of what the app does, and skip
    // explicitly writing CCCD=0 first (unnecessary once the whole link is
    // being severed, and — now that every characteristic requires
    // encryption — a write that can itself hang for seconds if the link
    // needs to renegotiate security). The native teardown is tracked in
    // _pendingNativeDisconnect so a fresh connect() call waits for it to
    // actually finish instead of racing it — see _connectDevice.
    await _connectionSub?.cancel();
    _connectionSub = null;
    await _textNotifySub?.cancel();
    await _binaryNotifySub?.cancel();
    _textNotifySub = null;
    _binaryNotifySub = null;
    await _handleDisconnectCleanup(autoStatus: 'Disconnected');
    _pendingNativeDisconnect = device.disconnect().catchError((_) {});
  }

  Future<void> shutdown() async {
    try { await FlutterBluePlus.stopScan(); } catch (_) {}
    await _scanSub?.cancel();
    await _isScanSub?.cancel();
    await _adapterStateSub?.cancel();
    _scanSub = null;
    _isScanSub = null;
    _adapterStateSub = null;
    await _unsubscribe();
    final device = _connectedDevice;
    if (device != null) {
      try { await device.disconnect(); } catch (_) {}
    }
  }

  Future<void> _connectOnce(BluetoothDevice device) async {
    // Monitor connection state BEFORE calling connect() so we catch any
    // disconnection that occurs during service discovery or subscribe.
    // FBP streams never throw, so no onError handler is needed.
    _connectionSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected &&
          _connectedDevice?.remoteId == device.remoteId) {
        unawaited(_handleDisconnectCleanup(autoStatus: 'Disconnected'));
      }
    });

    // Request MTU 512 on Android so multi-frame binary packets arrive intact.
    // mtu: null would silently leave the default 23-byte ATT MTU (20-byte payload)
    // which truncates every binary notification and causes all parses to fail.
    await device.connect(
      license: License.free,
      autoConnect: false,
      mtu: 512,
      timeout: const Duration(seconds: 12),
    );

    await _finishConnectedSetup(device);
  }

  /// Service discovery, characteristic lookup, subscribe, and bonding —
  /// everything after the link-layer GATT connection exists.
  Future<void> _finishConnectedSetup(BluetoothDevice device) async {
    final services = await device.discoverServices();
    final gatewayService = _findServiceByUuid(services, gatewayServiceUuid);
    if (gatewayService == null) {
      await _disconnectQuietly(device);
      throw StateError(
        'Selected device does not expose the BLE gateway service.',
      );
    }

    _notifyCharacteristic = _findCharacteristicByUuid(
      services,
      notifyCharacteristicUuid,
    );
    _binaryNotifyCharacteristic = _findCharacteristicByUuid(
      services,
      binaryNotifyCharacteristicUuid,
    );
    _commandCharacteristic = _findCharacteristicByUuid(
      services,
      commandCharacteristicUuid,
    );

    if (_commandCharacteristic == null &&
        _notifyCharacteristic == null &&
        _binaryNotifyCharacteristic == null) {
      await _disconnectQuietly(device);
      throw StateError(
        'Selected device is not the expected gateway peripheral.',
      );
    }

    _connectedDevice = device;
    _isConnecting = false;

    if (_notifyCharacteristic != null || _binaryNotifyCharacteristic != null) {
      await _subscribe();
    }

    // Guard: if the connectionState stream fired a disconnect while we were
    // doing service discovery or subscribe, _connectedDevice has been cleared.
    // Surface that as an error so the caller can reset and retry.
    if (_connectedDevice == null) {
      throw StateError('Connection lost during characteristic setup.');
    }

    await _readOnce();

    _status = _commandCharacteristic == null
        ? 'Connected. Command characteristic missing.'
        : 'Connected. Gateway characteristics ready.';
    notifyListeners();
  }

  Future<void> _resetBeforeConnect(BluetoothDevice device) async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    await _connectionSub?.cancel();
    _connectionSub = null;
    await _unsubscribe();
    // Only disconnect what we know is connected. Calling disconnect() on a
    // device that is not connected causes Android to open a transient GATT
    // client just to close it, creating spurious connect+cancelOpen log
    // noise and occasionally triggering race conditions.
    await _disconnectQuietly(_connectedDevice);
    _connectedDevice = null;
    _notifyCharacteristic = null;
    _binaryNotifyCharacteristic = null;
    _commandCharacteristic = null;
  }

  Future<void> _resetAfterFailedConnect(BluetoothDevice device) async {
    await _connectionSub?.cancel();
    _connectionSub = null;
    await _unsubscribe();
    await _disconnectQuietly(device);
    _connectedDevice = null;
    _notifyCharacteristic = null;
    _binaryNotifyCharacteristic = null;
    _commandCharacteristic = null;
  }

  Future<void> _disconnectQuietly(BluetoothDevice? device) async {
    if (device == null) {
      return;
    }

    try {
      await device.disconnect();
    } catch (_) {}
  }

  String _formatConnectFailure(Object error) {
    final suffix = isTransientBleConnectError(error)
        ? ' Try again with the ESP awake and close to the phone.'
        : '';
    return 'Connect failed: $error$suffix';
  }

  Future<void> writeCommandLine(String line) async {
    final characteristic = _commandCharacteristic;
    if (characteristic == null) {
      throw StateError('Command characteristic not available.');
    }
    if (!characteristic.properties.write &&
        !characteristic.properties.writeWithoutResponse) {
      throw StateError('Command characteristic is not writable.');
    }
    final bytes = utf8.encode(line);
    // FBP: withoutResponse:true = write-without-response, false = with-response.
    await characteristic.write(
      bytes,
      withoutResponse: !characteristic.properties.write,
    );
    _status = 'Sent ${line.trim()}';
    notifyListeners();
  }

  Future<void> emitFixtureChunk(
    List<int> bytes, {
    String source = 'fixture',
  }) async {
    _chunkController.add(
      BleTransportChunk(bytes: bytes, source: source, isBinary: false),
    );
  }

  Future<void> _readOnce() async {
    final characteristic = _notifyCharacteristic;
    if (characteristic == null) return;
    if (!characteristic.properties.read) return;
    try {
      final value = await characteristic.read();
      _chunkController.add(
        BleTransportChunk(bytes: value, source: 'read', isBinary: false),
      );
    } catch (_) {}
  }

  Future<void> _subscribe() async {
    await _textNotifySub?.cancel();
    await _binaryNotifySub?.cancel();
    _textNotifySub = null;
    _binaryNotifySub = null;
    // Subscribe each characteristic independently. A failure on the binary
    // characteristic does not abort the text channel and vice-versa.
    try {
      _textNotifySub = await _subscribeCharacteristic(
        _notifyCharacteristic,
        isBinary: false,
      );
    } catch (e) {
      _status = 'Text notify subscribe error: $e';
    }
    try {
      _binaryNotifySub = await _subscribeCharacteristic(
        _binaryNotifyCharacteristic,
        isBinary: true,
      );
    } catch (e) {
      _status = 'Binary notify subscribe error: $e';
    }
  }

  Future<StreamSubscription<List<int>>?> _subscribeCharacteristic(
    BluetoothCharacteristic? characteristic, {
    required bool isBinary,
  }) async {
    if (characteristic == null) return null;
    if (!characteristic.properties.notify &&
        !characteristic.properties.indicate) {
      return null;
    }

    // Register the listener BEFORE calling setNotifyValue so we don't miss
    // the first notification that may arrive immediately after enabling.
    // FBP streams never throw, so no onError handler is needed.
    final sub = characteristic.onValueReceived.listen((value) {
      _chunkController.add(
        BleTransportChunk(bytes: value, source: 'notify', isBinary: isBinary),
      );
    });

    await characteristic.setNotifyValue(true);
    return sub;
  }

  Future<void> _unsubscribe() async {
    await _textNotifySub?.cancel();
    await _binaryNotifySub?.cancel();
    _textNotifySub = null;
    _binaryNotifySub = null;
    // Only disable the CCCD if the device is still connected; setNotifyValue
    // will fail (and is pointless) if the connection is already gone.
    // Bounded: CCCD writes are encrypted now, and a write on a link that
    // needs to renegotiate security can hang for seconds — never let that
    // block whoever is waiting on this cleanup step.
    final device = _connectedDevice;
    if (device != null && device.isConnected) {
      try {
        await _notifyCharacteristic
            ?.setNotifyValue(false)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
      try {
        await _binaryNotifyCharacteristic
            ?.setNotifyValue(false)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  Future<void> _handleDisconnectCleanup({required String autoStatus}) async {
    _connectedDevice = null;
    _notifyCharacteristic = null;
    _binaryNotifyCharacteristic = null;
    _commandCharacteristic = null;
    _isConnecting = false;
    _status = autoStatus;
    notifyListeners();
  }

  BluetoothCharacteristic? _findCharacteristicByUuid(
    List<BluetoothService> services,
    String targetUuid,
  ) {
    final target = Guid(targetUuid);
    for (final service in services) {
      for (final c in service.characteristics) {
        if (c.characteristicUuid == target) return c;
      }
    }
    return null;
  }

  BluetoothService? _findServiceByUuid(
    List<BluetoothService> services,
    String targetUuid,
  ) {
    final target = Guid(targetUuid);
    for (final service in services) {
      if (service.serviceUuid == target) return service;
    }
    return null;
  }
}
