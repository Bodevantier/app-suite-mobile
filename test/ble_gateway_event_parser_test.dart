import 'package:ble_application/ble/models/ble_gateway_event.dart';
import 'package:ble_application/ble/parsers/ble_gateway_event_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parser = BleGatewayEventParser();

  test('parses request sent events', () {
    final event = parser.parse('device_list request sent id=12');

    expect(event.type, BleGatewayEventType.requestSent);
    expect(event.requestId, 12);
  });

  test('parses device progress events', () {
    final event = parser.parse('device_list device 3/7 src=45');

    expect(event.type, BleGatewayEventType.deviceProgress);
    expect(event.index, 3);
    expect(event.total, 7);
    expect(event.src, 45);
  });

  test('returns unknown for unsupported lines', () {
    final event = parser.parse('something else entirely');

    expect(event.type, BleGatewayEventType.unknown);
    expect(event.rawLine, 'something else entirely');
  });
}