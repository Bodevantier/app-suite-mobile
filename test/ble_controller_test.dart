import 'package:ble_application/controllers/ble_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses telemetry from a complete decoded line', () {
    final controller = BleController();

    controller.onLine(
      'wind:spd=5.20,ang=45.0,ref=3 hdg:123.4deg gps:54.12345,10.54321 bat:12.50V/1.20A/25.0C',
      source: 'test',
    );

    expect(controller.latestSource, 'test');
    expect(controller.latestUtf8, startsWith('wind:spd=5.20'));
    // ref=3 → not Apparent → trueWind*
    expect(controller.telemetry.trueWindSpeedMs, 5.2);
    expect(controller.telemetry.trueWindAngleDeg, 45.0);
    expect(controller.telemetry.windQuality, 3);
    expect(controller.telemetry.headingDeg, 123.4);
    expect(controller.telemetry.gps, '54.12345,10.54321');
    expect(controller.telemetry.batteryV, 12.5);
  });

  test('parses telemetry from notification bytes', () {
    final controller = BleController();

    controller.onNotification(
      'wind:spd=3.10,ang=182.5,ref=2 hdg:90.0deg gps:- bat:-'.codeUnits,
      source: 'notify',
    );

    expect(controller.latestSource, 'notify');
    // ref=2 → Apparent → apparentWind*
    expect(controller.telemetry.apparentWindSpeedMs, 3.1);
    expect(controller.telemetry.apparentWindAngleDeg, 182.5);
    expect(controller.telemetry.windQuality, 2);
    expect(controller.telemetry.headingDeg, 90.0);
  });

  test('parses telemetry from binary frame batches', () {
    final controller = BleController();

    controller.onBinaryPacket(<int>[
      1, 1, 1, 0, 2, 0, 0, 0,
      0x23, 0x02, 0xfd, 0x09,
      8,
      0x05,
      0x00, 0x20, 0x03, 0x34, 0x12, 0x00, 0x00, 0x00,
      0x21, 0x01, 0xf8, 0x09,
      8,
      0x05,
      0x80, 0x96, 0x98, 0x00, 0x00, 0x2d, 0x31, 0x01,
    ]);

    // binary wind frame: data[5]=0x00 → ref=0 → trueWind*
    expect(controller.telemetry.trueWindSpeedMs, 8.0);
    expect(controller.telemetry.trueWindAngleDeg, isNotNull);
    expect(controller.telemetry.gps, '1.00000,2.00000');
  });
}