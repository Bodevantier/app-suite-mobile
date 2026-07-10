import 'package:ble_application/models/telemetry_data.dart';
import 'package:ble_application/n2k/models/n2k_frame.dart';
import 'package:ble_application/n2k/n2k_telemetry_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a CAN id for a single-frame PGN from the given node.
int _canId(int pgn, int source) {
  final dataPage = (pgn >> 16) & 0x01;
  final pduFormat = (pgn >> 8) & 0xff;
  final pduSpecific = pgn & 0xff;
  return (6 << 26) |
      (dataPage << 24) |
      (pduFormat << 16) |
      (pduSpecific << 8) |
      source;
}

/// Builds a PGN 127505 (Fluid Level) frame.
N2kFrame _fluidLevelFrame({
  required int source,
  required double levelPct,
  int instance = 0,
  int typeCode = 0,
  int capacityRaw = 0xFFFFFFFF,
}) {
  final levelRaw = (levelPct / 0.004).round();
  return N2kFrame(
    canId: _canId(N2kTelemetryDecoder.pgnFluidLevel, source),
    dlc: 8,
    flags: 0,
    data: <int>[
      ((typeCode & 0x0f) << 4) | (instance & 0x0f),
      levelRaw & 0xff,
      (levelRaw >> 8) & 0xff,
      capacityRaw & 0xff,
      (capacityRaw >> 8) & 0xff,
      (capacityRaw >> 16) & 0xff,
      (capacityRaw >> 24) & 0xff,
      0xff,
    ],
  );
}

/// Builds a PGN 130312 (Temperature) frame.
N2kFrame _temperatureFrame({required int source, required double celsius}) {
  final raw = ((celsius + 273.15) / 0.01).round();
  return N2kFrame(
    canId: _canId(N2kTelemetryDecoder.pgnTemperature, source),
    dlc: 8,
    flags: 0,
    data: <int>[0, 0, 0, raw & 0xff, (raw >> 8) & 0xff, 0xff, 0xff, 0xff],
  );
}

void main() {
  test('bySource keeps telemetry from different nodes separate', () {
    final decoder = N2kTelemetryDecoder();
    final bySource = <int, TelemetryData>{};

    var combined = decoder.decode(
      [
        _fluidLevelFrame(source: 0x23, levelPct: 80, typeCode: 1), // Water
        _fluidLevelFrame(source: 0x42, levelPct: 25, typeCode: 0), // Fuel
        _temperatureFrame(source: 0x51, celsius: 18),
        _temperatureFrame(source: 0x52, celsius: 65),
      ],
      bySource: bySource,
    );
    // Later frames from one node must not disturb the others.
    combined = decoder.decode(
      [_fluidLevelFrame(source: 0x42, levelPct: 24, typeCode: 0)],
      previous: combined,
      bySource: bySource,
    );

    final water = bySource[0x23]!;
    expect(water.fluidLevelPct, closeTo(80, 0.01));
    expect(water.fluidType, 'Water');

    final fuel = bySource[0x42]!;
    expect(fuel.fluidLevelPct, closeTo(24, 0.01));
    expect(fuel.fluidType, 'Fuel');

    expect(bySource[0x51]!.temperatureC, closeTo(18, 0.01));
    expect(bySource[0x52]!.temperatureC, closeTo(65, 0.01));
    expect(bySource[0x60], isNull);

    // The combined view still reflects the last writer, as before.
    expect(combined.fluidLevelPct, closeTo(24, 0.01));
  });

  test('unavailable fluid type keeps the last label from the same node', () {
    final decoder = N2kTelemetryDecoder();
    final bySource = <int, TelemetryData>{};

    decoder.decode(
      [_fluidLevelFrame(source: 0x23, levelPct: 80, typeCode: 1)], // Water
      bySource: bySource,
    );
    decoder.decode(
      // typeCode 15 = type unavailable in this frame.
      [_fluidLevelFrame(source: 0x23, levelPct: 79, typeCode: 15)],
      bySource: bySource,
    );

    final water = bySource[0x23]!;
    expect(water.fluidLevelPct, closeTo(79, 0.01));
    expect(water.fluidType, 'Water');
  });

  test('decode without bySource still returns combined telemetry', () {
    final decoder = N2kTelemetryDecoder();

    final telemetry = decoder.decode([
      _fluidLevelFrame(source: 0x23, levelPct: 50, typeCode: 1),
    ]);

    expect(telemetry.fluidLevelPct, closeTo(50, 0.01));
    expect(telemetry.fluidType, 'Water');
  });
}
