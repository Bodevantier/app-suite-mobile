import 'package:flutter/material.dart';

import '../models/dashboard_layout.dart';
import '../models/n2k_device_info.dart';
import '../models/telemetry_data.dart';

/// One selectable display unit for a [DashboardMetricSpec] — e.g. knots vs
/// m/s for a speed. [fromBase] converts the metric's underlying SI-ish value
/// (as stored in [TelemetryData]) into the number to display.
///
/// A unit that needs more than just the metric's own base value — tank
/// litres need both the level percentage *and* the tank capacity — provides
/// [customFormat] instead, which reads straight from [TelemetryData] and
/// takes over formatting entirely for that unit choice.
class DashboardUnitOption {
  const DashboardUnitOption({
    required this.suffix,
    this.decimals = 1,
    this.fromBase,
    this.customFormat,
  }) : assert(
          fromBase != null || customFormat != null,
          'a unit needs fromBase or customFormat',
        );

  final String suffix;
  final int decimals;
  final double Function(double base)? fromBase;
  final String? Function(TelemetryData telemetry)? customFormat;

  String? format(TelemetryData telemetry, double? base) {
    final custom = customFormat;
    if (custom != null) return custom(telemetry);
    if (base == null) return null;
    return '${fromBase!(base).toStringAsFixed(decimals)}$suffix';
  }
}

/// Describes one pickable dashboard metric: how to read/format it and which
/// discovered N2K devices can supply it.
class DashboardMetricSpec {
  const DashboardMetricSpec({
    required this.type,
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.availableOn,
    this.units = const <DashboardUnitOption>[],
    this.baseValue,
    this.customValueText,
    this.useBoatWideTelemetry = false,
  });

  final DashboardMetricType type;
  final String label;

  /// Marine-instrument abbreviation (AWA, SOG, HDG, …) used as the tile
  /// caption — short enough to always fit without truncating, unlike
  /// [label] which is better suited to the (roomier) tile picker list.
  final String shortLabel;
  final IconData icon;

  /// Whether [device] currently exposes this metric, based on the same
  /// category flags the rest of the app already uses to route devices to
  /// their detail pages (isEngineDevice, isWindDevice, etc).
  final bool Function(N2kDeviceInfo device) availableOn;

  /// True wind is a *computed* quantity (apparent wind + SOG — see
  /// TelemetryData.effectiveTrueWindSpeedMs), and those two inputs almost
  /// never come from the same physical device (a masthead wind sensor
  /// doesn't know the boat's speed). Reading a single device's own
  /// telemetryFor(src) would leave SOG permanently missing and the tile
  /// stuck blank. Metrics with this set read the boat-wide fused telemetry
  /// getter instead — matches how the full Wind page already does it.
  final bool useBoatWideTelemetry;

  /// Display unit choices, in order. A single entry means the metric isn't
  /// unit-cyclable (tapping its tile's icon is a no-op).
  final List<DashboardUnitOption> units;

  /// Extracts the metric's underlying value from [telemetry], in whatever
  /// base unit [units] converts from (m/s, °C, etc). Null when this metric
  /// doesn't fit the single-scalar-with-units shape (see [customValueText]).
  final double? Function(TelemetryData telemetry)? baseValue;

  /// For metrics that don't reduce to one scalar with unit choices (e.g.
  /// position, which needs both latitude and longitude) — formats the value
  /// directly and ignores [unitIndex].
  final String? Function(TelemetryData telemetry)? customValueText;

  bool get supportsUnitCycling => units.length > 1;

  /// Formatted display value (including unit), or null when [telemetry]
  /// doesn't currently carry this field. [unitIndex] selects which of
  /// [units] to render in, clamped to a valid range.
  String? valueText(TelemetryData telemetry, {int unitIndex = 0}) {
    final custom = customValueText;
    if (custom != null) return custom(telemetry);
    if (units.isEmpty) return null;
    final index = unitIndex.clamp(0, units.length - 1);
    final base = baseValue?.call(telemetry);
    return units[index].format(telemetry, base);
  }
}

double _identity(double v) => v;
double _msToKn(double ms) => ms * 1.94384;
double _msToKmh(double ms) => ms * 3.6;
double _cToF(double c) => c * 9 / 5 + 32;

