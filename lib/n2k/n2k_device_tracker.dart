import 'package:flutter/foundation.dart';

import '../models/n2k_device_info.dart';
import 'models/n2k_fast_packet_message.dart';
import 'models/n2k_frame.dart';
import 'n2k_device_class.dart';
import 'n2k_fast_packet_reassembler.dart';

class N2kDeviceTracker {
  static const int pgnAddressClaim = 60928;
  static const int pgnPgnList = 126464;
  static const int pgnProductInfo = 126996;
  static const int pgnConfigInfo = 126998;
  static const int pgnWind = 130306;
  static const int pgnTemperatureExt = 130316;

  /// Quiet-window: scan considered done when no device-identity frame
  /// arrives for this long after the last one (mirrors Test-16).
  static const Duration _quietWindow = Duration(milliseconds: 500);

  /// Minimum scan duration before the quiet-window is allowed to fire.
  /// N2K devices broadcast AddressClaim spontaneously every ~10 s, so we
  /// must stay open past that window even if src=15 responds immediately.
  static const Duration _minScanDuration = Duration(milliseconds: 11000);

  /// Hard cap: scan always ends after this duration, even if frames keep arriving.
  static const Duration _maxScanDuration = Duration(milliseconds: 15000);

  static const _deviceIdentityPgns = {
    pgnAddressClaim,
    pgnPgnList,
    pgnProductInfo,
    pgnConfigInfo,
  };

  final N2kFastPacketReassembler _fastPacketReassembler;
  final Map<int, N2kDeviceInfo> _devices = <int, N2kDeviceInfo>{};
  // Tracks (pgn << 8 | src) so every unique source is logged once per scan.
  final Set<int> _seenPgns = <int>{};

  DateTime? _scanStartedAt;
  DateTime? _lastDeviceFrameAt;
  bool _scanComplete = false;

  N2kDeviceTracker({N2kFastPacketReassembler? fastPacketReassembler})
    : _fastPacketReassembler = fastPacketReassembler ?? N2kFastPacketReassembler();

  List<N2kDeviceInfo> get devices {
    final values = _devices.values.toList(growable: false)
      ..sort((a, b) => a.sourceAddress.compareTo(b.sourceAddress));
    return List<N2kDeviceInfo>.unmodifiable(values);
  }

  /// True once the quiet-window or hard-cap has elapsed after [startScan].
  bool get scanComplete => _scanComplete;

  /// True while a scan is running (between [startScan] and completion).
  bool get scanInProgress => _scanStartedAt != null && !_scanComplete;

  /// Call this when a DEVICE_LIST_REQUEST is sent to the gateway.
  /// Clears stale device info and starts the timing window.
  void startScan() {
    // Clear all stale device data so the new scan starts fresh.
    _devices.clear();
    _fastPacketReassembler.reset();
    _seenPgns.clear();
    final now = DateTime.now().toUtc();
    _scanStartedAt = now;
    _lastDeviceFrameAt = null;
    _scanComplete = false;
    debugPrint('[N2K] scan started');
  }

  void reset() {
    _devices.clear();
    _fastPacketReassembler.reset();
    _seenPgns.clear();
    _scanStartedAt = null;
    _lastDeviceFrameAt = null;
    _scanComplete = false;
  }

