import 'dart:math' as math;

import '../models/telemetry_data.dart';
import 'models/n2k_fast_packet_message.dart';
import 'models/n2k_frame.dart';
import 'n2k_fast_packet_reassembler.dart';

class N2kTelemetryDecoder {
  static const int pgnWind = 130306;
  static const int pgnHeading = 127250;
  static const int pgnPositionRapid = 129025;
  static const int pgnCOGSOGRapid = 129026;
  static const int pgnBattery = 127508;
  static const int pgnTemperatureExt = 130316;
  static const int pgnTemperature = 130312;
  static const int pgnFluidLevel = 127505;
  static const int pgnEngineParamRapid = 127488;
  static const int pgnMagneticVariation = 127258;
  static const int pgnGnssDop = 129539;
  static const int pgnGnssPositionData = 129029;

  static const List<String> _fluidTypeLabels = <String>[
    'Fuel',         // 0
    'Water',        // 1
    'Gray water',   // 2
    'Live well',    // 3
    'Oil',          // 4
    'Black water',  // 5
    'Fuel gasoline',// 6
  ];

  // PGN 129029 fix method field (byte 31, high nibble).
  static const List<String?> _fixMethodLabels = <String?>[
    'No GNSS',      // 0
    'GNSS',         // 1
    'DGNSS',        // 2
    'Precise GNSS', // 3
    'RTK Fixed',    // 4
    'RTK Float',    // 5
    'DR Mode',      // 6
    'Manual',       // 7
    'Simulator',    // 8
  ];

  final N2kFastPacketReassembler _reassembler = N2kFastPacketReassembler();

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
        case pgnMagneticVariation:
          // PGN 127258 – Magnetic Variation (single-frame, 6 bytes):
          //   byte 0 = SID
          //   byte 1 bits 0-3 = variation source, bits 4-7 = reserved
          //   bytes 2-3 = age of service (uint16 LE, days)
          //   bytes 4-5 = variation (int16 LE, 0.0001 rad; + = East)
          if (frame.dlc >= 6) {
            final varRad = _readInt16Le(data, 4) * 0.0001;
            telemetry = telemetry.copyWith(
              magneticVariationDeg: _radToDeg(varRad),
              updatedAt: DateTime.now(),
            );
          }
          break;
        case pgnGnssDop:
          // PGN 129539 – GNSS DOP (single-frame, 8 bytes):
          //   byte 0 = SID
          //   byte 1 bits 0-2 = desired mode, bits 3-5 = actual mode
          //   bytes 2-3 = HDOP (int16 LE, 0.01)
          //   bytes 4-5 = VDOP (int16 LE, 0.01)
          //   bytes 6-7 = TDOP (int16 LE, 0.01)
          if (frame.dlc >= 6) {
            final hdop = _readInt16Le(data, 2) * 0.01;
            final vdop = _readInt16Le(data, 4) * 0.01;
            telemetry = telemetry.copyWith(
              hdop: hdop,
              vdop: vdop,
              updatedAt: DateTime.now(),
            );
          }
          break;
        case pgnGnssPositionData:
          // PGN 129029 – GNSS Position Data (fast-packet, 43 bytes reassembled).
          // Feed each raw CAN frame into the reassembler; decode when complete.
          final msg = _reassembler.consume(frame);
          if (msg != null) {
            telemetry = _decodeGnssPositionData(msg, telemetry);
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
        case pgnEngineParamRapid:
          // PGN 127488 – Engine Parameters, Rapid Update (single-frame, 8 bytes):
          //   byte 0   = Engine instance (0–14, 255 = N/A)
          //   bytes 1-2 = Engine speed (uint16 LE, 0.25 RPM per LSB)
          //   bytes 3-4 = Boost pressure (uint16 LE, 100 Pa per LSB)
          //   byte 5   = Tilt/trim (int8, 1 % per LSB)
          //   bytes 6-7 = reserved (0xff)
          if (frame.dlc >= 3) {
            final instance = data[0];
            final rpmRaw = _readUint16Le(data, 1);
            // 0xffff = data not available.
            if (rpmRaw != 0xffff) {
              telemetry = telemetry.copyWith(
                engineRpm: rpmRaw * 0.25,
                engineInstance: instance,
                rawText: 'binary:engine',
                updatedAt: DateTime.now(),
              );
            }
          }
          break;
      }
    }

    return telemetry;
  }

  TelemetryData _decodeGnssPositionData(
      N2kFastPacketMessage msg, TelemetryData telemetry) {
    // PGN 129029 reassembled payload layout (43 bytes):
    //   byte 0    : SID
    //   bytes 1-2 : Date (uint16 LE, days from 1970-01-01)
    //   bytes 3-6 : Time (uint32 LE, 1e-4 s from midnight)
    //   bytes 7-14: Latitude  (int64 LE, 1e-16 deg)
    //   bytes 15-22: Longitude (int64 LE, 1e-16 deg)
    //   bytes 23-30: Altitude (int64 LE, 1e-6 m)
    //   byte 31   : GNSS Type (bits 0-3) | Method (bits 4-7)
    //   byte 32   : Integrity (bits 0-1) | reserved
    //   byte 33   : Number of SVs
    //   bytes 34-35: HDOP (int16 LE, 0.01)
    final payload = msg.payload;
    if (payload.length < 34) return telemetry;

    final altRaw = _readInt64Le(payload, 23);
    final gnssTypeByte = payload[31];
    final method = (gnssTypeByte >> 4) & 0x0f;
    final svs = payload[33];

    String? fixType;
    if (method < _fixMethodLabels.length) {
      fixType = _fixMethodLabels[method];
    }

    return telemetry.copyWith(
      gnssAltitudeM: altRaw * 1e-6,
      gnssSatellites: svs,
      gnssFixType: fixType,
      updatedAt: DateTime.now(),
    );
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

  int _readInt64Le(List<int> bytes, int offset) {
    // Dart int is 64-bit on native; bit-combine two 32-bit halves.
    final lo = _readUint32Le(bytes, offset);
    final hi = _readUint32Le(bytes, offset + 4);
    return lo | (hi << 32);
  }
}