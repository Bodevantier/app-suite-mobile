// Generates a small fleet of simulated N2K devices (wind, two temperature
// senders, two tank senders, an engine, and a GPS/compass) and periodically
// feeds them into the real telemetry pipeline via `onBinaryPacket`, so every
// page in the app renders exactly as it would with a real gateway connected.
//
// The frames are built with the actual NMEA 2000 wire format (see
// n2k_wire_format.dart) rather than by poking synthetic values into
// TelemetryData/N2kDeviceInfo directly — that way the real parser, fast-
// packet reassembler, device tracker and telemetry decoder all run
// unmodified, and this file can't drift out of sync with how they decode PGNs.

import 'dart:async';
import 'dart:math' as math;

import '../controllers/ble_controller.dart';
import '../n2k/models/n2k_frame.dart';
import 'n2k_wire_format.dart';

/// Fixed source addresses for each simulated device — public so
/// [seedDefaultDemoDashboards] can bind dashboard tiles to specific demo
/// devices directly, without waiting on/parsing decoded telemetry first.
class DemoDeviceSrc {
  static const int wind = 10;
  static const int engineTemp = 11;
  static const int fridgeTemp = 12;
  static const int fuelTank = 13;
  static const int waterTank = 14;
  static const int engine = 15;
  static const int gps = 16;
}

class _DemoDevice {
  const _DemoDevice({
    required this.src,
    required this.deviceClass,
    required this.deviceFunction,
    required this.model,
    required this.mfrText,
    required this.serial,
    required this.softwareVersion,
    required this.modelVersion,
  });

  final int src;
  final int deviceClass;
  final int deviceFunction;
  final String model;
  final String mfrText;
  final String serial;
  final String softwareVersion;
  final String modelVersion;
}

class DemoDataService {
  DemoDataService({required this.telemetryController});

  final BleController telemetryController;

  static const Duration _tickInterval = Duration(seconds: 1);
  static const int _manufacturerCode = 717; // fictitious "SDolve Marine" code

  static const _wind = _DemoDevice(
    src: DemoDeviceSrc.wind,
    deviceClass: 85, // Environmental
    deviceFunction: 130, // Wind
    model: 'SDolve Wind',
    mfrText: 'SDolve Marine',
    serial: 'SDW-104829',
    softwareVersion: '1.4.2',
    modelVersion: 'Rev B',
  );
  static const _tempEngine = _DemoDevice(
    src: DemoDeviceSrc.engineTemp,
    deviceClass: 85,
    deviceFunction: 160, // Temperature
    model: 'EnviroTemp Engine Bay',
    mfrText: 'SDolve Marine',
    serial: 'SDT-220144',
    softwareVersion: '1.2.0',
    modelVersion: 'Rev A',
  );
  static const _tempFridge = _DemoDevice(
    src: DemoDeviceSrc.fridgeTemp,
    deviceClass: 85,
    deviceFunction: 160,
    model: 'EnviroTemp Fridge',
    mfrText: 'SDolve Marine',
    serial: 'SDT-220145',
    softwareVersion: '1.2.0',
    modelVersion: 'Rev A',
  );
  static const _fuelTank = _DemoDevice(
    src: DemoDeviceSrc.fuelTank,
    deviceClass: 80, // Instrumentation
    deviceFunction: 150, // Fluid level sender (project convention)
    model: 'FuelWatch 200 Tank Sender',
    mfrText: 'SDolve Marine',
    serial: 'SDF-330091',
    softwareVersion: '1.1.3',
    modelVersion: 'Rev C',
  );
  static const _waterTank = _DemoDevice(
    src: DemoDeviceSrc.waterTank,
    deviceClass: 80,
    deviceFunction: 150,
    model: 'AquaWatch 300 Tank Sender',
    mfrText: 'SDolve Marine',
    serial: 'SDF-330092',
    softwareVersion: '1.1.3',
    modelVersion: 'Rev C',
  );
  static const _engine = _DemoDevice(
    src: DemoDeviceSrc.engine,
    deviceClass: 40, // Propulsion
    deviceFunction: 160,
    model: 'Engine Data Interface',
    mfrText: 'SDolve Marine',
    serial: 'SDE-440017',
    softwareVersion: '2.0.1',
    modelVersion: 'Rev A',
  );
  static const _gps = _DemoDevice(
    src: DemoDeviceSrc.gps,
    deviceClass: 50, // Navigation
    deviceFunction: 145, // GPS
    model: 'NavPilot GPS/Compass',
    mfrText: 'SDolve Marine',
    serial: 'SDN-550233',
    softwareVersion: '3.1.0',
    modelVersion: 'Rev D',
  );

