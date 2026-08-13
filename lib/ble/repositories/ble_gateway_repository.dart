import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../models/n2k_device_info.dart';
import '../models/ble_gateway_event.dart';
import '../models/device_list_snapshot.dart';
import '../parsers/ble_gateway_event_parser.dart';
import '../parsers/device_list_text_parser.dart';

class BleGatewayRepository extends ChangeNotifier {
  BleGatewayRepository({
    BleGatewayEventParser? eventParser,
    DeviceListTextParser? textParser,
  }) : _eventParser = eventParser ?? BleGatewayEventParser(),
       _textParser = textParser ?? DeviceListTextParser();

  final BleGatewayEventParser _eventParser;
  final DeviceListTextParser _textParser;

  /// Pre-populate the device list from a local cache (e.g. SharedPreferences).
  /// Called before any BLE connection is made so the UI shows something useful
  /// immediately. A real gateway snapshot will overwrite this when it arrives.
  void seedDevices(List<N2kDeviceInfo> devices) {
    if (devices.isEmpty) return;
    _devices = List<N2kDeviceInfo>.unmodifiable(devices);
    _lastStatusLine = 'From cache (${devices.length} devices)';
    notifyListeners();
  }

  final List<BleGatewayEvent> _recentEvents = <BleGatewayEvent>[];
  List<N2kDeviceInfo> _devices = const <N2kDeviceInfo>[];
  DeviceListSnapshot? _latestSnapshot;
  DeviceListSnapshot? _buildingSnapshot;
  BleGatewayEvent? _latestEvent;
  String _lastStatusLine = 'Idle';
  String _lastSource = 'none';
  String? _lastError;
  DateTime? _lastUpdateAt;
  DateTime? _lastSnapshotAt;
  int? _currentRequestId;
  int? _eventProgressExpected;
  int? _eventProgressReceived;
  bool _requestPending = false;
  bool _snapshotInProgress = false;

  UnmodifiableListView<N2kDeviceInfo> get devices =>
      UnmodifiableListView<N2kDeviceInfo>(_devices);
  UnmodifiableListView<BleGatewayEvent> get recentEvents =>
      UnmodifiableListView<BleGatewayEvent>(_recentEvents);
  DeviceListSnapshot? get latestSnapshot => _latestSnapshot;
  BleGatewayEvent? get latestEvent => _latestEvent;
  String get lastStatusLine => _lastStatusLine;
  String get lastSource => _lastSource;
  String? get lastError => _lastError;
  DateTime? get lastUpdateAt => _lastUpdateAt;
  DateTime? get lastSnapshotAt => _lastSnapshotAt;
  int? get currentRequestId =>
      _latestSnapshot?.snapshotRequestId ??
      _latestSnapshot?.pendingRequestId ??
      _currentRequestId;
  bool get requestPending => _latestSnapshot?.requestPending ?? _requestPending;
  bool get snapshotInProgress =>
      _latestSnapshot?.snapshotInProgress ?? _snapshotInProgress;
  int? get progressExpected => snapshotInProgress
      ? _eventProgressExpected ?? _latestSnapshot?.snapshotExpected
      : _latestSnapshot?.snapshotExpected;
  int? get progressReceived => snapshotInProgress
      ? _eventProgressReceived ?? _latestSnapshot?.snapshotReceived
      : _latestSnapshot?.snapshotReceived;

  int get malformedDeviceListMessages =>
      _latestSnapshot?.malformedDeviceListMessages ?? 0;
  int get completedSnapshots => _latestSnapshot?.completedSnapshots ?? 0;
  int get droppedSnapshots => _latestSnapshot?.droppedSnapshots ?? 0;
  int get unknownPacketTypes => _latestSnapshot?.unknownPacketTypes ?? 0;
  int get spiParseErrors => _latestSnapshot?.spiParseErrors ?? 0;

  String _ts() {
    final now = DateTime.now().toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.${three(now.millisecond)}Z';
  }

