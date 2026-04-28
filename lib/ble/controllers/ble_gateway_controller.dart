import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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
    telemetryController?.addListener(_handleDependencyChanged);
    _chunkSubscription = transport.chunks.listen(_handleChunk);
    _lastConnected = transport.isConnected;
  }

  final BleGatewayTransportService transport;
  final BleGatewayRepository repository;
  final BleController? telemetryController;
  final NewlineMessageFramer _framer;

  late final StreamSubscription<BleTransportChunk> _chunkSubscription;
  bool _lastConnected = false;

  List<ScanResult> get discoveredDevices => transport.devices;
  BluetoothDevice? get connectedDevice => transport.connectedDevice;
  bool get isScanning => transport.isScanning;
  bool get isConnecting => transport.isConnecting;
  bool get isConnected => transport.isConnected;
  bool get hasNotifyCharacteristic => transport.hasNotifyCharacteristic;
  bool get hasCommandCharacteristic => transport.hasCommandCharacteristic;
  String get bleStatus => transport.status;
  bool get n2kScanInProgress => telemetryController?.n2kScanInProgress ?? false;
  bool get n2kScanComplete => telemetryController?.n2kScanComplete ?? false;
  List<N2kDeviceInfo> get devices {
    // Merge binary (live-data flags) + text-snapshot (proper names).
    // The STM32 sends a text snapshot every ~30 s with resolved device names;
    // the binary N2K tracker has live wind/temperature flags and online status.
    final binary = telemetryController?.decodedDevices ?? const <N2kDeviceInfo>[];
    final text = repository.devices;

    if (binary.isEmpty && text.isEmpty) {
      return const <N2kDeviceInfo>[];
    }
    if (binary.isEmpty) {
      return text.toList();
    }
    if (text.isEmpty) {
      return List<N2kDeviceInfo>.unmodifiable(binary);
    }

    // Build merged map keyed by source address.
    final bySource = <int, N2kDeviceInfo>{};
    for (final d in binary) {
      bySource[d.src] = d;
    }
    for (final t in text) {
      final b = bySource[t.src];
      if (b == null) {
        // Device only known via text path.
        bySource[t.src] = t;
      } else {
        // Overlay text-path names when binary has generic placeholders.
        // The text path knows the authoritative device function/category from
        // the STM32 (which reads it from N2K AddressClaim). When the text path
        // says a device is a temperature sensor, clear the live-wind flag that
        // the binary tracker may have set because PGN 130306 happens to be
        // broadcast by that node.
        // Use text-path category when binary has no AddressClaim yet.
        final textCategory = (b.category == 'unknown' && t.category != 'unknown')
            ? t.category
            : b.category;
        final isTextTemp = textCategory == 'temperature';
        bySource[t.src] = b.copyWith(
          name: _pickBetter(t.name, b.name) ? t.name : b.name,
          model: _pickBetterModel(t.model, b.model) ? t.model : b.model,
          manufacturer: _pickBetterMfr(t.manufacturer, b.manufacturer)
              ? t.manufacturer
              : b.manufacturer,
          category: textCategory,
          hasProductInfo: b.hasProductInfo || t.hasProductInfo,
          hasAddressClaim: b.hasAddressClaim || t.hasAddressClaim,
          // If the authoritative category is temperature, suppress the live-wind
          // flag so isWindDevice stays false and the correct icon/chip shows.
          hasLiveWindData: isTextTemp ? false : b.hasLiveWindData,
        );
      }
    }
    final merged = bySource.values
        .where((d) => !d.isBleGatewayDevice)
        .toList()
      ..sort((a, b) => a.src.compareTo(b.src));
    return List<N2kDeviceInfo>.unmodifiable(merged);
  }

  /// Returns true if [candidate] is a better name than [current].
  static bool _pickBetter(String candidate, String current) {
    if (candidate == '-' || candidate.isEmpty) return false;
    final lc = current.toLowerCase();
    return lc.startsWith('n2k node src') ||
        lc == 'unknown device' ||
        lc == 'unknown' ||
        current == '-';
  }

  static bool _pickBetterModel(String candidate, String current) {
    if (candidate == '-' || candidate.isEmpty) return false;
    final lc = current.toLowerCase();
    return lc == 'unknown model' || current == '-';
  }

  static bool _pickBetterMfr(String candidate, String current) {
    if (candidate == '-' || candidate.isEmpty) return false;
    final lc = current.toLowerCase();
    return lc.startsWith('manufacturer code') ||
        lc == 'unknown manufacturer' ||
        current == '-';
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

  Future<void> connect(ScanResult result) {
    return transport.connect(result);
  }

  Future<void> disconnect() async {
    await transport.disconnect();
  }

  Future<void> shutdown() async {
    await transport.shutdown();
  }

  Future<void> requestDeviceList() async {
    // Start the scan window BEFORE writing the command so any AddressClaim
    // frames already in the BLE notification pipeline are captured, not lost.
    telemetryController?.startDeviceScan();
    try {
      await transport.writeCommandLine(
        GatewayCommand.requestDeviceList().toCommandLine(),
      );
    } catch (error) {
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
    telemetryController?.removeListener(_handleDependencyChanged);
    unawaited(_chunkSubscription.cancel());
    super.dispose();
  }

}