/// Tank volume in litres — needs both the level percentage *and* the tank's
/// reported capacity, so this is a [DashboardUnitOption.customFormat] rather
/// than a plain [DashboardUnitOption.fromBase] conversion. Null (shown as
/// "—") when the sensor hasn't reported a capacity.
String? _fluidLiters(TelemetryData telemetry) {
  final pct = telemetry.fluidLevelPct;
  final capacityL = telemetry.fluidCapacityL;
  if (pct == null || capacityL == null) return null;
  return '${(pct / 100 * capacityL).toStringAsFixed(0)} L';
}

const _speedUnits = <DashboardUnitOption>[
  DashboardUnitOption(suffix: ' kn', decimals: 1, fromBase: _msToKn),
  DashboardUnitOption(suffix: ' m/s', decimals: 1, fromBase: _identity),
  DashboardUnitOption(suffix: ' km/h', decimals: 1, fromBase: _msToKmh),
];

const _degreeUnits = <DashboardUnitOption>[
  DashboardUnitOption(suffix: '°', decimals: 0, fromBase: _identity),
];

String _fmtLatLng(double lat, double lng) {
  String part(double value, String pos, String neg) {
    final hemi = value >= 0 ? pos : neg;
    return '${value.abs().toStringAsFixed(3)}°$hemi';
  }

  return '${part(lat, 'N', 'S')} ${part(lng, 'E', 'W')}';
}

/// One spec per [DashboardMetricType]. Keep in sync with that enum.
final Map<DashboardMetricType, DashboardMetricSpec> dashboardMetricCatalog =
    <DashboardMetricType, DashboardMetricSpec>{
  DashboardMetricType.engineRpm: DashboardMetricSpec(
    type: DashboardMetricType.engineRpm,
    label: 'Engine RPM',
    shortLabel: 'RPM',
    icon: Icons.speed,
    availableOn: (d) => d.isEngineDevice,
    units: const [DashboardUnitOption(suffix: ' RPM', decimals: 0, fromBase: _identity)],
    baseValue: (t) => t.engineRpm,
  ),
  DashboardMetricType.temperatureC: DashboardMetricSpec(
    type: DashboardMetricType.temperatureC,
    label: 'Temperature',
    shortLabel: 'Temp',
    icon: Icons.thermostat,
    availableOn: (d) => d.isTemperatureDevice,
    units: const [
      DashboardUnitOption(suffix: '°C', decimals: 1, fromBase: _identity),
      DashboardUnitOption(suffix: '°F', decimals: 1, fromBase: _cToF),
    ],
    baseValue: (t) => t.temperatureC,
  ),
  DashboardMetricType.fluidLevelPct: DashboardMetricSpec(
    type: DashboardMetricType.fluidLevelPct,
    label: 'Tank Level',
    shortLabel: 'Tank',
    icon: Icons.water_drop,
    availableOn: (d) => d.isFluidLevelDevice,
    units: const [
      DashboardUnitOption(suffix: '%', decimals: 0, fromBase: _identity),
      DashboardUnitOption(suffix: ' L', customFormat: _fluidLiters),
    ],
    baseValue: (t) => t.fluidLevelPct,
  ),
  DashboardMetricType.batteryVoltage: DashboardMetricSpec(
    type: DashboardMetricType.batteryVoltage,
    label: 'Battery',
    shortLabel: 'Batt',
    icon: Icons.battery_full,
    // There's no dedicated battery-monitor device category yet — voltage
    // rides on whatever device last reported PGN 127508, commonly an engine
    // or navigation node. Offer it wherever those are available; the tile
    // itself just goes blank if this particular device never reports it.
    availableOn: (d) => d.isEngineDevice || d.isNavigationDevice,
    units: const [DashboardUnitOption(suffix: ' V', decimals: 1, fromBase: _identity)],
    baseValue: (t) => t.batteryV,
  ),
  DashboardMetricType.windApparentSpeed: DashboardMetricSpec(
    type: DashboardMetricType.windApparentSpeed,
    label: 'Apparent Wind Speed',
    shortLabel: 'AWS',
    icon: Icons.air,
    availableOn: (d) => d.isWindDevice,
    units: _speedUnits,
    baseValue: (t) => t.apparentWindSpeedMs,
  ),
  DashboardMetricType.windApparentAngle: DashboardMetricSpec(
    type: DashboardMetricType.windApparentAngle,
    label: 'Apparent Wind Angle',
    shortLabel: 'AWA',
    icon: Icons.explore,
    availableOn: (d) => d.isWindDevice,
    units: _degreeUnits,
    baseValue: (t) => t.apparentWindAngleDeg,
  ),
  DashboardMetricType.windTrueSpeed: DashboardMetricSpec(
    type: DashboardMetricType.windTrueSpeed,
    label: 'True Wind Speed',
    shortLabel: 'TWS',
    icon: Icons.air,
    availableOn: (d) => d.isWindDevice,
    units: _speedUnits,
    baseValue: (t) => t.effectiveTrueWindSpeedMs,
    useBoatWideTelemetry: true,
  ),
  DashboardMetricType.windTrueAngle: DashboardMetricSpec(
    type: DashboardMetricType.windTrueAngle,
    label: 'True Wind Angle',
    shortLabel: 'TWA',
    icon: Icons.explore,
    availableOn: (d) => d.isWindDevice,
    units: _degreeUnits,
    baseValue: (t) => t.effectiveTrueWindAngleDeg,
    useBoatWideTelemetry: true,
  ),
  DashboardMetricType.heading: DashboardMetricSpec(
    type: DashboardMetricType.heading,
    label: 'Heading',
    shortLabel: 'HDG',
    icon: Icons.navigation,
    availableOn: (d) => d.isNavigationDevice,
    units: _degreeUnits,
    baseValue: (t) => t.headingDeg,
  ),
  DashboardMetricType.speedOverGround: DashboardMetricSpec(
    type: DashboardMetricType.speedOverGround,
    label: 'Speed Over Ground',
    shortLabel: 'SOG',
    icon: Icons.speed,
    availableOn: (d) => d.isNavigationDevice,
    units: _speedUnits,
    baseValue: (t) => t.sogMs,
  ),
  DashboardMetricType.courseOverGround: DashboardMetricSpec(
    type: DashboardMetricType.courseOverGround,
    label: 'Course Over Ground',
    shortLabel: 'COG',
    icon: Icons.explore,
    availableOn: (d) => d.isNavigationDevice,
    units: _degreeUnits,
    baseValue: (t) => t.cogDeg,
  ),
  DashboardMetricType.position: DashboardMetricSpec(
    type: DashboardMetricType.position,
    label: 'Position',
    shortLabel: 'Pos',
    icon: Icons.my_location,
    availableOn: (d) => d.isNavigationDevice,
    customValueText: (t) => (t.latitude == null || t.longitude == null)
        ? null
        : _fmtLatLng(t.latitude!, t.longitude!),
  ),
};

