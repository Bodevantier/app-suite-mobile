import 'dart:async';

import 'package:flutter/material.dart';

import '../ble/controllers/ble_gateway_controller.dart';
import '../controllers/ble_controller.dart';
import '../dashboard/dashboard_metric_catalog.dart';
import '../dashboard/dashboard_tile_resolver.dart';
import '../models/dashboard_layout.dart';
import '../models/n2k_device_info.dart';
import '../n2k/fluid_icons.dart';
import '../n2k/n2k_liveness.dart';
import '../services/alarm_monitor_service.dart';
import '../services/node_settings_service.dart';
import 'live_activity_indicator.dart';

/// Whether [device]'s current reading for [metric] is under an active alarm
/// — used to redden the tile. Only fluid level and temperature tiles have
/// alarms modeled today; every other metric is never alarming.
bool _isTileAlarming(
  AlarmMonitorService? monitor,
  N2kDeviceInfo device,
  DashboardMetricType metric,
) {
  if (monitor == null) return false;
  switch (metric) {
    case DashboardMetricType.fluidLevelPct:
      return monitor.isActive(device, AlarmKind.tankLow) ||
          monitor.isActive(device, AlarmKind.tankHigh);
    case DashboardMetricType.temperatureC:
      return monitor.isActive(device, AlarmKind.tempHigh) ||
          monitor.isActive(device, AlarmKind.tempLow);
    default:
      return false;
  }
}

/// One square on a dashboard grid: the live value for [tile], resolved
/// fresh from whichever device currently matches its stored identity.
///
/// Self-contained on purpose — it listens to [bleGatewayController] and
/// [telemetryController] directly rather than relying on a parent rebuild,
/// so a dashboard's tile *count* only changes when the layout itself is
/// edited, while each tile's *value* still updates live at full telemetry
/// rate. A small periodic timer additionally re-checks staleness, since no
/// listener fires when a device simply stops transmitting.
class MetricTile extends StatefulWidget {
  const MetricTile({
    super.key,
    required this.tile,
    required this.bleGatewayController,
    required this.telemetryController,
    required this.nodeSettingsService,
    this.alarmMonitor,
    this.onRemove,
    this.onCycleUnit,
  });

  final DashboardTile tile;
  final BleGatewayController bleGatewayController;
  final BleController telemetryController;
  final NodeSettingsService nodeSettingsService;
  final AlarmMonitorService? alarmMonitor;

  /// Non-null only while the dashboard is in edit mode — shows a remove
  /// affordance instead of the live indicator.
  final VoidCallback? onRemove;

  /// Tapping anywhere on the tile cycles its display unit (e.g.
  /// kn → m/s → km/h). A no-op when the metric only has one unit.
  final VoidCallback? onCycleUnit;

  @override
  State<MetricTile> createState() => _MetricTileState();
}

class _MetricTileState extends State<MetricTile> {
  Timer? _stalenessTicker;

  @override
  void initState() {
    super.initState();
    _stalenessTicker = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _stalenessTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.bleGatewayController,
        widget.telemetryController,
        widget.nodeSettingsService,
        ?widget.alarmMonitor,
      ]),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spec = dashboardMetricCatalog[widget.tile.metric]!;
    var metricColor = colorForMetric(widget.tile.metric);
    final device = resolveTileDevice(
      widget.tile,
      filterSetupVisibleDevices(widget.bleGatewayController.devices),
    );

    final live = device != null && isDeviceLive(device);
    final alarming = live &&
        _isTileAlarming(widget.alarmMonitor, device, widget.tile.metric);
    String? valueText;
    var icon = spec.icon;
    if (live) {
      final telemetry = widget.telemetryController.telemetryFor(device.src);
      // True wind is computed from apparent wind + SOG, which almost never
      // come from the same physical device — read the boat-wide fused
      // telemetry for those so the tile isn't permanently stuck blank.
      final valueTelemetry =
          spec.useBoatWideTelemetry ? widget.telemetryController.telemetry : telemetry;
      valueText = spec.valueText(valueTelemetry, unitIndex: widget.tile.unitIndex);
      // A tank is whatever it's actually holding — a fixed water-drop icon
      // and generic blue for every fluid tile is wrong for fuel, waste,
      // oil, etc. Matches the color/icon used on the fluid detail page. A
      // user override (Node settings → Tank → Fluid type) takes priority
      // over the device's own broadcast value, same as the detail page —
      // otherwise two tanks whose sensors both broadcast the same raw type
      // keep showing the same icon even after the user tells them apart.
      if (widget.tile.metric == DashboardMetricType.fluidLevelPct) {
        final fluidType =
            widget.nodeSettingsService.forDevice(device).customFluidTypeLabel ??
                telemetry.fluidType;
        icon = iconForFluidType(fluidType);
        metricColor = colorForFluidType(fluidType);
      }
    }
    // An active alarm overrides whatever color the metric would otherwise
    // show (including a tank's fluid-type color) — it's the most important
    // thing to notice on the tile.
    if (alarming) {
      metricColor = cs.error;
    }

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: alarming ? cs.error : cs.outline.withValues(alpha: 0.12),
          width: alarming ? 2 : 1,
        ),
      ),
      child: InkWell(
        // The whole tile cycles the unit — much easier to hit than a small
        // icon, and there's nothing else to tap here outside edit mode.
        onTap: spec.supportsUnitCycling ? widget.onCycleUnit : null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: metricColor.withValues(alpha: live ? 0.16 : 0.08),
                        ),
                        child: Icon(
                          icon,
                          size: 16,
                          color: metricColor.withValues(alpha: live ? 1 : 0.5),
                        ),
                      ),
                      if (alarming)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.error,
                              border: Border.all(color: cs.surface, width: 1.5),
                            ),
                            child: const Icon(
                              Icons.priority_high_rounded,
                              size: 9,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  if (widget.onRemove != null)
                    InkWell(
                      onTap: widget.onRemove,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        child: Icon(Icons.close, size: 16, color: cs.error),
                      ),
                    )
                  else
                    LiveActivityIndicator(
                      lastEventAt: device?.lastSeen,
                      staleAfter: kDeviceOfflineAfter,
                      size: 7,
                    ),
                ],
              ),
              // The value is the thing someone glances at the dashboard for —
              // keep it centered and dominant. The caption names the data
              // (e.g. "AWS"), not the device, since one device can back
              // several tiles. Both are wrapped in FittedBox so a longer
              // unit (km/h vs kn) or label never clips instead of shrinking.
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      valueText ?? '—',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: valueText == null
                            ? cs.onSurface.withValues(alpha: 0.35)
                            : cs.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  spec.shortLabel,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
