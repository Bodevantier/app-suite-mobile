import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import '../../controllers/ble_controller.dart';
import '../../models/gateway_command.dart';
import '../../models/n2k_device_info.dart';
import '../framing/newline_message_framer.dart';
import '../models/ble_gateway_event.dart';
import '../models/device_list_snapshot.dart';
import '../repositories/ble_gateway_repository.dart';
import '../services/ble_gateway_transport.dart';
import '../testing/gateway_protocol_fixtures.dart';

class BleGatewayController extends ChangeNotifier {
  BleGatewayController({
    required this.transport,
    required this.repository,
    this.telemetryController,
    NewlineMessageFramer? framer,
  }) : _framer = framer ?? NewlineMessageFramer() {
    transport.addListener(_handleDependencyChanged);
    repository.addListener(_handleDependencyChanged);
    _chunkSubscription = transport.chunks.listen(_handleChunk);
    _lastConnected = transport.isConnected;
  }

  final BleGatewayTransportService transport;
  final BleGatewayRepository repository;
  final BleController? telemetryController;
  final NewlineMessageFramer _framer;

  late final StreamSubscription<BleTransportChunk> _chunkSubscription;
  bool _lastConnected = false;

  List<BleDevice> get discoveredDevices => transport.devices;
  BleDevice? get connectedDevice => transport.connectedDevice;
  bool get isScanning => transport.isScanning;
  bool get isConnecting => transport.isConnecting;
  bool get isConnected => transport.isConnected;
  bool get hasNotifyCharacteristic => transport.hasNotifyCharacteristic;
  bool get hasCommandCharacteristic => transport.hasCommandCharacteristic;
  String get bleStatus => transport.status;
  List<N2kDeviceInfo> get devices {
    final snapshotDevices = repository.devices;
    final decodedDevices =
        telemetryController?.decodedDevices ?? const <N2kDeviceInfo>[];

    final hasSnapshotDevices = snapshotDevices.isNotEmpty;
    final requestAttemptFinishedWithoutSnapshot =
        snapshotDevices.isEmpty &&
        repository.currentRequestId != null &&
        !repository.requestPending &&
        !repository.snapshotInProgress;

    return _mergeDevices(
      snapshotDevices,
      decodedDevices,
      allowFallbackTelemetry:
          hasSnapshotDevices || requestAttemptFinishedWithoutSnapshot,
    );
  }
  String get statusLine => repository.lastStatusLine;
  String? get lastError => repository.lastError;
  DateTime? get lastUpdateAt => repository.lastUpdateAt;
  DateTime? get lastSnapshotAt => repository.lastSnapshotAt;
  int? get currentRequestId => repository.currentRequestId;
  bool get requestPending => repository.requestPending;
  bool get snapshotInProgress => repository.snapshotInProgress;
  int? get progressExpected => repository.progressExpected;
  int? get progressReceived => repository.progressReceived;
  int get malformedDeviceListMessages => repository.malformedDeviceListMessages;
  int get completedSnapshots => repository.completedSnapshots;
  int get droppedSnapshots => repository.droppedSnapshots;
  int get unknownPacketTypes => repository.unknownPacketTypes;
  int get spiParseErrors => repository.spiParseErrors;
  List<BleGatewayEvent> get recentEvents => repository.recentEvents;
  DeviceListSnapshot? get latestSnapshot => repository.latestSnapshot;
  BleGatewayEvent? get latestEvent => repository.latestEvent;

  Future<void> initialize() {
    return transport.ensureInitialized();
  }

  Future<void> startScan() {
    return transport.startScan();
  }

  Future<void> stopScan() {
    return transport.stopScan();
  }

  Future<void> connect(BleDevice device) {
    return transport.connect(device);
  }

  Future<void> disconnect() async {
    await transport.disconnect();
  }

  Future<void> shutdown() async {
    await transport.shutdown();
  }

  Future<void> requestDeviceList() async {
    repository.markRequestQueued();
    try {
      await transport.writeCommandLine(
        GatewayCommand.requestDeviceList().toCommandLine(),
      );
    } catch (error) {
      repository.markWriteFailed(error);
      rethrow;
    }
  }

