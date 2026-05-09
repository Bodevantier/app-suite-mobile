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
  static const int pgnTemperature = 130312;
  static const int pgnFluidLevel = 127505;

  static const List<String> _fluidTypeLabels = <String>[
    'Fuel',         // 0
    'Water',        // 1
    'Gray water',   // 2
    'Live well',    // 3
    'Oil',          // 4
    'Black water',  // 5
    'Fuel gasoline',// 6
  ];

  TelemetryData decode(Iterable<N2kFrame> frames, {TelemetryData? previous}) {
    var telemetry = previous ?? TelemetryData.empty();

    for (final frame in frames) {
      final data = frame.data;
      switch (frame.pgn) {
        case pgnWind:
          if (frame.dlc >= 6) {
            // PGN 130306 byte 5 bits 0-2 = Wind Reference:
            //   0 = True (ground/north referenced, geographic angle)
            //   1 = Magnetic (geographic-style, magnetic referenced)
            //   2 = Apparent (boat-referenced, angle from bow)
            //   3 = True (boat-referenced — angle from bow, like apparent)
            //   4 = True (water-referenced — also boat-frame, angle from bow)
            // Codes 2/3/4 are already in the boat frame; codes 0/1 are
            // geographic and must be rotated by heading to get a TWA.
            final ref = data[5] & 0x07;
            final speedMs = _readUint16Le(data, 1) * 0.01;
            final rawDeg = _radToDeg(_readUint16Le(data, 3) * 0.0001);
            // Use NMEA 2000 angle as-is and normalize to [0, 360).
            final angleDeg = rawDeg % 360.0;
            final isBoatReferenced = (ref == 2) || (ref == 3) || (ref == 4);
            if (ref == 2) {
              telemetry = telemetry.copyWith(
                apparentWindSpeedMs: speedMs,
                apparentWindAngleDeg: angleDeg,
                windQuality: data[5],
                rawText: 'binary:wind',
                updatedAt: DateTime.now(),
              );
            } else if (isBoatReferenced) {
              // ref = 3 or 4 — true wind, but already in boat frame (angle
              // from bow). No heading rotation needed.
              telemetry = telemetry.copyWith(
                trueWindSpeedMs: speedMs,
                trueWindAngleDeg: angleDeg,
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
          // PGN 127250: byte 0 = SID, bytes 1-2 = heading (uint16 LE, 0.0001 rad),
          //             bytes 3-4 = deviation, bytes 5-6 = variation,
          //             byte 7 bits 0-1 = reference (0 = True, 1 = Magnetic,
          //             2 = Error, 3 = Null/unavailable).
          // Wind decoding below treats stored headingDeg as TRUE/geographic
          // when rotating geographic wind into boat frame. Storing magnetic
          // heading here would silently mis-rotate true wind, so we accept
          // only ref == 0 (True). A future improvement: combine magnetic
          // heading with PGN 127258 variation to derive true heading.
          if (frame.dlc >= 8) {
            final ref = data[7] & 0x03;
            if (ref == 0) {
              telemetry = telemetry.copyWith(
                headingDeg: _radToDeg(_readUint16Le(data, 1) * 0.0001),
                rawText: 'binary:heading',
                updatedAt: DateTime.now(),
              );
            }
          } else if (frame.dlc >= 3) {
            // Legacy/short frame: assume true heading (best-effort fallback).
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
          //             bytes 3-5 = actual temperature (uint24 LE, 0.001 K),
          //             bytes 6-7 = set temperature (uint16 LE, 0.1 K, optional).
          // PGN 130316 is an 8-byte single-frame PGN; require full payload to
          // avoid acting on truncated frames.
          if (frame.dlc >= 8) {
            final tempK = _readUint24Le(data, 3) * 0.001;
            telemetry = telemetry.copyWith(
              temperatureC: tempK - 273.15,
              rawText: 'binary:temperature',
              updatedAt: DateTime.now(),
            );
          }
          break;
        case pgnTemperature:
          // PGN 130312: byte 0 = SID, byte 1 = instance, byte 2 = source,
          //             bytes 3-4 = actual temperature (uint16 LE, 0.01 K),
          //             bytes 5-6 = set temperature (uint16 LE, 0.01 K, optional).
          // 8-byte single-frame PGN; require full payload.
          if (frame.dlc >= 8) {
            final tempK = _readUint16Le(data, 3) * 0.01;
            telemetry = telemetry.copyWith(
              temperatureC: tempK - 273.15,
              rawText: 'binary:temperature',
              updatedAt: DateTime.now(),
            );
          }
          break;
        case pgnFluidLevel:
          // PGN 127505 – Fluid Level (single-frame, 8 bytes):
          //   byte 0 low nibble  = Tank instance (0–14, 15 = N/A)
          //   byte 0 high nibble = Fluid type   (0=Fuel, 1=Water, 2=Gray,
          //                                       3=Live well, 4=Oil, 5=Black,
          //                                       6=Fuel gasoline, 14=Error,
          //                                       15=Unavailable)
          //   bytes 1-2 = Level (int16 LE, 0.004 % per LSB)
          //   bytes 3-6 = Capacity (uint32 LE, 0.1 L per LSB)
          //   byte 7 = reserved (0xff)
          if (frame.dlc >= 8) {
            final b0 = data[0];
            final instance = b0 & 0x0f;
            final typeCode = (b0 >> 4) & 0x0f;
            final levelRaw = _readInt16Le(data, 1);
            final levelPct = levelRaw * 0.004;
            final capacityRaw = _readUint32Le(data, 3);
            // 0xFFFFFFFF means "data not available".
            final double? capacityL =
                capacityRaw == 0xFFFFFFFF ? null : capacityRaw * 0.1;
            String? typeLabel;
            if (typeCode < _fluidTypeLabels.length) {
              typeLabel = _fluidTypeLabels[typeCode];
            } else if (typeCode == 14) {
              typeLabel = 'Error';
            } else if (typeCode == 15) {
              typeLabel = null;
            } else {
              typeLabel = 'Type $typeCode';
            }
            telemetry = telemetry.copyWith(
              fluidLevelPct: levelPct,
              fluidType: typeLabel,
              fluidInstance: instance,
              fluidCapacityL: capacityL,
              rawText: 'binary:fluidlevel',
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

  int _readInt16Le(List<int> bytes, int offset) {
    final value = bytes[offset] | (bytes[offset + 1] << 8);
    return value & 0x8000 != 0 ? value - 0x10000 : value;
  }

  int _readUint32Le(List<int> bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
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