  void handleIncomingLine(String line, {required String source}) {
    final normalizedLine = line.trim();
    if (normalizedLine.isEmpty) {
      return;
    }

    debugPrint('[${_ts()}] [REPO] RX src=$source: $normalizedLine');
    _lastSource = source;
    _lastUpdateAt = DateTime.now().toUtc();

    final snapshot = _textParser.tryParseSnapshotHeader(normalizedLine);
    if (snapshot != null) {
      debugPrint(
        '[${_ts()}] [REPO] snapshot header accepted id=${snapshot.snapshotRequestId} complete=${snapshot.snapshotComplete} expected=${snapshot.snapshotExpected}',
      );
      _buildingSnapshot = snapshot;
      _lastStatusLine = _snapshotStatusLine(snapshot, snapshot.devices.length);
      _applySnapshot(snapshot);
      notifyListeners();
      return;
    }

    final device = _textParser.tryParseSnapshotDevice(normalizedLine);
    if (device != null && _buildingSnapshot != null) {
      debugPrint(
        '[${_ts()}] [REPO] device accepted src=${device.sourceAddress} name="${device.name}" model="${device.model}" hasProductInfo=${device.hasProductInfo}',
      );
      final updatedSnapshot = _buildingSnapshot!.copyWith(
        devices: List<N2kDeviceInfo>.unmodifiable(<N2kDeviceInfo>[
          ..._buildingSnapshot!.devices,
          device,
        ]),
        rawMessage: '${_buildingSnapshot!.rawMessage}\n$normalizedLine',
      );
      _buildingSnapshot = updatedSnapshot;
      _lastStatusLine = _snapshotStatusLine(
        updatedSnapshot,
        updatedSnapshot.devices.length,
      );
      _applySnapshot(updatedSnapshot);
      notifyListeners();
      return;
    }

    if (device != null && _buildingSnapshot == null) {
      debugPrint(
        '[${_ts()}] [REPO] WARN device line arrived but no snapshot in progress (dropped): src=${device.sourceAddress}',
      );
    }

    if (normalizedLine.toLowerCase().startsWith('device_list snapshot ')) {
      _lastError = 'Malformed device_list snapshot ignored.';
      debugPrint('[${_ts()}] [REPO] ERROR malformed snapshot header: $normalizedLine');
    } else if (normalizedLine.toLowerCase().startsWith('device src=')) {
      _lastError = 'Malformed device_list device ignored.';
      debugPrint('[${_ts()}] [REPO] ERROR malformed device line: $normalizedLine');
    }

    final event = _eventParser.parse(normalizedLine, occurredAt: _lastUpdateAt);
    _applyEvent(event);
    _lastStatusLine = _eventStatusLine(event);
    notifyListeners();
  }

  void markRequestQueued() {
    // Keep _devices intact — continue showing the previous snapshot while the
    // new request is in flight, so the UI never flashes a fallback name.
    _latestSnapshot = null;
    _buildingSnapshot = null;
    _currentRequestId = null;
    _eventProgressExpected = null;
    _eventProgressReceived = null;
    _requestPending = true;
    _snapshotInProgress = true;
    _lastError = null;
    _lastStatusLine = 'Sending request_device_list...';
    _lastSnapshotAt = null;
    _lastUpdateAt = DateTime.now().toUtc();
    notifyListeners();
  }

  void markWriteFailed(Object error) {
    _requestPending = false;
    _snapshotInProgress = false;
    _lastError = '$error';
    _lastStatusLine = 'request_device_list failed';
    _lastUpdateAt = DateTime.now().toUtc();
    notifyListeners();
  }

  void handleDisconnected() {
    _buildingSnapshot = null;
    _requestPending = false;
    _snapshotInProgress = false;
    _eventProgressExpected = null;
    _eventProgressReceived = null;
    _lastStatusLine = 'Disconnected';
    _lastUpdateAt = DateTime.now().toUtc();
    notifyListeners();
  }

  /// Forget a single device by N2K source address. Removes the entry from
  /// both the live device list and the cached snapshot so a subsequent app
  /// restart does not resurrect the offline node from disk.
  bool forgetDevice(int source) {
    final beforeCount = _devices.length;
    final remaining = _devices.where((d) => d.src != source).toList();
    if (remaining.length == beforeCount) {
      return false;
    }
    _devices = List<N2kDeviceInfo>.unmodifiable(remaining);

    final snapshot = _latestSnapshot;
    if (snapshot != null) {
      final filtered = snapshot.devices.where((d) => d.src != source).toList();
      if (filtered.length != snapshot.devices.length) {
        _latestSnapshot = snapshot.copyWith(
          devices: List<N2kDeviceInfo>.unmodifiable(filtered),
        );
      }
    }
    final building = _buildingSnapshot;
    if (building != null) {
      final filtered = building.devices.where((d) => d.src != source).toList();
      if (filtered.length != building.devices.length) {
        _buildingSnapshot = building.copyWith(
          devices: List<N2kDeviceInfo>.unmodifiable(filtered),
        );
      }
    }
    _lastUpdateAt = DateTime.now().toUtc();
    notifyListeners();
    return true;
  }

