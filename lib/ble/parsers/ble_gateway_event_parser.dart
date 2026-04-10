import '../models/ble_gateway_event.dart';

class BleGatewayEventParser {
  BleGatewayEvent parse(String line, {DateTime? occurredAt}) {
    final normalizedLine = line.trim();
    final timestamp = occurredAt ?? DateTime.now();

    final requestSentMatch = RegExp(
      r'^device_list request sent id=(\d+)$',
      caseSensitive: false,
    ).firstMatch(normalizedLine);
    if (requestSentMatch != null) {
      return BleGatewayEvent(
        type: BleGatewayEventType.requestSent,
        rawLine: normalizedLine,
        occurredAt: timestamp,
        requestId: int.tryParse(requestSentMatch.group(1)!),
      );
    }

    final beginMatch = RegExp(
      r'^device_list begin id=(\d+) count=(\d+)$',
      caseSensitive: false,
    ).firstMatch(normalizedLine);
    if (beginMatch != null) {
      return BleGatewayEvent(
        type: BleGatewayEventType.begin,
        rawLine: normalizedLine,
        occurredAt: timestamp,
        requestId: int.tryParse(beginMatch.group(1)!),
        count: int.tryParse(beginMatch.group(2)!),
      );
    }

    final deviceProgressMatch = RegExp(
      r'^device_list device (\d+)/(\d+) src=(\d+)$',
      caseSensitive: false,
    ).firstMatch(normalizedLine);
    if (deviceProgressMatch != null) {
      return BleGatewayEvent(
        type: BleGatewayEventType.deviceProgress,
        rawLine: normalizedLine,
        occurredAt: timestamp,
        index: int.tryParse(deviceProgressMatch.group(1)!),
        total: int.tryParse(deviceProgressMatch.group(2)!),
        src: int.tryParse(deviceProgressMatch.group(3)!),
      );
    }

    final completeMatch = RegExp(
      r'^device_list complete id=(\d+) devices=(\d+)$',
      caseSensitive: false,
    ).firstMatch(normalizedLine);
    if (completeMatch != null) {
      return BleGatewayEvent(
        type: BleGatewayEventType.complete,
        rawLine: normalizedLine,
        occurredAt: timestamp,
        requestId: int.tryParse(completeMatch.group(1)!),
        count: int.tryParse(completeMatch.group(2)!),
      );
    }

    final timeoutMatch = RegExp(
      r'^device_list timeout id=(\d+)$',
      caseSensitive: false,
    ).firstMatch(normalizedLine);
    if (timeoutMatch != null) {
      return BleGatewayEvent(
        type: BleGatewayEventType.timeout,
        rawLine: normalizedLine,
        occurredAt: timestamp,
        requestId: int.tryParse(timeoutMatch.group(1)!),
      );
    }

    return BleGatewayEvent(
      type: BleGatewayEventType.unknown,
      rawLine: normalizedLine,
      occurredAt: timestamp,
    );
  }
}