import 'dart:math' as math;

class TelemetryData {
  const TelemetryData({
    this.trueWindSpeedMs,
    this.trueWindAngleDeg,
    this.apparentWindSpeedMs,
    this.apparentWindAngleDeg,
    this.windQuality,
    this.headingDeg,
    this.gps,
    this.latitude,
    this.longitude,
    this.cogDeg,
    this.sogMs,
    this.batteryV,
    this.temperatureC,
    this.engineRpm,
    this.engineInstance,
    this.fluidLevelPct,
    this.fluidType,
    this.fluidInstance,
    this.fluidCapacityL,
    this.magneticVariationDeg,
    this.hdop,
    this.vdop,
    this.gnssAltitudeM,
    this.gnssSatellites,
    this.gnssFixType,
    this.unknownPgns,
    this.model,
    this.deviceId,
    this.rawText,
    this.updatedAt,
  });

  /// True wind speed/angle — from PGN 130306 with ref ≠ 2.
  /// Typically computed and sent by a chartplotter.
  final double? trueWindSpeedMs;
  final double? trueWindAngleDeg;

  /// Apparent wind speed/angle — directly from the masthead sensor (ref = 2).
  final double? apparentWindSpeedMs;
  final double? apparentWindAngleDeg;

  final int? windQuality;
  final double? headingDeg;
  final String? gps;
  final double? latitude;
  final double? longitude;
  final double? cogDeg;
  final double? sogMs;
  final double? batteryV;
  final double? temperatureC;

  /// Engine speed in RPM as broadcast on PGN 127488 (Engine Parameters,
  /// Rapid Update). This is the value reported by the sensor before any
  /// app-side pulses-per-revolution calibration is applied.
  final double? engineRpm;

  /// Engine instance from PGN 127488 (0–14, 255 = N/A).
  final int? engineInstance;

  /// Fluid (tank) level percentage 0–100 from PGN 127505.
  final double? fluidLevelPct;

  /// Fluid type label decoded from PGN 127505 (e.g. "Fuel", "Water",
  /// "Gray water", "Live well", "Oil", "Black water"). Null when unknown.
  final String? fluidType;

  /// Tank instance from PGN 127505 (0–14, 15 = N/A).
  final int? fluidInstance;

  /// Tank capacity in litres from PGN 127505. Null when not provided.
  final double? fluidCapacityL;

  /// Magnetic variation in degrees (+ = East) from PGN 127258.
  final double? magneticVariationDeg;

  /// Horizontal / vertical dilution of precision from PGN 129539.
  final double? hdop;
  final double? vdop;

  /// Altitude in metres from PGN 129029 (fast-packet, reassembled).
  final double? gnssAltitudeM;

  /// Number of tracked satellites from PGN 129029.
  final int? gnssSatellites;

  /// Fix method string from PGN 129029 (e.g. "GNSS", "DGNSS", "RTK Fixed").
  final String? gnssFixType;

  final int? unknownPgns;
  final String? model;
  final int? deviceId;
  final String? rawText;
  final DateTime? updatedAt;

  factory TelemetryData.empty() {
    return const TelemetryData();
  }

  /// True wind speed (m/s). See [_computedTrueWind] for the derivation;
  /// falls back to stored [trueWindSpeedMs] when AWS/AWA/SOG aren't all known.
  double? get effectiveTrueWindSpeedMs => _computedTrueWind()?.$1 ?? trueWindSpeedMs;

  /// True wind angle (degrees from bow, 0–360). Paired with
  /// [effectiveTrueWindSpeedMs] — both come from the same computation so the
  /// (TWS, TWA) pair is always consistent within a frame.
  double? get effectiveTrueWindAngleDeg => _computedTrueWind()?.$2 ?? trueWindAngleDeg;

