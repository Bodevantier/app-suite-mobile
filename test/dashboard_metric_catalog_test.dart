import 'package:ble_application/dashboard/dashboard_metric_catalog.dart';
import 'package:ble_application/models/dashboard_layout.dart';
import 'package:ble_application/models/n2k_device_info.dart';
import 'package:ble_application/models/telemetry_data.dart';
import 'package:flutter_test/flutter_test.dart';

N2kDeviceInfo _device({
  int src = 1,
  bool liveEngine = false,
  bool liveTemperature = false,
  bool liveFluid = false,
  bool liveWind = false,
  String category = 'unknown',
}) {
  return N2kDeviceInfo(
    src: src,
    name: 'Test Device',
    model: 'Model X',
    manufacturer: 'Acme',
    category: category,
    online: true,
    hasLiveEngineData: liveEngine,
    hasLiveTemperatureData: liveTemperature,
    hasLiveFluidLevelData: liveFluid,
    hasLiveWindData: liveWind,
  );
}

void main() {
  group('metricsFor', () {
    test('an engine device offers engine RPM', () {
      final device = _device(liveEngine: true);
      expect(metricsFor(device), contains(DashboardMetricType.engineRpm));
      expect(metricsFor(device), isNot(contains(DashboardMetricType.temperatureC)));
    });

    test('a wind device offers all four wind metrics', () {
      final device = _device(liveWind: true);
      expect(
        metricsFor(device),
        containsAll(<DashboardMetricType>[
          DashboardMetricType.windApparentSpeed,
          DashboardMetricType.windApparentAngle,
          DashboardMetricType.windTrueSpeed,
          DashboardMetricType.windTrueAngle,
        ]),
      );
    });

    test('a navigation device offers heading, SOG, COG and position', () {
      final device = _device(category: 'navigation');
      expect(
        metricsFor(device),
        containsAll(<DashboardMetricType>[
          DashboardMetricType.heading,
          DashboardMetricType.speedOverGround,
          DashboardMetricType.courseOverGround,
          DashboardMetricType.position,
        ]),
      );
    });

    test('a device with no recognized category offers nothing', () {
      final device = _device();
      expect(metricsFor(device), isEmpty);
    });
  });

  group('valueText formatting', () {
    test('engine RPM is rounded with a unit suffix', () {
      const telemetry = TelemetryData(engineRpm: 1234.6);
      expect(
        dashboardMetricCatalog[DashboardMetricType.engineRpm]!.valueText(telemetry),
        '1235 RPM',
      );
    });

    test('temperature is shown to one decimal in Celsius', () {
      const telemetry = TelemetryData(temperatureC: 18.456);
      expect(
        dashboardMetricCatalog[DashboardMetricType.temperatureC]!.valueText(telemetry),
        '18.5°C',
      );
    });

    test('fluid level is a whole-number percentage', () {
      const telemetry = TelemetryData(fluidLevelPct: 72.3);
      expect(
        dashboardMetricCatalog[DashboardMetricType.fluidLevelPct]!.valueText(telemetry),
        '72%',
      );
    });

    test('wind speed converts m/s to knots', () {
      const telemetry = TelemetryData(apparentWindSpeedMs: 10.0);
      expect(
        dashboardMetricCatalog[DashboardMetricType.windApparentSpeed]!.valueText(telemetry),
        '19.4 kn',
      );
    });

    test('position formats latitude/longitude with hemispheres', () {
      const telemetry = TelemetryData(latitude: -33.865, longitude: 151.209);
      expect(
        dashboardMetricCatalog[DashboardMetricType.position]!.valueText(telemetry),
        '33.865°S 151.209°E',
      );
    });

    test('a metric with no data for this telemetry snapshot formats to null', () {
      const telemetry = TelemetryData();
      expect(
        dashboardMetricCatalog[DashboardMetricType.engineRpm]!.valueText(telemetry),
        isNull,
      );
    });
  });
}