  /// Returns true if the scan-complete state changed (caller should
  /// call notifyListeners if it did).
  bool consumeFrames(Iterable<N2kFrame> frames) {
    bool completedThisCall = false;

    for (final frame in frames) {
      _ensureDevice(frame.sourceAddress);
      _markOnline(frame.sourceAddress);

      // DEBUG: log first occurrence of each identity PGN per source during a scan.
      if (scanInProgress && _deviceIdentityPgns.contains(frame.pgn)) {
        final key = (frame.pgn << 8) | frame.sourceAddress;
        if (!_seenPgns.contains(key)) {
          _seenPgns.add(key);
          debugPrint('[N2K] identity frame pgn=${frame.pgn} src=${frame.sourceAddress}');
        }
      }

      if (frame.pgn == pgnAddressClaim) {
        _consumeAddressClaim(frame);
      }
      if (frame.pgn == pgnWind) {
        _markLiveWind(frame.sourceAddress);
      }
      if (frame.pgn == pgnTemperatureExt) {
        _markLiveTemperature(frame.sourceAddress);
      }
      if (frame.pgn == pgnPgnList) {
        _consumePgnList(frame.sourceAddress, frame.data.sublist(0, frame.dlc));
      }

      // Reset quiet-window whenever a device-identity frame arrives.
      if (_deviceIdentityPgns.contains(frame.pgn) && scanInProgress) {
        _lastDeviceFrameAt = DateTime.now().toUtc();
      }

      final message = _fastPacketReassembler.consume(frame);
      if (message != null) {
        if (_deviceIdentityPgns.contains(message.pgn)) {
          debugPrint('[N2K] fast-packet complete: pgn=${message.pgn} src=${message.source} payloadLen=${message.payload.length}');
        }
        _consumeFastPacket(message);
        if (_deviceIdentityPgns.contains(message.pgn) && scanInProgress) {
          _lastDeviceFrameAt = DateTime.now().toUtc();
        }
      }
    }

    // Check timing conditions.
    if (scanInProgress) {
      final now = DateTime.now().toUtc();
      final sinceStart = now.difference(_scanStartedAt!);

      if (sinceStart >= _maxScanDuration) {
        // Hard cap always fires.
        debugPrint('[N2K] scan ended (hard cap ${sinceStart.inMilliseconds}ms) devices=${_devices.length} pgns=${_seenPgns.toList()}');
        _scanComplete = true;
        completedThisCall = true;
      } else if (_lastDeviceFrameAt != null && sinceStart >= _minScanDuration) {
        // Quiet window is only allowed after the minimum duration so the
        // ~10 s spontaneous AddressClaim broadcast cycle has had a chance to run.
        final sinceLastFrame = now.difference(_lastDeviceFrameAt!);
        if (sinceLastFrame >= _quietWindow) {
          debugPrint('[N2K] scan ended (quiet window ${sinceStart.inMilliseconds}ms) devices=${_devices.length} pgns=${_seenPgns.toList()}');
          _scanComplete = true;
          completedThisCall = true;
        }
      }
    }

    return completedThisCall;
  }

  N2kDeviceInfo _ensureDevice(int source) {
    return _devices.putIfAbsent(
      source,
      () => N2kDeviceInfo(
        src: source,
        name: 'N2K node src $source',
        model: 'Unknown model',
        manufacturer: 'Unknown manufacturer',
        category: 'unknown',
        online: true,
      ),
    );
  }

  void _markOnline(int source) {
    final now = DateTime.now().toUtc();
    final device = _ensureDevice(source);
    _devices[source] = device.copyWith(online: true, lastSeen: now);
  }

  void _markLiveWind(int source) {
    final device = _ensureDevice(source);
    _devices[source] = device.copyWith(hasLiveWindData: true);
  }

  void _markLiveTemperature(int source) {
    final device = _ensureDevice(source);
    _devices[source] = device.copyWith(hasLiveTemperatureData: true);
  }

  void _consumeAddressClaim(N2kFrame frame) {
    if (frame.dlc < 8) {
      debugPrint('[N2K] AddressClaim src=${frame.sourceAddress}: dlc=${frame.dlc} < 8, skipped');
      return;
    }
    final name = _readUint64Le(frame.data, 0);
    final manufacturerCode = _readUnsignedBits(name, shift: 21, width: 11);
    final deviceFunction = _readUnsignedBits(name, shift: 40, width: 8);
    final deviceClass = _readUnsignedBits(name, shift: 49, width: 7);
    debugPrint('[N2K] AddressClaim src=${frame.sourceAddress} mfr=$manufacturerCode class=$deviceClass fn=$deviceFunction raw=${frame.data.map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ")}');
    final device = _ensureDevice(frame.sourceAddress);

    _devices[frame.sourceAddress] = device.copyWith(
      hasAddressClaim: true,
      manufacturer: 'Manufacturer code $manufacturerCode',
      category: n2kCategoryFromCodes(deviceClass, deviceFunction) ?? 'unknown',
      extraData: <String, dynamic>{
        ...device.extraData,
        'deviceFunction': deviceFunction,
        'deviceClass': deviceClass,
        'nameValue': name.toRadixString(16).padLeft(16, '0'),
      },
    );
  }

  void _consumeFastPacket(N2kFastPacketMessage message) {
    switch (message.pgn) {
      case pgnProductInfo:
        _consumeProductInfo(message.source, message.payload);
        break;
      case pgnConfigInfo:
        _consumeConfigInfo(message.source, message.payload);
        break;
      case pgnPgnList:
        _consumePgnList(message.source, message.payload);
        break;
    }
  }

