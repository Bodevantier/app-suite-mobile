import 'dart:async';

import 'package:flutter/material.dart';

import '../ble/controllers/ble_gateway_controller.dart';
import '../controllers/ble_controller.dart';
import '../dashboard/dashboard_metric_catalog.dart';
import '../dashboard/dashboard_tile_resolver.dart';
import '../models/dashboard_layout.dart';
import '../models/n2k_device_info.dart';
import '../n2k/n2k_liveness.dart';
import '../services/wind_angle_history_service.dart';
import 'live_activity_indicator.dart';
import 'wind_gauge.dart';

/// How much recent wind-angle history trails behind the needle, fading out
/// with age — a compact cousin of the full Wind page's trail/heatmap, sized
/// for a small dashboard tile rather than a configurable window.
const Duration _kTrailWindow = Duration(seconds: 90);

/// A larger (2x2) dashboard tile showing wind angle relative to the boat,
/// plus the corresponding speed — built on the same [WindGauge] used by the
/// full-screen Wind data page, so it looks and animates identically.
///
/// Reuses [DashboardTile.metric] to mean "which speed is currently shown" —
/// windApparentSpeed or windTrueSpeed — toggled by tapping the gauge; the
/// matching angle (AWA/effective TWA) is derived from that. Tapping the
/// icon cycles the speed unit, same interaction as [MetricTile].
class WindCompassTile extends StatefulWidget {
  const WindCompassTile({
    super.key,
    required this.tile,
    required this.bleGatewayController,
    required this.telemetryController,
    required this.windAngleHistory,
    this.onRemove,
    this.onCycleUnit,
    this.onToggleMode,
  });

  final DashboardTile tile;
  final BleGatewayController bleGatewayController;
  final BleController telemetryController;
  final WindAngleHistoryService windAngleHistory;
  final VoidCallback? onRemove;
  final VoidCallback? onCycleUnit;
  final VoidCallback? onToggleMode;

  @override
  State<WindCompassTile> createState() => _WindCompassTileState();
}

class _WindCompassTileState extends State<WindCompassTile> {
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

  bool get _isTrue => widget.tile.metric == DashboardMetricType.windTrueSpeed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.bleGatewayController,
        widget.telemetryController,
        widget.windAngleHistory,
      ]),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final windColor = colorForMetric(DashboardMetricType.windApparentSpeed);
    final speedType = _isTrue
        ? DashboardMetricType.windTrueSpeed
        : DashboardMetricType.windApparentSpeed;
    final spec = dashboardMetricCatalog[speedType]!;
    final device = resolveTileDevice(
      widget.tile,
      filterSetupVisibleDevices(widget.bleGatewayController.devices),
    );

    final live = device != null && isDeviceLive(device);
    String? valueText;
    double? angleDeg;
    var history = const <AngleSample>[];
    if (live) {
      // True wind is computed from apparent wind + SOG, which almost never
      // come from the same physical device — read the boat-wide fused
      // telemetry for it so the tile isn't permanently stuck blank.
      final telemetry = spec.useBoatWideTelemetry
          ? widget.telemetryController.telemetry
          : widget.telemetryController.telemetryFor(device.src);
      valueText = spec.valueText(telemetry, unitIndex: widget.tile.unitIndex);
      angleDeg =
          _isTrue ? telemetry.effectiveTrueWindAngleDeg : telemetry.apparentWindAngleDeg;
      history = _isTrue
          ? widget.windAngleHistory.trueHistory(_kTrailWindow)
          : widget.windAngleHistory.apparentHistory(_kTrailWindow);
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                InkWell(
                  onTap: spec.supportsUnitCycling ? widget.onCycleUnit : null,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: windColor.withValues(alpha: live ? 0.16 : 0.08),
                    ),
                    child: Icon(
                      Icons.air,
                      size: 17,
                      color: windColor.withValues(alpha: live ? 1 : 0.5),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: windColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _isTrue ? 'TRUE' : 'APPARENT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: windColor,
                    ),
                  ),
                ),
                const Spacer(),
                if (widget.onRemove != null)
                  InkWell(
                    onTap: widget.onRemove,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      child: Icon(Icons.close, size: 17, color: cs.error),
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
            Expanded(
              child: InkWell(
                onTap: widget.onToggleMode,
                borderRadius: BorderRadius.circular(16),
                child: WindGauge(
                  angleDeg: angleDeg,
                  history: history,
                  showHeatmap: true,
                  trailHalfLifeSec: 25,
                  trailSigmaDeg: 3,
                  showPortStarboardLabels: false,
                ),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                valueText ?? '—',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  color: valueText == null
                      ? cs.onSurface.withValues(alpha: 0.35)
                      : cs.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                spec.shortLabel,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
