import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../n2k/n2k_binary_packet_parser.dart';
import '../n2k/n2k_device_tracker.dart';
import '../n2k/n2k_telemetry_decoder.dart';
import '../models/n2k_device_info.dart';
import '../models/telemetry_data.dart';
import '../services/telemetry_parser.dart';

class BleController extends ChangeNotifier {
  BleController({
    TelemetryParser? parser,
    N2kBinaryPacketParser? binaryPacketParser,
     N2kDeviceTracker? deviceTracker,
    N2kTelemetryDecoder? telemetryDecoder,
  }) : _parser = parser ?? TelemetryParser(),
       _binaryPacketParser = binaryPacketParser ?? N2kBinaryPacketParser(),
       _deviceTracker = deviceTracker ?? N2kDeviceTracker(),
       _telemetryDecoder = telemetryDecoder ?? N2kTelemetryDecoder();

  final TelemetryParser _parser;
  final N2kBinaryPacketParser _binaryPacketParser;
  final N2kDeviceTracker _deviceTracker;
  final N2kTelemetryDecoder _telemetryDecoder;

  TelemetryData _telemetry = TelemetryData.empty();
  String _latestUtf8 = '';
  String _latestSource = 'notification';
  bool _isConnected = false;
  bool _isScanning = false;

  TelemetryData get telemetry => _telemetry;
  String get latestUtf8 => _latestUtf8;
  String get latestSource => _latestSource;
  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  List<N2kDeviceInfo> get decodedDevices => _deviceTracker.devices;

  void onBinaryPacket(List<int> bytes, {String source = 'binary'}) {
    final packet = _binaryPacketParser.parse(bytes);
    if (packet == null) {
      return;
    }

    _latestUtf8 = 'binary:${packet.frames.length}';
    _latestSource = source;
    _deviceTracker.consumeFrames(packet.frames);
    _telemetry = _telemetryDecoder.decode(packet.frames, previous: _telemetry);
    notifyListeners();
  }

  void onLine(String text, {String source = 'notification'}) {
    final decoded = text.trim();
    debugPrint(
      '[BleController] source=$source decoded line="$decoded"',
    );

    _latestUtf8 = decoded;
    _latestSource = source;
    _telemetry = _parser.parse(decoded, previous: _telemetry);

    debugPrint('[BleController] parsed windSpeed=${_telemetry.windSpeed}');
    debugPrint('[BleController] parsed windAngleDeg=${_telemetry.windAngleDeg}');

    debugPrint(
      '[BleController] final parsed telemetry '
      'wind=${_telemetry.windSpeed} '
      'angle=${_telemetry.windAngleDeg} '
      'quality=${_telemetry.windQuality} '
      'heading=${_telemetry.headingDeg} '
      'gps=${_telemetry.gps} '
      'model=${_telemetry.model} '
      'battery=${_telemetry.batteryV} '
      'device=${_telemetry.deviceId}',
    );

    notifyListeners();
  }

  void onNotification(List<int> bytes, {String source = 'notification'}) {
    final decoded = utf8.decode(bytes, allowMalformed: true);
    onLine(decoded, source: source);
  }

  void setConnected(bool value) {
    if (_isConnected == value) {
      return;
    }
    _isConnected = value;
    notifyListeners();
  }

  void setScanning(bool value) {
    if (_isScanning == value) {
      return;
    }
    _isScanning = value;
    notifyListeners();
  }

  void reset() {
    _telemetry = TelemetryData.empty();
    _deviceTracker.reset();
    _latestUtf8 = '';
    _latestSource = 'notification';
    _isConnected = false;
    _isScanning = false;
    notifyListeners();
  }

  void resetTrackedDevices() {
    _deviceTracker.reset();
    notifyListeners();
  }
}
