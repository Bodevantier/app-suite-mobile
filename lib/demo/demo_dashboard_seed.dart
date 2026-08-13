import '../models/dashboard_layout.dart';
import '../services/dashboard_layout_service.dart';
import 'demo_data_service.dart';

/// Populates Demo Mode's (separate — see DashboardLayoutService.setDemoMode)
/// dashboard set with four curated dashboards the first time Demo Mode is
/// turned on, so trying it immediately shows off the app rather than
/// landing on an empty "create your first dashboard" screen.
///
/// Tiles are bound to demo devices by their fixed [DemoDeviceSrc] source
/// address via the `src:<n>` fallback identity key — the same key a tile
/// would use for a real device before its NMEA 2000 NAME has resolved.
/// `resolveTileDevice` (lib/dashboard/dashboard_tile_resolver.dart) falls
/// back to matching on source address, so this works correctly without
/// needing to wait for/parse the demo devices' decoded identity first.
///
/// Only runs when the demo namespace has no dashboards yet — deleting or
/// rearranging them sticks; this isn't re-run on every toggle.
Future<void> seedDefaultDemoDashboards(DashboardLayoutService dashboards) async {
  if (dashboards.layouts.isNotEmpty) return;

  DashboardTile tile(
    int src,
    DashboardMetricType metric, {
    DashboardTileKind kind = DashboardTileKind.metric,
  }) {
    return DashboardTile(
      id: dashboards.generateId(),
      metric: metric,
      deviceKey: 'src:$src',
      deviceSrcHint: src,
      kind: kind,
    );
  }

  Future<void> build({
    required String name,
    required String iconKey,
    required DashboardModeTag tag,
    required List<DashboardTile> tiles,
  }) async {
    final layout = await dashboards.addLayout(name: name, iconKey: iconKey, modeTag: tag);
    await dashboards.updateLayout(layout.copyWith(tiles: tiles));
  }

  // Sailing — wind is the whole story: lead with the big compass (shows
  // apparent by default, tap to flip to true), then the usual sailing
  // instruments plus a couple of "still a boat" checks (battery, water).
  await build(
    name: 'Sailing',
    iconKey: 'sailing',
    tag: DashboardModeTag.sailing,
    tiles: [
      tile(
        DemoDeviceSrc.wind,
        DashboardMetricType.windApparentSpeed,
        kind: DashboardTileKind.windCompass,
      ),
      tile(DemoDeviceSrc.gps, DashboardMetricType.heading),
      tile(DemoDeviceSrc.gps, DashboardMetricType.speedOverGround),
      tile(DemoDeviceSrc.gps, DashboardMetricType.courseOverGround),
      tile(DemoDeviceSrc.wind, DashboardMetricType.windTrueSpeed),
      tile(DemoDeviceSrc.fridgeTemp, DashboardMetricType.temperatureC),
      tile(DemoDeviceSrc.waterTank, DashboardMetricType.fluidLevelPct),
      tile(DemoDeviceSrc.engine, DashboardMetricType.batteryVoltage),
    ],
  );

  // Motoring — engine health front and centre, plus fuel burn and the
  // usual position/speed instruments.
  await build(
    name: 'Motoring',
    iconKey: 'directions_boat',
    tag: DashboardModeTag.motoring,
    tiles: [
      tile(DemoDeviceSrc.engine, DashboardMetricType.engineRpm),
      tile(DemoDeviceSrc.engine, DashboardMetricType.batteryVoltage),
      tile(DemoDeviceSrc.engineTemp, DashboardMetricType.temperatureC),
      tile(DemoDeviceSrc.fuelTank, DashboardMetricType.fluidLevelPct),
      tile(DemoDeviceSrc.gps, DashboardMetricType.speedOverGround),
      tile(DemoDeviceSrc.gps, DashboardMetricType.heading),
      tile(DemoDeviceSrc.wind, DashboardMetricType.windApparentSpeed),
    ],
  );

  // Anchored — resource/anchor-watch concerns: where the boat is, which
  // way it's swinging, and the house essentials (power, water, food).
  await build(
    name: 'Anchored',
    iconKey: 'anchor',
    tag: DashboardModeTag.anchored,
    tiles: [
      tile(DemoDeviceSrc.gps, DashboardMetricType.position),
      tile(DemoDeviceSrc.gps, DashboardMetricType.heading),
      tile(DemoDeviceSrc.wind, DashboardMetricType.windApparentAngle),
      tile(DemoDeviceSrc.engine, DashboardMetricType.batteryVoltage),
      tile(DemoDeviceSrc.fridgeTemp, DashboardMetricType.temperatureC),
      tile(DemoDeviceSrc.waterTank, DashboardMetricType.fluidLevelPct),
      tile(DemoDeviceSrc.fuelTank, DashboardMetricType.fluidLevelPct),
    ],
  );

  // Docked — a lighter, housekeeping-only dashboard: what needs topping up
  // or has cooled down before heading out again.
  await build(
    name: 'Docked',
    iconKey: 'home',
    tag: DashboardModeTag.docked,
    tiles: [
      tile(DemoDeviceSrc.engine, DashboardMetricType.batteryVoltage),
      tile(DemoDeviceSrc.engineTemp, DashboardMetricType.temperatureC),
      tile(DemoDeviceSrc.fridgeTemp, DashboardMetricType.temperatureC),
      tile(DemoDeviceSrc.waterTank, DashboardMetricType.fluidLevelPct),
      tile(DemoDeviceSrc.fuelTank, DashboardMetricType.fluidLevelPct),
    ],
  );
}
