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

  /// True wind speed (m/s). Prefers direct physics computation from apparent
  /// wind + SOG when available — this avoids relying on chartplotter-broadcast
  /// true wind which may carry reference-convention mismatches.
  /// Falls back to stored [trueWindSpeedMs] (e.g. chartplotter with no sensor).
  double? get effectiveTrueWindSpeedMs {
    if (apparentWindSpeedMs != null && apparentWindAngleDeg != null && sogMs != null) {
      final awa = apparentWindAngleDeg! * math.pi / 180;
      final twx = apparentWindSpeedMs! * math.sin(awa);
      final twy = apparentWindSpeedMs! * math.cos(awa) - sogMs!;
      final tws = math.sqrt(twx * twx + twy * twy);
      // Below 0.5 m/s the vectors nearly cancel and the result is dominated by
      // GPS noise — return apparent wind speed directly.
      if (tws < 0.5) return apparentWindSpeedMs;
      return tws;
    }
    return trueWindSpeedMs;
  }

  /// True wind angle (degrees from bow, 0–360). Prefers direct computation
  /// from apparent wind + SOG; falls back to stored [trueWindAngleDeg].
  double? get effectiveTrueWindAngleDeg {
    if (apparentWindSpeedMs != null && apparentWindAngleDeg != null && sogMs != null) {
      final awa = apparentWindAngleDeg! * math.pi / 180;
      final twx = apparentWindSpeedMs! * math.sin(awa);
      final twy = apparentWindSpeedMs! * math.cos(awa) - sogMs!;
      final tws = math.sqrt(twx * twx + twy * twy);
      // When TWS is near zero the vectors nearly cancel and atan2(~0, ~0) is
      // undefined — GPS noise in SOG alone produces atan2(0, -SOG) = 180° which
      // jiggle between 0° and 180° as the boat sits stationary. 0.5 m/s gives
      // enough headroom above typical GPS drift (~0.3–0.4 m/s on a fixed vessel).
      if (tws < 0.5) return apparentWindAngleDeg;
      var twa = math.atan2(twx, twy) * 180 / math.pi;
      if (twa < 0) twa += 360;
      return twa;
    }
    return trueWindAngleDeg;
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