  /// Computes (TWS m/s, TWA deg 0–360) from apparent wind + SOG.
  ///
  /// Returns `null` when any required input is missing.
  ///
  /// Stationary-boat handling: when SOG is below typical GPS noise floor the
  /// boat isn't really moving, so by definition true wind ≡ apparent wind. We
  /// blend smoothly between "use apparent" and "subtract SOG vector" across a
  /// narrow hysteresis band [_sogIdleMs, _sogMovingMs] so the displayed angle
  /// doesn't snap when SOG flickers across the threshold (which used to make
  /// TWA jump up to 180° when AWA ≈ 0° and AWS was small — the noise in SOG
  /// would dominate `aws·cos(awa) − sog` and flip its sign).
  (double, double)? _computedTrueWind() {
    final aws = apparentWindSpeedMs;
    final awaDeg = apparentWindAngleDeg;
    final sog = sogMs;
    if (aws == null || awaDeg == null || sog == null) return null;

    // Smooth gating factor: 0 → use apparent, 1 → fully subtract SOG.
    const sogIdleMs = 0.25;    // ≈ 0.5 kn — typical static GPS drift
    const sogMovingMs = 0.75;  // ≈ 1.5 kn — boat clearly underway
    double k;
    if (sog <= sogIdleMs) {
      k = 0;
    } else if (sog >= sogMovingMs) {
      k = 1;
    } else {
      k = (sog - sogIdleMs) / (sogMovingMs - sogIdleMs);
    }

    final awa = awaDeg * math.pi / 180;
    final twx = aws * math.sin(awa);
    final twy = aws * math.cos(awa) - k * sog;
    final tws = math.sqrt(twx * twx + twy * twy);

    // Degenerate vectors (essentially zero apparent wind and zero SOG): fall
    // back to apparent so we don't return atan2(0, 0) noise.
    if (tws < 1e-3) return (aws, awaDeg);

    var twa = math.atan2(twx, twy) * 180 / math.pi;
    if (twa < 0) twa += 360;
    return (tws, twa);
  }

  TelemetryData copyWith({
    double? trueWindSpeedMs,
    double? trueWindAngleDeg,
    double? apparentWindSpeedMs,
    double? apparentWindAngleDeg,
    int? windQuality,
    double? headingDeg,
    String? gps,
    double? latitude,
    double? longitude,
    double? cogDeg,
    double? sogMs,
    double? batteryV,
    double? temperatureC,
    double? engineRpm,
    int? engineInstance,
    double? fluidLevelPct,
    String? fluidType,
    int? fluidInstance,
    double? fluidCapacityL,
    double? magneticVariationDeg,
    double? hdop,
    double? vdop,
    double? gnssAltitudeM,
    int? gnssSatellites,
    String? gnssFixType,
    int? unknownPgns,
    String? model,
    int? deviceId,
    String? rawText,
    DateTime? updatedAt,
  }) {
    return TelemetryData(
      trueWindSpeedMs: trueWindSpeedMs ?? this.trueWindSpeedMs,
      trueWindAngleDeg: trueWindAngleDeg ?? this.trueWindAngleDeg,
      apparentWindSpeedMs: apparentWindSpeedMs ?? this.apparentWindSpeedMs,
      apparentWindAngleDeg: apparentWindAngleDeg ?? this.apparentWindAngleDeg,
      windQuality: windQuality ?? this.windQuality,
      headingDeg: headingDeg ?? this.headingDeg,
      gps: gps ?? this.gps,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      cogDeg: cogDeg ?? this.cogDeg,
      sogMs: sogMs ?? this.sogMs,
      batteryV: batteryV ?? this.batteryV,
      temperatureC: temperatureC ?? this.temperatureC,
      engineRpm: engineRpm ?? this.engineRpm,
      engineInstance: engineInstance ?? this.engineInstance,
      fluidLevelPct: fluidLevelPct ?? this.fluidLevelPct,
      fluidType: fluidType ?? this.fluidType,
      fluidInstance: fluidInstance ?? this.fluidInstance,
      fluidCapacityL: fluidCapacityL ?? this.fluidCapacityL,
      magneticVariationDeg: magneticVariationDeg ?? this.magneticVariationDeg,
      hdop: hdop ?? this.hdop,
      vdop: vdop ?? this.vdop,
      gnssAltitudeM: gnssAltitudeM ?? this.gnssAltitudeM,
      gnssSatellites: gnssSatellites ?? this.gnssSatellites,
      gnssFixType: gnssFixType ?? this.gnssFixType,
      unknownPgns: unknownPgns ?? this.unknownPgns,
      model: model ?? this.model,
      deviceId: deviceId ?? this.deviceId,
      rawText: rawText ?? this.rawText,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
