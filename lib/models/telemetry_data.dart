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
      unknownPgns: unknownPgns ?? this.unknownPgns,
      model: model ?? this.model,
      deviceId: deviceId ?? this.deviceId,
      rawText: rawText ?? this.rawText,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