  static const _allDevices = [
    _wind,
    _tempEngine,
    _tempFridge,
    _fuelTank,
    _waterTank,
    _engine,
    _gps,
  ];

  // A plausible sailing ground (the Solent, UK) — only used as a starting
  // point for a slowly-meandering simulated GPS track, not a real position.
  static const double _lat0 = 50.7300;
  static const double _lon0 = -1.3200;

  final math.Random _random = math.Random();
  Timer? _timer;
  double _t = 0;
  int _sequence = 0;

  bool get isRunning => _timer != null;

  void start() {
    if (isRunning) return;
    _t = 0;
    _sequence = 0;
    _sendBatch([
      for (final d in _allDevices) ..._identityFrames(d),
      ..._liveFrames(),
    ]);
    _timer = Timer.periodic(_tickInterval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _tick() {
    _t += _tickInterval.inMilliseconds / 1000.0;
    _sendBatch(_liveFrames());
  }

  void _sendBatch(List<N2kFrame> frames) {
    if (frames.isEmpty) return;
    final bytes = packFrameBatch(frames, sequence: _sequence++);
    telemetryController.onBinaryPacket(bytes, source: 'demo');
  }

  // ── Device identity (Address Claim + Product Info + Config Info) ────────

  List<N2kFrame> _identityFrames(_DemoDevice d) {
    final name = buildDeviceName(
      uniqueNumber: 500000 + d.src,
      manufacturerCode: _manufacturerCode,
      deviceFunction: d.deviceFunction,
      deviceClass: d.deviceClass,
    );
    return [
      singleFrame(pgn: 60928, source: d.src, data: le64(name)),
      ...fastPacketFrames(
        pgn: 126996,
        source: d.src,
        payload: _productInfoPayload(d),
      ),
      ...fastPacketFrames(
        pgn: 126998,
        source: d.src,
        payload: _configInfoPayload(d),
      ),
    ];
  }

  List<int> _productInfoPayload(_DemoDevice d) => [
        ...le16(2100), // N2K DB version
        ...le16(1000 + d.src), // product code
        ...asciiField(d.model, 32),
        ...asciiField(d.softwareVersion, 32),
        ...asciiField(d.modelVersion, 32),
        ...asciiField(d.serial, 32),
      ];

  List<int> _configInfoPayload(_DemoDevice d) => [
        ...varStringField(''), // installation description 1 (unused)
        ...varStringField(''), // installation description 2 (unused)
        ...varStringField(d.mfrText),
      ];

  // ── Live data ─────────────────────────────────────────────────────────

  List<N2kFrame> _liveFrames() => [
        _windFrame(),
        _temperatureFrame(_tempEngine, celsius: _engineRoomTempC(), sourceType: 3),
        _temperatureFrame(_tempFridge, celsius: _fridgeTempC(), sourceType: 7),
        _fluidFrame(_fuelTank, typeCode: 0, levelPct: _fuelLevelPct(), capacityL: 200),
        _fluidFrame(_waterTank, typeCode: 1, levelPct: _waterLevelPct(), capacityL: 300),
        _engineFrame(),
        _batteryFrame(),
        _positionFrame(),
        _cogSogFrame(),
        _headingFrame(),
        _gnssDopFrame(),
        ..._gnssPositionDataFrames(),
      ];

  double _jitter(double amplitude) => (_random.nextDouble() * 2 - 1) * amplitude;

  double _wrap360(double deg) {
    final w = deg % 360;
    return w < 0 ? w + 360 : w;
  }

  // Apparent wind: 9-16 kn oscillating close-hauled angle, as if tacking
  // upwind over a several-minute period.
  N2kFrame _windFrame() {
    final speedMs =
        (6.3 + 1.3 * math.sin(_t / 47) + 0.5 * math.sin(_t / 9) + _jitter(0.1))
            .clamp(0.5, 20.0);
    final angleDeg =
        _wrap360(180 + 150 * math.sin(_t / 150) + 3 * math.sin(_t * 0.7));
    final speedRaw = (speedMs * 100).round() & 0xffff;
    final angleRaw = ((angleDeg * math.pi / 180) * 10000).round() & 0xffff;
    return singleFrame(
      pgn: 130306,
      source: _wind.src,
      data: [
        0, // SID
        ...le16(speedRaw),
        ...le16(angleRaw),
        0x02, // reference: 2 = Apparent (boat-referenced)
        0xff,
        0xff,
      ],
    );
  }

  double _engineRoomTempC() =>
      (34 + 6 * math.sin(_t / 97) + 2 * math.sin(_t / 13) + _jitter(0.2))
          .clamp(18.0, 55.0);

  double _fridgeTempC() =>
      (4 + 2 * math.sin(_t / 131) + _jitter(0.15)).clamp(0.0, 8.0);

  N2kFrame _temperatureFrame(
    _DemoDevice d, {
    required double celsius,
    required int sourceType,
  }) {
    final raw = ((celsius + 273.15) * 100).round().clamp(0, 0xfffe);
    return singleFrame(
      pgn: 130312,
      source: d.src,
      data: [
        0, // SID
        0, // instance
        sourceType,
        ...le16(raw),
        0xff, 0xff, // set temperature: not available
        0xff, // reserved
      ],
    );
  }

  // Fuel drains over a ~20-minute cycle then "refuels"; water over ~40 min.
  double _fuelLevelPct() {
    final cycle = _t % 1200;
    return (82 - (cycle / 1200) * 67 + _jitter(0.3)).clamp(5.0, 90.0);
  }

  double _waterLevelPct() {
    final cycle = _t % 2400;
    return (90 - (cycle / 2400) * 70 + _jitter(0.3)).clamp(10.0, 95.0);
  }

  N2kFrame _fluidFrame(
    _DemoDevice d, {
    required int typeCode,
    required double levelPct,
    required double capacityL,
  }) {
    final levelRaw = (levelPct / 0.004).round().clamp(-32768, 32767);
    final capacityRaw = (capacityL * 10).round() & 0xffffffff;
    final typeInstanceByte = ((typeCode & 0x0f) << 4) | 0x00;
    return singleFrame(
      pgn: 127505,
      source: d.src,
      data: [
        typeInstanceByte,
        ...le16(levelRaw),
        ...le32(capacityRaw),
        0xff, // reserved
      ],
    );
  }

  double _engineRpm() =>
      (1200 + 900 * math.sin(_t / 55) + 150 * math.sin(_t / 6) + _jitter(15))
          .clamp(600.0, 3400.0);

  N2kFrame _engineFrame() {
    final rpmRaw = (_engineRpm() * 4).round().clamp(0, 0xfffe);
    return singleFrame(
      pgn: 127488,
      source: _engine.src,
      data: [
        0, // instance
        ...le16(rpmRaw),
        0xff, 0xff, // boost pressure: not available
        0x00, // trim
        0xff, 0xff, // reserved
      ],
    );
  }

  // Starter/house battery voltage, slowly drifting as if under a light load
  // with the odd small sag — reported by the engine data interface, which
  // is a common real-world pairing (SmartCraft-style gateways often surface
  // both engine parameters and battery voltage from the same source).
  double _batteryVoltage() =>
      (12.6 + 0.5 * math.sin(_t / 210) + _jitter(0.05)).clamp(11.8, 14.4);

  N2kFrame _batteryFrame() {
    final voltRaw = (_batteryVoltage() * 100).round() & 0xffff;
    return singleFrame(
      pgn: 127508,
      source: _engine.src,
      data: [
        0, // DC instance
        ...le16(voltRaw),
        0xff, 0xff, // current: not available
        0xff, 0xff, // temperature: not available
        0xff, // SID
      ],
    );
  }

  double get _headingDeg => _wrap360(40 * math.sin(_t / 150));
  double get _cogDeg => _wrap360(_headingDeg + 5 * math.sin(_t / 23));
  double get _sogMs => (3.0 + 1.0 * math.sin(_t / 37)).clamp(0.2, 8.0);

  (double, double) _position() {
    final lat = _lat0 + 0.00015 * math.sin(_t / 300) + _t * 0.0000002;
    final lon = _lon0 + 0.00020 * math.cos(_t / 300) + _t * 0.0000001;
    return (lat, lon);
  }

  N2kFrame _positionFrame() {
    final (lat, lon) = _position();
    final latRaw = (lat * 10000000).round() & 0xffffffff;
    final lonRaw = (lon * 10000000).round() & 0xffffffff;
    return singleFrame(
      pgn: 129025,
      source: _gps.src,
      data: [...le32(latRaw), ...le32(lonRaw)],
    );
  }

  N2kFrame _cogSogFrame() {
    final cogRaw = ((_cogDeg * math.pi / 180) * 10000).round() & 0xffff;
    final sogRaw = (_sogMs * 100).round() & 0xffff;
    return singleFrame(
      pgn: 129026,
      source: _gps.src,
      data: [
        0, // SID
        0x00, // reference: 0 = True
        ...le16(cogRaw),
        ...le16(sogRaw),
        0xff, 0xff,
      ],
    );
  }

  N2kFrame _headingFrame() {
    final headingRaw = ((_headingDeg * math.pi / 180) * 10000).round() & 0xffff;
    return singleFrame(
      pgn: 127250,
      source: _gps.src,
      data: [
        0, // SID
        ...le16(headingRaw),
        0xff, 0xff, // deviation: not available
        0xff, 0xff, // variation: not available
        0x00, // reference: 0 = True
      ],
    );
  }

  N2kFrame _gnssDopFrame() {
    final hdop = (0.8 + 0.1 * math.sin(_t / 13)).clamp(0.3, 3.0);
    final vdop = (1.1 + 0.1 * math.cos(_t / 17)).clamp(0.3, 4.0);
    final hdopRaw = (hdop * 100).round() & 0xffff;
    final vdopRaw = (vdop * 100).round() & 0xffff;
    return singleFrame(
      pgn: 129539,
      source: _gps.src,
      data: [
        0, // SID
        0, // mode bits
        ...le16(hdopRaw),
        ...le16(vdopRaw),
        0xff, 0xff, // TDOP: not used by the app
      ],
    );
  }

  List<N2kFrame> _gnssPositionDataFrames() {
    final (lat, lon) = _position();
    final altitudeM = 1.5 + 0.3 * math.sin(_t / 29);
    final satellites = 8 + (math.sin(_t / 19) > 0 ? 2 : 0);
    final hdopRaw = ((0.8 + 0.1 * math.sin(_t / 13)) * 100).round() & 0xffff;

    final latRaw = (lat * 1e16).round();
    final lonRaw = (lon * 1e16).round();
    final altRaw = (altitudeM * 1e6).round();
    final nowUtc = DateTime.now().toUtc();
    final dateDays = nowUtc.difference(DateTime.utc(1970, 1, 1)).inDays;
    final midnight = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    final timeRaw = (nowUtc.difference(midnight).inMilliseconds * 10) & 0xffffffff;

    final payload = <int>[
      0, // SID
      ...le16(dateDays),
      ...le32(timeRaw),
      ...le64(latRaw),
      ...le64(lonRaw),
      ...le64(altRaw),
      0x11, // type nibble=1, method nibble=1 (GNSS fix)
      0x00, // integrity/reserved
      satellites,
      ...le16(hdopRaw),
      0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, // reserved to pad to 43 bytes
    ];
    return fastPacketFrames(pgn: 129029, source: _gps.src, payload: payload);
  }
}