/// Metrics [device] can currently supply, in catalog order.
List<DashboardMetricType> metricsFor(N2kDeviceInfo device) {
  return dashboardMetricCatalog.values
      .where((spec) => spec.availableOn(device))
      .map((spec) => spec.type)
      .toList(growable: false);
}

/// Accent color per metric family — mirrors the category colors already
/// used for device icons elsewhere in the app (temperature orange, fluid
/// blue, engine red, navigation green), with wind given its own teal so it
/// doesn't read as "just another blue tile" next to fluid levels.
Color colorForMetric(DashboardMetricType type) {
  switch (type) {
    case DashboardMetricType.engineRpm:
      return const Color(0xffdc2626); // red-600
    case DashboardMetricType.temperatureC:
      return const Color(0xffea580c); // orange-600
    case DashboardMetricType.fluidLevelPct:
      return const Color(0xff2563eb); // blue-600
    case DashboardMetricType.batteryVoltage:
      return const Color(0xffb45309); // amber-700
    case DashboardMetricType.windApparentSpeed:
    case DashboardMetricType.windApparentAngle:
    case DashboardMetricType.windTrueSpeed:
    case DashboardMetricType.windTrueAngle:
      return const Color(0xff0d9488); // teal-600
    case DashboardMetricType.heading:
    case DashboardMetricType.speedOverGround:
    case DashboardMetricType.courseOverGround:
    case DashboardMetricType.position:
      return const Color(0xff16a34a); // green-600
  }
}
