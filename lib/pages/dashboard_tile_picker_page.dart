import 'package:flutter/material.dart';

import '../ble/controllers/ble_gateway_controller.dart';
import '../dashboard/dashboard_metric_catalog.dart';
import '../models/dashboard_layout.dart';
import '../models/n2k_device_info.dart';
import '../models/node_settings.dart';
import '../services/dashboard_layout_service.dart';
import '../services/node_settings_service.dart';

/// Lets the user add a tile to a dashboard. Lists only metrics actually
/// available from devices currently visible on the N2K bus, grouped by
/// device, excluding any (device, metric) pair already on this dashboard.
///
/// Pops with the new [DashboardTile], or null if the user backs out.
class DashboardTilePickerPage extends StatelessWidget {
  const DashboardTilePickerPage({
    super.key,
    required this.bleGatewayController,
    required this.nodeSettings,
    required this.dashboards,
    required this.existingTiles,
  });

  final BleGatewayController bleGatewayController;
  final NodeSettingsService nodeSettings;
  final DashboardLayoutService dashboards;
  final List<DashboardTile> existingTiles;

  @override
  Widget build(BuildContext context) {
    final devices = filterSetupVisibleDevices(bleGatewayController.devices);

    final sections = <Widget>[];
    for (final device in devices) {
      final deviceKey = nodeSettingsKey(device);
      final available = metricsFor(device).where((metric) {
        return !existingTiles
            .any((t) => t.deviceKey == deviceKey && t.metric == metric);
      }).toList(growable: false);
      final compassAvailable = device.isWindDevice &&
          !existingTiles.any(
            (t) => t.deviceKey == deviceKey && t.kind == DashboardTileKind.windCompass,
          );
      if (available.isEmpty && !compassAvailable) continue;

      final custom = nodeSettings.forDevice(device).customName;
      final title = (custom != null && custom.trim().isNotEmpty)
          ? custom.trim()
          : device.displayName;

      sections.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
      );
      if (compassAvailable) {
        sections.add(
          ListTile(
            leading: const Icon(Icons.explore_outlined),
            title: const Text('Wind compass'),
            subtitle: const Text('Bigger tile — wind angle relative to the boat, plus speed'),
            onTap: () => Navigator.of(context).pop(
              DashboardTile(
                id: dashboards.generateId(),
                metric: DashboardMetricType.windApparentSpeed,
                deviceKey: deviceKey,
                deviceSrcHint: device.src,
                kind: DashboardTileKind.windCompass,
              ),
            ),
          ),
        );
      }
      for (final metric in available) {
        final spec = dashboardMetricCatalog[metric]!;
        sections.add(
          ListTile(
            leading: Icon(spec.icon),
            title: Text(spec.label),
            onTap: () => Navigator.of(context).pop(
              DashboardTile(
                id: dashboards.generateId(),
                metric: metric,
                deviceKey: deviceKey,
                deviceSrcHint: device.src,
              ),
            ),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Add tile')),
      body: sections.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  devices.isEmpty
                      ? 'No N2K devices detected on the bus yet.'
                      : 'Everything visible on the network is already on this dashboard.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(children: sections),
    );
  }
}