  void _applySnapshot(DeviceListSnapshot snapshot) {
    final dedupedDevices = dedupeDevicesBySrc(snapshot.devices);
    _latestSnapshot = snapshot.copyWith(devices: dedupedDevices);
    _lastError = null;
    _currentRequestId = snapshot.snapshotRequestId ?? snapshot.pendingRequestId;
    _requestPending = snapshot.requestPending;
    _snapshotInProgress = snapshot.snapshotInProgress;
    _eventProgressExpected = snapshot.snapshotExpected;
    _eventProgressReceived = snapshot.snapshotReceived;
    debugPrint(
      '[${_ts()}] [REPO] _applySnapshot: id=$_currentRequestId complete=${snapshot.snapshotComplete} deviceCount=${dedupedDevices.length} expected=${snapshot.snapshotExpected}',
    );

    // Commit whenever we have at least one device, whether or not the snapshot
    // is marked complete.  The STM32 may deliver a partial snapshot
    // (complete=0) when the SPI queue was previously undersized; we still want
    // to show whatever devices we have rather than showing stale cached data.
    if (dedupedDevices.isNotEmpty) {
      // `complete=true` on the header only means the STM32's own bus scan is
      // done — it's sent before any "device ..." detail lines cross the BLE
      // link, and stays true (carried through copyWith) while they trickle in
      // one at a time. Treating it as "all device lines are in" caused every
      // periodic re-poll to replace _devices with just the first device the
      // instant its line arrived (dropping every other known device for a
      // frame), then grow back as the rest arrived — the home page cards
      // flashing out and back in on every snapshot. Only do the full replace
      // once we've actually received as many device lines as the header said
      // to expect.
      final expected = snapshot.snapshotExpected;
      final haveAllExpectedDevices =
          expected == null || dedupedDevices.length >= expected;
      if (snapshot.snapshotComplete && haveAllExpectedDevices) {
        // Full snapshot received: replace the device list entirely.
        _devices = dedupedDevices;
      } else {
        // Snapshot is still building (arriving line-by-line).  Overlay the
        // newly-received entries on top of the existing list so that devices
        // already classified in the previous snapshot (in particular the
        // gateway device with category='gateway') are not temporarily lost
        // while the new snapshot is only partially committed.  This prevents
        // the gateway from briefly appearing as an unclassified 'unknown'
        // entry in the binary merge and flashing as a phantom 4th card.
        final bySource = <int, N2kDeviceInfo>{
          for (final d in _devices) d.src: d,
          for (final d in dedupedDevices) d.src: d,
        };
        _devices = List<N2kDeviceInfo>.unmodifiable(bySource.values.toList());
      }
      _lastSnapshotAt = DateTime.now().toUtc();
      _buildingSnapshot = _latestSnapshot;
      for (final d in dedupedDevices) {
        debugPrint(
          '[${_ts()}] [REPO]   device src=${d.sourceAddress} name="${d.name}" model="${d.model}" hasProductInfo=${d.hasProductInfo} online=${d.online}',
        );
      }
    }
  }

