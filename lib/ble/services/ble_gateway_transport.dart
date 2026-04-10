import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

@visibleForTesting
bool isTransientBleConnectError(Object error) {
  final message = '$error'.toLowerCase();
  return message.contains('unknown error 133') ||
      message.contains('gatt 133') ||
      message.contains('status=133');
}

@visibleForTesting
bool isBleGatewayCandidate(BleDevice device, {required String serviceUuid}) {
  final canonicalServiceUuid = serviceUuid.trim().toLowerCase();
  final advertisedServices = device.services
      .map((service) => service.trim().toLowerCase())
      .toList(growable: false);
  if (advertisedServices.contains(canonicalServiceUuid)) {
    return true;
  }

  final rawName = (device.name ?? device.rawName ?? '').trim().toLowerCase();
  if (rawName.isEmpty) {
    return false;
  }

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

  final List<BleDevice> _devices = <BleDevice>[];
  final StreamController<BleTransportChunk> _chunkController =
      StreamController<BleTransportChunk>.broadcast();

  StreamSubscription<BleDevice>? _scanSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<dynamic>? _textNotifySub;
  StreamSubscription<dynamic>? _binaryNotifySub;

  BleDevice? _connectedDevice;
  BleCharacteristic? _notifyCharacteristic;
  BleCharacteristic? _binaryNotifyCharacteristic;
  BleCharacteristic? _commandCharacteristic;
  bool _initialized = false;
  bool _isScanning = false;
  bool _isConnecting = false;
  String _status = 'Initializing BLE...';

  List<BleDevice> get devices => List.unmodifiable(_devices);
  BleDevice? get connectedDevice => _connectedDevice;
  bool get isScanning => _isScanning;
  bool get isConnecting => _isConnecting;
  bool get isConnected => _connectedDevice != null;
  bool get hasNotifyCharacteristic => _notifyCharacteristic != null;
  bool get hasBinaryNotifyCharacteristic => _binaryNotifyCharacteristic != null;
  bool get hasCommandCharacteristic => _commandCharacteristic != null;
  String get status => _status;
  Stream<BleTransportChunk> get chunks => _chunkController.stream;

  Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    try {
      await UniversalBle.requestPermissions(withAndroidFineLocation: false);
      _scanSub = UniversalBle.scanStream.listen(
        (device) {
          if (!isBleGatewayCandidate(device, serviceUuid: gatewayServiceUuid)) {
            return;
          }

          final index = _devices.indexWhere(
            (item) => item.deviceId == device.deviceId,
          );
          if (index >= 0) {
            _devices[index] = device;
          } else {
            _devices.add(device);
          }
          notifyListeners();
        },
        onError: (Object error) {
          _isScanning = false;
          _status = 'Scan error: $error';
          notifyListeners();
        },
      );
      _status = 'Ready. Tap Start scan.';
    } catch (error) {
      _status = 'BLE init failed: $error';
    }

    notifyListeners();
  }

  Future<void> startScan() async {
    try {
      final availability = await UniversalBle.getBluetoothAvailabilityState();
      if (availability != AvailabilityState.poweredOn) {
        _status = 'Bluetooth is ${availability.name}.';
        notifyListeners();
        return;
      }

      await UniversalBle.stopScan();
      _isScanning = true;
      _status = 'Scanning...';
      notifyListeners();

      await UniversalBle.startScan(
        scanFilter: ScanFilter(
          withServices: <String>[gatewayServiceUuid],
          withNamePrefix: const <String>['SDolve'],
        ),
        platformConfig: PlatformConfig(
          android: AndroidOptions(requestLocationPermission: false),
        ),
      );
    } catch (error) {
      _isScanning = false;
      _status = 'Scan failed: $error';
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    await UniversalBle.stopScan();
    _isScanning = false;
    _status = 'Scan stopped.';
    notifyListeners();
  }

  Future<void> connect(BleDevice device) async {
    const settleDelay = Duration(milliseconds: 350);
    const retryDelay = Duration(milliseconds: 900);

    try {
      _isConnecting = true;
      _status = 'Connecting to ${device.name ?? device.deviceId}...';
      notifyListeners();

      await _resetBeforeConnect(device);
      await Future<void>.delayed(settleDelay);

      Object? lastError;
      final maxAttempts = defaultTargetPlatform == TargetPlatform.android
          ? 2
          : 1;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          if (attempt > 1) {
            _status =
                'Retrying connection to ${device.name ?? device.deviceId}...';
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
    if (device == null) {
      return;
    }

    try {
      await _unsubscribe();
      await _connectionSub?.cancel();
      _connectionSub = null;
      await device.disconnect();
      await _handleDisconnectCleanup(autoStatus: 'Disconnected');
    } catch (error) {
      _status = 'Disconnect failed: $error';
      notifyListeners();
    }
  }

  Future<void> shutdown() async {
    try {
      await stopScan();
      await _unsubscribe();
      await _scanSub?.cancel();
      _scanSub = null;
      final device = _connectedDevice;
      if (device != null) {
        await device.disconnect();
      }
    } catch (_) {}
  }

  Future<void> _connectOnce(BleDevice device) async {
    await device.connect(timeout: const Duration(seconds: 12));
    try {
      await device.requestMtu(256);
    } catch (_) {}

    _connectionSub = device.connectionStream.listen(
      (isConnected) {
        if (!isConnected && _connectedDevice?.deviceId == device.deviceId) {
          unawaited(_handleDisconnectCleanup(autoStatus: 'Disconnected'));
          return;
        }
        _status = 'Connection: ${isConnected ? 'connected' : 'disconnected'}';
        notifyListeners();
      },
      onError: (Object error) {
        _isConnecting = false;
        _status = 'Connection error: $error';
        notifyListeners();
      },
    );

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

    if ((_notifyCharacteristic != null) ||
        (_binaryNotifyCharacteristic != null)) {
      await _subscribe();
      await _readOnce();
    }

    _status = _commandCharacteristic == null
        ? 'Connected. Command characteristic missing.'
        : 'Connected. Gateway characteristics ready.';
    notifyListeners();
  }

  Future<void> _resetBeforeConnect(BleDevice device) async {
    try {
      await UniversalBle.stopScan();
    } catch (_) {}
    _isScanning = false;

    await _connectionSub?.cancel();
    _connectionSub = null;
    await _unsubscribe();
    await _disconnectQuietly(_connectedDevice);
    if (_connectedDevice?.deviceId != device.deviceId) {
      await _disconnectQuietly(device);
    }
    _connectedDevice = null;
    _notifyCharacteristic = null;
    _binaryNotifyCharacteristic = null;
    _commandCharacteristic = null;
  }

  Future<void> _resetAfterFailedConnect(BleDevice device) async {
    await _connectionSub?.cancel();
    _connectionSub = null;
    await _unsubscribe();
    await _disconnectQuietly(device);
    _connectedDevice = null;
    _notifyCharacteristic = null;
    _binaryNotifyCharacteristic = null;
    _commandCharacteristic = null;
  }

  Future<void> _disconnectQuietly(BleDevice? device) async {
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

    final supportsWrite = characteristic.properties.contains(
      CharacteristicProperty.write,
    );
    final supportsWriteWithoutResponse = characteristic.properties.contains(
      CharacteristicProperty.writeWithoutResponse,
    );

    if (!supportsWrite && !supportsWriteWithoutResponse) {
      throw StateError('Command characteristic is not writable.');
    }

    final bytes = utf8.encode(line);
    await characteristic.write(bytes, withResponse: supportsWrite);
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
    if (characteristic == null) {
      return;
    }
    if (!characteristic.properties.contains(CharacteristicProperty.read)) {
      return;
    }

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
    _textNotifySub = await _subscribeCharacteristic(
      _notifyCharacteristic,
      isBinary: false,
    );
    _binaryNotifySub = await _subscribeCharacteristic(
      _binaryNotifyCharacteristic,
      isBinary: true,
    );
  }

  Future<StreamSubscription<dynamic>?> _subscribeCharacteristic(
    BleCharacteristic? characteristic, {
    required bool isBinary,
  }) async {
    if (characteristic == null) {
      return null;
    }

    if (characteristic.properties.contains(CharacteristicProperty.notify)) {
      await characteristic.notifications.subscribe();
      return characteristic.notifications.listen(
        (dynamic value) {
          _emitChunkFromNotifyValue(value, isBinary: isBinary);
        },
        onError: (Object error) {
          _status = 'Notify error: $error';
          notifyListeners();
        },
      );
    }

    if (characteristic.properties.contains(CharacteristicProperty.indicate)) {
      await characteristic.indications.subscribe();
      return characteristic.indications.listen(
        (dynamic value) {
          _emitChunkFromNotifyValue(value, isBinary: isBinary);
        },
        onError: (Object error) {
          _status = 'Notify error: $error';
          notifyListeners();
        },
      );
    }

    return null;
  }

  void _emitChunkFromNotifyValue(dynamic value, {required bool isBinary}) {
    if (value is List<int>) {
      _chunkController.add(
        BleTransportChunk(bytes: value, source: 'notify', isBinary: isBinary),
      );
      return;
    }

    if (value is List) {
      final bytes = value.whereType<int>().toList(growable: false);
      if (bytes.isNotEmpty) {
        _chunkController.add(
          BleTransportChunk(bytes: bytes, source: 'notify', isBinary: isBinary),
        );
      }
    }
  }

  Future<void> _unsubscribe() async {
    final textCharacteristic = _notifyCharacteristic;
    final binaryCharacteristic = _binaryNotifyCharacteristic;
    await _textNotifySub?.cancel();
    await _binaryNotifySub?.cancel();
    _textNotifySub = null;
    _binaryNotifySub = null;
    if (textCharacteristic != null) {
      try {
        await textCharacteristic.unsubscribe();
      } catch (_) {}
    }
    if (binaryCharacteristic != null) {
      try {
        await binaryCharacteristic.unsubscribe();
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

  BleCharacteristic? _findCharacteristicByUuid(
    List<BleService> services,
    String targetUuid,
  ) {
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (_canonicalUuid(characteristic.uuid) == _canonicalUuid(targetUuid)) {
          return characteristic;
        }
      }
    }
    return null;
  }

  BleService? _findServiceByUuid(List<BleService> services, String targetUuid) {
    for (final service in services) {
      if (_canonicalUuid(service.uuid) == _canonicalUuid(targetUuid)) {
        return service;
      }
    }
    return null;
  }

  String _canonicalUuid(String uuid) {
    return uuid.trim().toLowerCase();
  }
}
