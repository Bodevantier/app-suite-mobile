import 'package:flutter/foundation.dart';

import '../../models/n2k_device_info.dart';
import '../../n2k/n2k_device_class.dart';
import '../models/device_list_snapshot.dart';

class DeviceListTextParser {
  String _ts() {
    final now = DateTime.now().toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.${three(now.millisecond)}Z';
  }

  DeviceListSnapshot? tryParseSnapshotHeader(String line) {
    final normalizedLine = line.trim();
    if (!normalizedLine.toLowerCase().startsWith('device_list snapshot ')) {
      return null;
    }

    debugPrint('[${_ts()}] [PARSER] snapshot header: $normalizedLine');
    final fields = _parseFields(
      normalizedLine.substring('device_list snapshot '.length),
    );
    final requestId = _parseInt(fields['id']);
    if (requestId == null) {
      debugPrint('[${_ts()}] [PARSER] ERROR: snapshot header missing id — fields=$fields');
      return null;
    }

    final complete = _parseBool(fields['complete']);
    debugPrint('[${_ts()}] [PARSER] snapshot header parsed: id=$requestId complete=$complete expected=${fields["expected"]} received=${fields["received"]}');
    return DeviceListSnapshot(
      type: 'device_list',
      rawMessage: normalizedLine,
      snapshotRequestId: requestId,
      snapshotInProgress: !complete,
      snapshotComplete: complete,
      snapshotExpected: _parseInt(fields['expected']),
      snapshotReceived: _parseInt(fields['received']),
      requestPending: !complete,
      pendingRequestId: complete ? null : requestId,
      malformedDeviceListMessages: _parseInt(fields['malformed']) ?? 0,
      completedSnapshots: _parseInt(fields['completed']) ?? 0,
      droppedSnapshots: _parseInt(fields['dropped']) ?? 0,
      unknownPacketTypes: _parseInt(fields['unknown']) ?? 0,
      spiParseErrors: _parseInt(fields['parse']) ?? 0,
      devices: const <N2kDeviceInfo>[],
    );
  }

  N2kDeviceInfo? tryParseSnapshotDevice(String line) {
    final normalizedLine = line.trim();
    if (!normalizedLine.toLowerCase().startsWith('device ')) {
      return null;
    }

    debugPrint('[${_ts()}] [PARSER] device line: $normalizedLine');
    final fields = _parseFields(normalizedLine.substring('device '.length));
    debugPrint('[${_ts()}] [PARSER] device fields: $fields');
    final src = _parseInt(fields['src']);
    if (src == null) {
      debugPrint('[${_ts()}] [PARSER] ERROR: device line missing src');
      return null;
    }

    final isGateway = _parseBool(fields['gateway']);
    final productCode = _parseInt(fields['product']);
    final manufacturerCode = _parseInt(fields['mfg']);
    final nameValue = _normalizeText(fields['namevalue']);
    final rawName = _normalizeText(fields['name']);
    // When the gateway has no model ID it falls back to emitting the 16-char hex
    // NAME as the name field.  Treat that as "no real name" so the app shows the
    // standard fallback label instead of a raw hex string.
    final name = (rawName != null && rawName == nameValue) ? null : rawName;
    final model = _normalizeText(fields['model']);
    debugPrint('[${_ts()}] [PARSER] device src=$src gateway=$isGateway rawName=$rawName nameValue=$nameValue name=$name model=$model productCode=$productCode');
    final manufacturer = _normalizeText(fields['manufacturer']);
    final category = _normalizeText(fields['category']);
    final serial = _normalizeText(fields['serial']);
    final softwareVersion = _normalizeText(fields['sw']);
    final modelVersion = _normalizeText(fields['modelversion']);
    final installation1 = _normalizeText(fields['install1']);
    final installation2 = _normalizeText(fields['install2']);
    final deviceClass = _parseInt(fields['deviceclass']);
    final deviceFunction = _parseInt(fields['devicefunction']);

    final result = N2kDeviceInfo(
      src: src,
      name: name ?? (isGateway ? 'SDolve NMEA200 Bluetooth' : 'N2K node src $src'),
      model: model ?? modelVersion ?? 'Unknown model',
      manufacturer: manufacturer ??
          (isGateway
              ? 'SDolve'
              : (manufacturerCode != null
                    ? 'Manufacturer code $manufacturerCode'
                    : 'Unknown manufacturer')),
      category: category ?? (isGateway ? 'gateway' : n2kCategoryFromCodes(deviceClass, deviceFunction) ?? 'unknown'),
      online: _parseBool(fields['online']),
      hasAddressClaim: _parseBool(fields['hasaddressclaim']),
      hasConfigurationInfo: _parseBool(fields['hasconfigurationinfo']),
      hasProductInfo: _parseBool(fields['hasproductinfo']) || (productCode != null && productCode > 0) || model != null,
      hasTxPgnList: _parseBool(fields['tx']),
      hasRxPgnList: _parseBool(fields['rx']),
      serialNumber: serial,
      softwareVersion: softwareVersion,
      modelVersion: modelVersion,
      manufacturerText: manufacturer,
      installationDescription1: installation1,
      installationDescription2: installation2,
      deviceClass: deviceClass,
      deviceFunction: deviceFunction,
      nameValue: nameValue,
      extraData: <String, dynamic>{
        if (isGateway) 'gateway': true,
        'productCode':? productCode,
        'manufacturerCode':? manufacturerCode,
        ...fields,
      },
    );
    debugPrint('[${_ts()}] [PARSER] device built: src=$src name=${result.name} model=${result.model} hasProductInfo=${result.hasProductInfo}');
    return result;
  }

  Map<String, String> _parseFields(String text) {
    final fields = <String, String>{};
    final matches = RegExp(
      r'([A-Za-z][A-Za-z0-9]*)=([^=]+?)(?=\s+[A-Za-z][A-Za-z0-9]*=|$)',
    ).allMatches(text);

    for (final match in matches) {
      fields[match.group(1)!.trim().toLowerCase()] =
          match.group(2)!.trim();
    }

    return fields;
  }

  int? _parseInt(String? value) {
    if (value == null) {
      return null;
    }
    return int.tryParse(value.trim());
  }

  bool _parseBool(String? value) {
    if (value == null) {
      return false;
    }

    switch (value.trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
        return true;
      default:
        return false;
    }
  }

  String? _normalizeText(String? value) {
    if (value == null) {
      return null;
    }

    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '-') {
      return null;
    }
    return trimmed;
  }
}