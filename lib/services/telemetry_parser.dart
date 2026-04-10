import '../models/telemetry_data.dart';
import 'package:flutter/foundation.dart';

class TelemetryParser {
  TelemetryData parse(String input, {TelemetryData? previous}) {
    final prior = previous ?? TelemetryData.empty();
    final normalized = input.trim();
    final windMatch = _windPayloadPattern.firstMatch(normalized);
    final windSpeed = _parseWindSpeed(normalized, fallback: prior.windSpeed);
    final windAngleDeg = _parseWindAngle(normalized, fallback: prior.windAngleDeg);
    final windQuality = _parseWindQuality(normalized, fallback: prior.windQuality);

    debugPrint('[TelemetryParser] input string="$normalized"');
    debugPrint('[TelemetryParser] wind regex matched=${windMatch != null}');
    debugPrint('[TelemetryParser] parsed wind speed=$windSpeed');
    debugPrint('[TelemetryParser] parsed wind angle=$windAngleDeg');

    return TelemetryData(
      windSpeed: windSpeed,
      windAngleDeg: windAngleDeg,
      windQuality: windQuality,
      headingDeg: _parseDoubleMatch(
        normalized,
        RegExp(r'hdg:([-+]?\d+(?:[.,]\d+)?)deg'),
        fallback: prior.headingDeg,
      ),
      gps: _parseStringField(
        normalized,
        RegExp(r'gps:(.*?)(?=\s+(?:bat:|unknown:|model:|dev:)|$)'),
        fallback: prior.gps,
      ),
      batteryV: _parseDoubleMatch(
        normalized,
        RegExp(r'bat:([-+]?\d+(?:[.,]\d+)?)V\b'),
        fallback: prior.batteryV,
      ),
      unknownPgns: _parseIntMatch(
        normalized,
        RegExp(r'unknown:(\d+)'),
        fallback: prior.unknownPgns,
      ),
      model: _parseStringField(
        normalized,
        RegExp(r'model:(.*?)(?=\s+dev:|dev:|$)'),
        fallback: prior.model,
      ),
      deviceId: _parseIntMatch(
        normalized,
        RegExp(r'dev:(\d+)'),
        fallback: prior.deviceId,
      ),
      rawText: normalized.isEmpty ? prior.rawText : normalized,
      updatedAt: normalized.isEmpty ? prior.updatedAt : DateTime.now(),
    );
  }

  static final RegExp _windPayloadPattern = RegExp(
    r'wind:(?:spd=)?([-+]?\d+(?:[.,]\d+)?)(?:m/s)?(?:,|\s*@\s*|@)(?:ang=)?([-+]?\d+(?:[.,]\d+)?)(?:deg)?(?:,ref=(\d+)|\s*r(\d+))?',
  );

  double? _parseWindSpeed(String input, {double? fallback}) {
    return _parseDoubleFromGroups(input, _windPayloadPattern, const [1], fallback: fallback);
  }

  double? _parseWindAngle(String input, {double? fallback}) {
    return _parseDoubleFromGroups(input, _windPayloadPattern, const [2], fallback: fallback);
  }

  int? _parseWindQuality(String input, {int? fallback}) {
    return _parseIntFromGroups(input, _windPayloadPattern, const [3, 4], fallback: fallback);
  }

  double? _parseDoubleMatch(String input, RegExp pattern, {double? fallback}) {
    final value = _firstMatch(input, pattern);
    if (value == null || value == '-') {
      return fallback;
    }

    return double.tryParse(value.replaceAll(',', '.')) ?? fallback;
  }

  int? _parseIntMatch(String input, RegExp pattern, {int? fallback}) {
    final value = _firstMatch(input, pattern);
    if (value == null || value == '-') {
      return fallback;
    }

    return int.tryParse(value) ?? fallback;
  }

  double? _parseDoubleFromGroups(
    String input,
    RegExp pattern,
    List<int> groups, {
    double? fallback,
  }) {
    final value = _firstNonEmptyGroup(input, pattern, groups);
    if (value == null || value == '-') {
      return fallback;
    }

    return double.tryParse(value.replaceAll(',', '.')) ?? fallback;
  }

  int? _parseIntFromGroups(
    String input,
    RegExp pattern,
    List<int> groups, {
    int? fallback,
  }) {
    final value = _firstNonEmptyGroup(input, pattern, groups);
    if (value == null || value == '-') {
      return fallback;
    }

    return int.tryParse(value) ?? fallback;
  }

  String? _parseStringField(String input, RegExp pattern, {String? fallback}) {
    final value = _lastMatch(input, pattern);
    if (value == null) {
      return fallback;
    }

    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '-') {
      return fallback;
    }

    return trimmed;
  }

  String? _firstMatch(String input, RegExp pattern) {
    return _lastMatch(input, pattern);
  }

  String? _lastMatch(String input, RegExp pattern) {
    String? value;
    for (final match in pattern.allMatches(input)) {
      value = match.group(1);
    }
    return value;
  }

  String? _firstNonEmptyGroup(String input, RegExp pattern, List<int> groups) {
    for (final match in pattern.allMatches(input)) {
      for (final group in groups) {
        final value = match.group(group);
        if (value != null && value.isNotEmpty) {
          return value;
        }
      }
    }
    return null;
  }
}