  void _consumeProductInfo(int source, List<int> payload) {
    // Minimum: 4 bytes for db-version (2) + product-code (2).
    if (payload.length < 4) {
      return;
    }
    final device = _ensureDevice(source);
    final productCode = _readUint16Le(payload, 2);

    // Each field is read only when enough bytes are present — mirrors the
    // progressive length checks used in the PCB firmware.
    final modelId       = payload.length >= 36  ? _readPaddedAscii(payload, 4,   32) : '';
    final softVersion   = payload.length >= 68  ? _readPaddedAscii(payload, 36,  32) : '';
    final modelVersion  = payload.length >= 100 ? _readPaddedAscii(payload, 68,  32) : '';
    final serial        = payload.length >= 132 ? _readPaddedAscii(payload, 100, 32) : '';

    _devices[source] = device.copyWith(
      hasProductInfo: true,
      // Set name so displayName works without the gateway-fallback path.
      name: modelId.isEmpty ? device.name : modelId,
      model: modelId.isEmpty ? device.model : modelId,
      serialNumber: serial.isEmpty ? device.serialNumber : serial,
      softwareVersion: softVersion.isEmpty ? device.softwareVersion : softVersion,
      modelVersion: modelVersion.isEmpty ? device.modelVersion : modelVersion,
      extraData: <String, dynamic>{
        ...device.extraData,
        'productCode': productCode,
      },
    );
  }

  void _consumeConfigInfo(int source, List<int> payload) {
    final device = _ensureDevice(source);
    var offset = 0;
    final installation1 = _readVarString(payload, offset);
    offset = installation1.nextOffset;
    final installation2 = _readVarString(payload, offset);
    offset = installation2.nextOffset;
    final manufacturerText = _readVarString(payload, offset);

    _devices[source] = device.copyWith(
      hasConfigurationInfo: true,
      // Do NOT override name from installation descriptions — they contain
      // physical location notes (e.g. "masthead anemometer") that may include
      // non-ASCII characters and are not suitable as display names.
      installationDescription1: installation1.text.isEmpty ? device.installationDescription1 : installation1.text,
      installationDescription2: installation2.text.isEmpty ? device.installationDescription2 : installation2.text,
      manufacturerText: manufacturerText.text.isEmpty ? device.manufacturerText : manufacturerText.text,
      manufacturer: manufacturerText.text.isEmpty ? device.manufacturer : manufacturerText.text,
    );
  }

  void _consumePgnList(int source, List<int> payload) {
    if (payload.length < 4) {
      return;
    }
    final device = _ensureDevice(source);
    final listType = payload[0];
    final pgns = <int>[];
    for (var offset = 1; offset + 2 < payload.length; offset += 3) {
      pgns.add(payload[offset] | (payload[offset + 1] << 8) | (payload[offset + 2] << 16));
    }

    _devices[source] = device.copyWith(
      hasTxPgnList: listType == 0 ? true : device.hasTxPgnList,
      hasRxPgnList: listType == 1 ? true : device.hasRxPgnList,
      supportedPgns: <int>{...device.supportedPgns, ...pgns}.toList(growable: false),
    );
  }

  int _readUint16Le(List<int> bytes, int offset) {
    if (offset + 1 >= bytes.length) {
      return 0;
    }
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  BigInt _readUint64Le(List<int> bytes, int offset) {
    var value = BigInt.zero;
    for (var index = 0; index < 8 && (offset + index) < bytes.length; index++) {
      value |= BigInt.from(bytes[offset + index]) << (8 * index);
    }
    return value;
  }

  int _readUnsignedBits(BigInt value, {required int shift, required int width}) {
    final mask = (BigInt.one << width) - BigInt.one;
    return ((value >> shift) & mask).toInt();
  }

  String _readPaddedAscii(List<int> bytes, int offset, int length) {
    final end = offset + length > bytes.length ? bytes.length : offset + length;
    final chars = <int>[];
    for (var index = offset; index < end; index++) {
      final value = bytes[index];
      if (value == 0x00 || value == 0xff) {
        break;
      }
      chars.add(value);
    }
    return String.fromCharCodes(chars).trim();
  }

  _VarString _readVarString(List<int> bytes, int offset) {
    if (offset + 1 >= bytes.length) {
      return _VarString('', bytes.length);
    }
    final fieldLength = bytes[offset];
    final fieldType = bytes[offset + 1];
    if (fieldLength < 2 || fieldType != 0x01) {
      return _VarString('', bytes.length);
    }
    final textStart = offset + 2;
    final textEnd = textStart + fieldLength - 2;
    if (textEnd > bytes.length) {
      return _VarString('', bytes.length);
    }
    final text = _readPaddedAscii(bytes, textStart, fieldLength - 2);
    return _VarString(text, textEnd);
  }
}

class _VarString {
  const _VarString(this.text, this.nextOffset);

  final String text;
  final int nextOffset;
}