  Future<void> loadMockDeviceListFixture() async {
    for (final line in GatewayProtocolFixtures.eventLines) {
      await transport.emitFixtureChunk(
        line.codeUnits.followedBy(<int>[10]).toList(),
      );
    }
    for (final chunk in GatewayProtocolFixtures.chunkedTextNotificationChunks) {
      await transport.emitFixtureChunk(chunk);
    }
  }

  void _handleChunk(BleTransportChunk chunk) {
    if (chunk.isBinary) {
      telemetryController?.onBinaryPacket(chunk.bytes, source: chunk.source);
      return;
    }

    final lines = _framer.addChunk(chunk.bytes);
    for (final line in lines) {
      repository.handleIncomingLine(line, source: chunk.source);
      if (line.startsWith('wind:')) {
        telemetryController?.onLine(line, source: chunk.source);
      }
    }
  }

  void _handleDependencyChanged() {
    if (_lastConnected != transport.isConnected) {
      _lastConnected = transport.isConnected;
      if (!_lastConnected) {
        _framer.clear();
        repository.handleDisconnected();
        telemetryController?.reset();
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    transport.removeListener(_handleDependencyChanged);
    repository.removeListener(_handleDependencyChanged);
    unawaited(_chunkSubscription.cancel());
    super.dispose();
  }

  List<N2kDeviceInfo> _mergeDevices(
    List<N2kDeviceInfo> snapshotDevices,
    List<N2kDeviceInfo> decodedDevices,
    {required bool allowFallbackTelemetry}
  ) {
    // Snapshot is authoritative for device identity (name, model, category).
    // Start from snapshot; decoded devices only augment with live-frame data.
    final merged = <int, N2kDeviceInfo>{
      for (final d in snapshotDevices) d.sourceAddress: d,
    };

    for (final decoded in decodedDevices) {
      final existing = merged[decoded.sourceAddress];
      if (existing != null) {
        // Snapshot already covers this src — merge in live-frame flags only.
        merged[decoded.sourceAddress] = existing.copyWith(
          online: existing.online || decoded.online,
          lastSeen: existing.lastSeen ?? decoded.lastSeen,
          hasAddressClaim: existing.hasAddressClaim || decoded.hasAddressClaim,
          hasProductInfo: existing.hasProductInfo || decoded.hasProductInfo,
          hasConfigurationInfo:
              existing.hasConfigurationInfo || decoded.hasConfigurationInfo,
          hasTxPgnList: existing.hasTxPgnList || decoded.hasTxPgnList,
          hasRxPgnList: existing.hasRxPgnList || decoded.hasRxPgnList,
          hasLiveWindData: existing.hasLiveWindData || decoded.hasLiveWindData,
          serialNumber: existing.serialNumber ?? decoded.serialNumber,
          softwareVersion: existing.softwareVersion ?? decoded.softwareVersion,
          modelVersion: existing.modelVersion ?? decoded.modelVersion,
          manufacturerText: existing.manufacturerText ?? decoded.manufacturerText,
          installationDescription1:
              existing.installationDescription1 ?? decoded.installationDescription1,
          installationDescription2:
              existing.installationDescription2 ?? decoded.installationDescription2,
          supportedPgns: existing.supportedPgns.isEmpty
              ? decoded.supportedPgns
              : existing.supportedPgns,
          extraData: <String, dynamic>{...decoded.extraData, ...existing.extraData},
        );
        } else if (!decoded.hasGatewayFallbackName ||
          (allowFallbackTelemetry &&
            (decoded.hasProductInfo || decoded.hasConfigurationInfo))) {
        // Not in snapshot but carries real data from live CAN frames — show it.
        // Fallback-name devices are suppressed on initial page load, but shown
        // only when telemetry has real identity (product/config) and snapshot
        // did not arrive (for timeout paths).
        merged[decoded.sourceAddress] = decoded;
      }
    }

    final values = merged.values.toList(growable: false)
      ..sort((a, b) => a.sourceAddress.compareTo(b.sourceAddress));
    return List<N2kDeviceInfo>.unmodifiable(values);
  }
}