  void _applyEvent(BleGatewayEvent event) {
    _latestEvent = event;
    _recentEvents.add(event);
    if (_recentEvents.length > 20) {
      _recentEvents.removeAt(0);
    }

    switch (event.type) {
      case BleGatewayEventType.requestSent:
        _currentRequestId = event.requestId ?? _currentRequestId;
        _requestPending = true;
        _snapshotInProgress = true;
        _lastError = null;
        break;
      case BleGatewayEventType.begin:
        _currentRequestId = event.requestId ?? _currentRequestId;
        _requestPending = true;
        _snapshotInProgress = true;
        _eventProgressExpected = event.count ?? _eventProgressExpected;
        _eventProgressReceived = 0;
        _lastError = null;
        break;
      case BleGatewayEventType.deviceProgress:
        _snapshotInProgress = true;
        _eventProgressExpected = event.total ?? _eventProgressExpected;
        _eventProgressReceived = event.index ?? _eventProgressReceived;
        break;
      case BleGatewayEventType.complete:
        _currentRequestId = event.requestId ?? _currentRequestId;
        _requestPending = false;
        _snapshotInProgress = false;
        _eventProgressReceived = event.count ?? _eventProgressReceived;
        _eventProgressExpected = event.count ?? _eventProgressExpected;
        // Commit whatever was built — mirrors the timeout path for the case
        // where the End binary arrived and complete=1 was never sent separately.
        final completedSnapshot = _buildingSnapshot;
        if (completedSnapshot != null && completedSnapshot.devices.isNotEmpty) {
          final finalDevices = dedupeDevicesBySrc(completedSnapshot.devices);
          _devices = finalDevices;
          _latestSnapshot = completedSnapshot.copyWith(
            devices: finalDevices,
            snapshotInProgress: false,
            requestPending: false,
          );
          _lastSnapshotAt = DateTime.now().toUtc();
        }
        break;
      case BleGatewayEventType.timeout:
        final timeoutRequestId = event.requestId;
        final hasActiveRequest =
            _requestPending || _snapshotInProgress || _buildingSnapshot != null;
        if (!hasActiveRequest) {
          break;
        }
        if (_currentRequestId != null &&
            timeoutRequestId != null &&
            timeoutRequestId != _currentRequestId) {
          break;
        }
        _currentRequestId = timeoutRequestId ?? _currentRequestId;
        _requestPending = false;
        _snapshotInProgress = false;
        _lastError = 'device_list request timed out';
        // Some firmware builds emit snapshot headers/devices but never flip the
        // final complete flag. If we collected any device lines, surface the
        // best available partial snapshot instead of showing an empty list.
        final pendingSnapshot = _buildingSnapshot;
        if (pendingSnapshot != null && pendingSnapshot.devices.isNotEmpty) {
          final partialDevices = dedupeDevicesBySrc(pendingSnapshot.devices);
          _devices = partialDevices;
          _latestSnapshot = pendingSnapshot.copyWith(
            devices: partialDevices,
            snapshotInProgress: false,
            requestPending: false,
          );
          _lastSnapshotAt = DateTime.now().toUtc();
        }
        break;
      case BleGatewayEventType.unknown:
        break;
    }
  }

  String _snapshotStatusLine(DeviceListSnapshot snapshot, int deviceCount) {
    final received = snapshot.snapshotReceived ?? deviceCount;
    final expected = snapshot.snapshotExpected;
    final progress = expected == null ? '$received' : '$received/$expected';
    if (snapshot.snapshotComplete) {
      return 'Snapshot complete ($progress)';
    }
    return 'Snapshot in progress ($progress)';
  }

  String _eventStatusLine(BleGatewayEvent event) {
    switch (event.type) {
      case BleGatewayEventType.requestSent:
        final requestId = event.requestId;
        return requestId == null
            ? 'Device list request sent'
            : 'Device list request sent (id=$requestId)';
      case BleGatewayEventType.begin:
        final count = event.count;
        return count == null
            ? 'Receiving device list'
            : 'Receiving device list (0/$count)';
      case BleGatewayEventType.deviceProgress:
        final index = event.index;
        final total = event.total;
        if (index == null || total == null) {
          return 'Receiving device list';
        }
        return 'Receiving device list ($index/$total)';
      case BleGatewayEventType.complete:
        final count = event.count;
        return count == null
            ? 'Device list complete'
            : 'Device list complete ($count devices)';
      case BleGatewayEventType.timeout:
        return 'Device list request timed out';
      case BleGatewayEventType.unknown:
        return _truncateStatusLine(event.rawLine);
    }
  }

  String _truncateStatusLine(String line) {
    const maxLength = 120;
    if (line.length <= maxLength) {
      return line;
    }
    return '${line.substring(0, maxLength - 3)}...';
  }
}

List<N2kDeviceInfo> dedupeDevicesBySrc(Iterable<N2kDeviceInfo> devices) {
  final latestBySrc = <int, N2kDeviceInfo>{};
  for (final device in devices) {
    latestBySrc[device.sourceAddress] = device;
  }

  final deduped = latestBySrc.values.toList(growable: false)
    ..sort((left, right) => left.sourceAddress.compareTo(right.sourceAddress));
  return List<N2kDeviceInfo>.unmodifiable(deduped);
}
