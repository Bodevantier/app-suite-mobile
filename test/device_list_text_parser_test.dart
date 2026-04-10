import 'package:ble_application/ble/parsers/device_list_text_parser.dart';
import 'package:ble_application/ble/testing/gateway_protocol_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parser = DeviceListTextParser();

  test('parses device_list snapshot header', () {
    final snapshot = parser.tryParseSnapshotHeader(
      GatewayProtocolFixtures.snapshotTextLines.first,
    );

    expect(snapshot, isNotNull);
    expect(snapshot!.type, 'device_list');
    expect(snapshot.snapshotRequestId, 12);
    expect(snapshot.snapshotComplete, isTrue);
    expect(snapshot.snapshotExpected, 3);
    expect(snapshot.snapshotReceived, 3);
    expect(snapshot.malformedDeviceListMessages, 1);
    expect(snapshot.completedSnapshots, 4);
    expect(snapshot.unknownPacketTypes, 2);
    expect(snapshot.spiParseErrors, 1);
    expect(snapshot.devices, isEmpty);
  });

  test('parses device snapshot line', () {
    final device = parser.tryParseSnapshotDevice(
      GatewayProtocolFixtures.snapshotTextLines[2],
    );

    expect(device, isNotNull);
    expect(device!.sourceAddress, 45);
    expect(device.displayName, 'WS310');
    expect(device.displayModel, 'Wind Sensor Mk2');
    expect(device.displayManufacturer, 'Airmar');
    expect(device.displaySerialNumber, 'SN-45');
    expect(device.displaySoftwareVersion, '1.2.3');
    expect(device.installationDescription1, 'Masthead Wind');
    expect(device.hasTxPgnList, isTrue);
    expect(device.hasRxPgnList, isTrue);
    expect(device.deviceClass, 25);
    expect(device.deviceFunction, 130);
    expect(device.nameValue, '1122334455667788');
  });

  test('parses keys case-insensitively where practical', () {
    final snapshot = parser.tryParseSnapshotHeader(
      'DEVICE_LIST SNAPSHOT ID=22 COMPLETE=0 EXPECTED=7 RECEIVED=2 MALFORMED=1 COMPLETED=5 DROPPED=0 UNKNOWN=4 PARSE=3',
    );
    final device = parser.tryParseSnapshotDevice(
      'DEVICE SRC=45 ONLINE=1 HASADDRESSCLAIM=1 NAME=Masthead Wind MODEL=WS310 TX=1 RX=1',
    );

    expect(snapshot, isNotNull);
    expect(snapshot!.snapshotRequestId, 22);
    expect(snapshot.snapshotComplete, isFalse);
    expect(snapshot.snapshotExpected, 7);
    expect(snapshot.snapshotReceived, 2);
    expect(snapshot.unknownPacketTypes, 4);

    expect(device, isNotNull);
    expect(device!.sourceAddress, 45);
    expect(device.hasAddressClaim, isTrue);
    expect(device.displayName, 'Masthead Wind');
  });

  test('keeps values with spaces until next key token', () {
    final device = parser.tryParseSnapshotDevice(
      'device src=18 online=0 name=Autopilot Controller Mk2 model=AP 200 manufacturer=Helm Works install1=Aft Helm tx=0 rx=1',
    );

    expect(device, isNotNull);
    expect(device!.displayName, 'Autopilot Controller Mk2');
    expect(device.displayModel, 'AP 200');
    expect(device.displayManufacturer, 'Helm Works');
    expect(device.installationDescription1, 'Aft Helm');
    expect(device.hasTxPgnList, isFalse);
    expect(device.hasRxPgnList, isTrue);
  });

  test('returns null for malformed text lines', () {
    expect(parser.tryParseSnapshotHeader('device_list snapshot id='), isNull);
    expect(parser.tryParseSnapshotDevice('device src='), isNull);
  });

  test('parses deviceClass, deviceFunction and nameValue for node without product info', () {
    final device = parser.tryParseSnapshotDevice(
      'device src=23 online=1 hasAddressClaim=1 hasProductInfo=0 hasConfigurationInfo=0 product=0 mfg=2046 name=c0aa8200ffc00001 model=- manufacturer=- serial=- sw=- install1=- install2=- tx=0 rx=0 deviceClass=85 deviceFunction=130 nameValue=c0aa8200ffc00001',
    );

    expect(device, isNotNull);
    expect(device!.sourceAddress, 23);
    expect(device.deviceClass, 85);
    expect(device.deviceFunction, 130);
    expect(device.nameValue, 'c0aa8200ffc00001');
    expect(device.displayName, 'N2K node src 23');
  });
}