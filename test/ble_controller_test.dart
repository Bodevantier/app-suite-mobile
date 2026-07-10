import 'package:ble_application/controllers/ble_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('latestUtf8 reflects the last text line received via onLine', () {
    final controller = BleController();

    controller.onLine('hello-world', source: 'test');

    expect(controller.latestSource, 'test');
    expect(controller.latestUtf8, 'hello-world');
    // Text-format telemetry is no longer parsed; telemetry stays empty.
    expect(controller.telemetry.headingDeg, isNull);
  });

  test('parses telemetry from binary frame batches', () {
    final controller = BleController();

    controller.onBinaryPacket(<int>[
      1, 1, 1, 0, 2, 0,
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

  test('telemetryFor keeps per-node values apart for a shared PGN', () {
    final controller = BleController();

    // Two PGN 127505 (Fluid Level, canId 0x19F211xx) frames from different
    // source addresses: src 0x23 water 80 % and src 0x42 fuel 25 %.
    controller.onBinaryPacket(<int>[
      1, 1, 1, 0, 2, 0,
      0x23, 0x11, 0xf2, 0x19,
      8,
      0x00,
      0x10, 0x20, 0x4e, 0xff, 0xff, 0xff, 0xff, 0xff,
      0x42, 0x11, 0xf2, 0x19,
      8,
      0x00,
      0x00, 0x6a, 0x18, 0xff, 0xff, 0xff, 0xff, 0xff,
    ]);

    expect(controller.telemetryFor(0x23).fluidLevelPct, closeTo(80, 0.01));
    expect(controller.telemetryFor(0x23).fluidType, 'Water');
    expect(controller.telemetryFor(0x42).fluidLevelPct, closeTo(25, 0.01));
    expect(controller.telemetryFor(0x42).fluidType, 'Fuel');
    // Combined view holds the last writer (fuel), as before.
    expect(controller.telemetry.fluidLevelPct, closeTo(25, 0.01));

    controller.reset();
    expect(controller.telemetryFor(0x23).fluidLevelPct, isNull);
  });
}
