import 'dart:math' as math;

class TelemetryData {
  const TelemetryData({
    this.windSpeed,
    this.windAngleDeg,
    this.windQuality,
    this.headingDeg,
    this.gps,
    this.latitude,
    this.longitude,
    this.cogDeg,
    this.sogMs,
    this.batteryV,
    this.unknownPgns,
    this.model,
    this.deviceId,
    this.rawText,
    this.updatedAt,
  });

  final double? windSpeed;
  final double? windAngleDeg;
  final int? windQuality;
  final double? headingDeg;
  final String? gps;
  final double? latitude;
  final double? longitude;
  final double? cogDeg;
  final double? sogMs;
  final double? batteryV;
  final int? unknownPgns;
  final String? model;
  final int? deviceId;
  final String? rawText;
  final DateTime? updatedAt;

  factory TelemetryData.empty() {
    return const TelemetryData();
  }

  /// Apparent Wind Speed (m/s) computed from true wind + boat SOG.
  /// Returns null if any required value is missing.
  double? get apparentWindSpeedMs {
    if (windSpeed == null || windAngleDeg == null || sogMs == null) return null;
    final twa = windAngleDeg! * math.pi / 180;
    final awx = windSpeed! * math.sin(twa);
    final awy = windSpeed! * math.cos(twa) + sogMs!;
    return math.sqrt(awx * awx + awy * awy);
  }

  /// Apparent Wind Angle (degrees from bow, 0–360) computed from true wind + boat SOG.
  /// Returns null if any required value is missing.
  double? get apparentWindAngleDeg {
    if (windSpeed == null || windAngleDeg == null || sogMs == null) return null;
    final twa = windAngleDeg! * math.pi / 180;
    final awx = windSpeed! * math.sin(twa);
    final awy = windSpeed! * math.cos(twa) + sogMs!;
    var awa = math.atan2(awx, awy) * 180 / math.pi;
    if (awa < 0) awa += 360;
    return awa;
  }

  TelemetryData copyWith({
    double? windSpeed,
    double? windAngleDeg,
    int? windQuality,
    double? headingDeg,
    String? gps,
    double? latitude,
    double? longitude,
    double? cogDeg,
    double? sogMs,
    double? batteryV,
    int? unknownPgns,
    String? model,
    int? deviceId,
    String? rawText,
    DateTime? updatedAt,
  }) {
    return TelemetryData(
      windSpeed: windSpeed ?? this.windSpeed,
      windAngleDeg: windAngleDeg ?? this.windAngleDeg,
      windQuality: windQuality ?? this.windQuality,
      headingDeg: headingDeg ?? this.headingDeg,
      gps: gps ?? this.gps,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      cogDeg: cogDeg ?? this.cogDeg,
      sogMs: sogMs ?? this.sogMs,
      batteryV: batteryV ?? this.batteryV,
      unknownPgns: unknownPgns ?? this.unknownPgns,
      model: model ?? this.model,
      deviceId: deviceId ?? this.deviceId,
      rawText: rawText ?? this.rawText,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
