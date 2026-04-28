import 'dart:math' as math;

import '../models/telemetry_data.dart';
import 'models/n2k_frame.dart';

class N2kTelemetryDecoder {
  static const int pgnWind = 130306;
  static const int pgnHeading = 127250;
  static const int pgnPositionRapid = 129025;
  static const int pgnCOGSOGRapid = 129026;
  static const int pgnBattery = 127508;
  static const int pgnTemperatureExt = 130316;

  TelemetryData decode(Iterable<N2kFrame> frames, {TelemetryData? previous}) {
    var telemetry = previous ?? TelemetryData.empty();

    for (final frame in frames) {
      final data = frame.data;
      switch (frame.pgn) {
        case pgnWind:
          if (frame.dlc >= 6) {
            final ref = data[5] & 0x07; // bits 0–2: 2 = Apparent, 0/1 = True
            final speedMs = _readUint16Le(data, 1) * 0.01;
            final rawDeg = _radToDeg(_readUint16Le(data, 3) * 0.0001);
            // Use NMEA 2000 angle as-is and normalize to [0, 360).
            final angleDeg = rawDeg % 360.0;
            if (ref == 2) {
              telemetry = telemetry.copyWith(
                apparentWindSpeedMs: speedMs,
                apparentWindAngleDeg: angleDeg,
                windQuality: data[5],
                rawText: 'binary:wind',
                updatedAt: DateTime.now(),
              );
            } else {
              // ref=0 (True North) or ref=1 (Magnetic): angle is the geographic
              // wind direction, NOT angle-from-bow. Convert using current heading.
              final heading = telemetry.headingDeg;
              if (heading != null) {
                var twa = (angleDeg - heading) % 360.0;
                if (twa < 0) twa += 360.0;
                telemetry = telemetry.copyWith(
                  trueWindSpeedMs: speedMs,
                  trueWindAngleDeg: twa,
                  windQuality: data[5],
                  rawText: 'binary:wind',
                  updatedAt: DateTime.now(),
                );
              } else {
                telemetry = telemetry.copyWith(
                  trueWindSpeedMs: speedMs,
                  trueWindAngleDeg: angleDeg,
                  windQuality: data[5],
                  rawText: 'binary:wind',
                  updatedAt: DateTime.now(),
                );
              }
              // No heading available — keep speed only; convert angle later.
            }
          }
          break;
        case pgnHeading:
          if (frame.dlc >= 3) {
            telemetry = telemetry.copyWith(
              headingDeg: _radToDeg(_readUint16Le(data, 1) * 0.0001),
              rawText: 'binary:heading',
              updatedAt: DateTime.now(),
            );
          }
          break;
        case pgnPositionRapid:
          // PGN 129025: 4 bytes latitude (1e-7 deg), 4 bytes longitude (1e-7 deg)
          if (frame.dlc >= 8) {
            final latitude = _readInt32Le(data, 0) / 10000000.0;
            final longitude = _readInt32Le(data, 4) / 10000000.0;
            telemetry = telemetry.copyWith(
              latitude: latitude,
              longitude: longitude,
              gps: '${latitude.toStringAsFixed(5)},${longitude.toStringAsFixed(5)}',
              rawText: 'binary:gps',
              updatedAt: DateTime.now(),
            );
          }
          break;
        case pgnCOGSOGRapid:
          // PGN 129026: byte 0 = SID, byte 1 bits 0-1 = ref, bytes 2-3 = COG (1e-4 rad),
          //             bytes 4-5 = SOG (1e-2 m/s)
          if (frame.dlc >= 6) {
            final cogRad = _readUint16Le(data, 2) * 0.0001;
            final sogMs = _readUint16Le(data, 4) * 0.01;
            telemetry = telemetry.copyWith(
              cogDeg: _radToDeg(cogRad),
              sogMs: sogMs,
              rawText: 'binary:cogsog',
              updatedAt: DateTime.now(),
            );
          }
          break;
        case pgnBattery:
          if (frame.dlc >= 7) {
            telemetry = telemetry.copyWith(
              batteryV: _readUint16Le(data, 1) * 0.01,
              rawText: 'binary:battery',
              updatedAt: DateTime.now(),
            );
          }
          break;
        case pgnTemperatureExt:
          // PGN 130316: byte 0 = SID, byte 1 = instance, byte 2 = source,
          //             bytes 3-5 = actual temperature (uint24 LE, 0.001 K resolution)
          if (frame.dlc >= 6) {
            final tempK = _readUint24Le(data, 3) * 0.001;
            telemetry = telemetry.copyWith(
              temperatureC: tempK - 273.15,
              rawText: 'binary:temperature',
              updatedAt: DateTime.now(),
            );
          }
          break;
      }
    }

    return telemetry;
  }

  double _radToDeg(double radians) {
    return radians * 180.0 / math.pi;
  }

  int _readUint16Le(List<int> bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  int _readUint24Le(List<int> bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
  }

  int _readInt32Le(List<int> bytes, int offset) {
    final value = bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
    return value & 0x80000000 != 0 ? value - 0x100000000 : value;
  }
}