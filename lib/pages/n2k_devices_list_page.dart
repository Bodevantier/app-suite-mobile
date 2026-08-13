import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_dependencies.dart';
import '../controllers/ble_controller.dart';
import '../models/n2k_device_info.dart';
import '../n2k/fluid_icons.dart';
import '../n2k/n2k_liveness.dart';
import '../services/node_settings_service.dart';
import '../widgets/connection_banners.dart';
import 'ble_connection_page.dart';
import 'engine_data_page.dart';
import 'fluid_level_data_page.dart';
import 'n2k_device_detail_page.dart';
import 'navigation_data_page.dart';
import 'temperature_data_page.dart';
import 'wind_data_page.dart';

/// The full list of N2K devices currently visible on the bus, with
/// tap-through into each device's data page. This used to be the home page
/// body; it now lives behind a "Devices" entry point from the dashboard
/// home page so the raw device list (useful for troubleshooting) stays
/// available without competing with the curated dashboards for the main
/// screen.
class N2kDevicesListPage extends StatefulWidget {
  const N2kDevicesListPage({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<N2kDevicesListPage> createState() => _N2kDevicesListPageState();
}

class _N2kDevicesListPageState extends State<N2kDevicesListPage> {
  // See _AppHomePageState in ble_gateway_app.dart for why rebuilds are
  // coalesced — the underlying controllers notify on every BLE chunk (often
  // 20+ Hz under heavy N2K traffic).
  static const Duration _kRebuildInterval = Duration(milliseconds: 250);

  Timer? _stalenessTicker;
  Timer? _coalesceTimer;
  DateTime? _lastRebuildAt;
  Listenable? _listenable;
  String? _lastQueuedVisualState;

  AppDependencies get dependencies => widget.dependencies;

  @override
  void initState() {
    super.initState();
    _listenable = Listenable.merge([
      dependencies.bleGatewayController,
      dependencies.autoConnectService,
      dependencies.demoMode,
    ]);
    _listenable!.addListener(_onSourceChanged);
    _stalenessTicker = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _listenable?.removeListener(_onSourceChanged);
    _coalesceTimer?.cancel();
    _stalenessTicker?.cancel();
    super.dispose();
  }

  String _deviceFingerprint(N2kDeviceInfo d) =>
      '${d.src}|${d.displayName}|${d.displayCategory}|${d.online ? 1 : 0}';

  String _computeVisualState() {
    final ctrl = dependencies.bleGatewayController;
    final auto = dependencies.autoConnectService;
    final isConnected = ctrl.isConnected;
    final isConnecting = ctrl.isConnecting ||
        (auto.isRunning && !isConnected && auto.status.isNotEmpty);
    final devices =
        filterSetupVisibleDevices(ctrl.devices).map(_deviceFingerprint).join(',');
    return '${isConnected ? 1 : 0}|${isConnecting ? 1 : 0}|$devices';
  }

  void _onSourceChanged() {
    if (!mounted) return;
    final newState = _computeVisualState();
    if (newState == _lastQueuedVisualState) return;
    _lastQueuedVisualState = newState;

    final now = DateTime.now();
    final last = _lastRebuildAt;
    if (last == null || now.difference(last) >= _kRebuildInterval) {
      _lastRebuildAt = now;
      _coalesceTimer?.cancel();
      _coalesceTimer = null;
      setState(() {});
      return;
    }
    if (_coalesceTimer?.isActive ?? false) return;
    final wait = _kRebuildInterval - now.difference(last);
    _coalesceTimer = Timer(wait, () {
      _coalesceTimer = null;
      if (!mounted) return;
      _lastRebuildAt = DateTime.now();
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final devices = filterSetupVisibleDevices(
      dependencies.bleGatewayController.devices,
    );
    final isConnected = dependencies.bleGatewayController.isConnected;
    final isConnecting = dependencies.bleGatewayController.isConnecting ||
        dependencies.autoConnectService.isRunning &&
            !isConnected &&
            dependencies.autoConnectService.status.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('N2K Devices')),
      body: Column(
        children: [
          if (dependencies.demoMode.isActive)
            DemoModeBanner(onTurnOff: dependencies.demoMode.disable),
          if (isConnecting && !isConnected)
            ConnectingBanner(
              status: dependencies.autoConnectService.status.isNotEmpty
                  ? dependencies.autoConnectService.status
                  : 'Connecting to gateway…',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BleConnectionPage(
                      controller: dependencies.bleGatewayController,
                      autoConnectService: dependencies.autoConnectService,
                      preferences: dependencies.preferences,
                      demoModeActive: dependencies.demoMode.isActive,
                    ),
                  ),
                );
              },
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Devices on the N2K network',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isConnected
                        ? (devices.isEmpty
                            ? 'No N2K devices detected on the bus yet.'
                            : 'Tap a device to view its data.')
                        : isConnecting
                            ? 'Connecting to the gateway…'
                            : 'Connect to the gateway to see N2K devices.',
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: devices.isEmpty
                        ? Center(
                            child: Text(
                              isConnected
                                  ? 'Waiting for devices...'
                                  : isConnecting
                                      ? 'Connecting to gateway…'
                                      : 'Not connected to gateway.',
                            ),
                          )
                        : ListView.builder(
                            itemCount: devices.length,
                            itemBuilder: (context, index) {
                              final device = devices[index];
                              final deviceLive =
                                  isConnected && isDeviceLive(device);
                              final card = _HomeDeviceCard(
                                key: ValueKey<int>(device.src),
                                device: device,
                                isLive: deviceLive,
                                settingsService: dependencies.nodeSettings,
                                telemetryController:
                                    dependencies.telemetryController,
                                onTap: !deviceLive
                                    ? null
                                    : () => _openDevice(context, device),
                              );
                              if (deviceLive) {
                                return card;
                              }
                              return Dismissible(
                                key: ValueKey<String>('n2k-device-${device.src}'),
                                direction: DismissDirection.endToStart,
                                background: _OfflineDismissBackground(),
                                confirmDismiss: (_) async {
                                  return await showDialog<bool>(
                                        context: context,
                                        builder: (dialogCtx) => AlertDialog(
                                          title: const Text('Remove offline device?'),
                                          content: Text(
                                            '${device.displayName} (src ${device.sourceAddress}) will be removed from the list. '
                                            'It will reappear automatically if it comes back on the bus.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(dialogCtx).pop(false),
                                              child: const Text('Cancel'),
                                            ),
                                            FilledButton.tonal(
                                              onPressed: () =>
                                                  Navigator.of(dialogCtx).pop(true),
                                              child: const Text('Remove'),
                                            ),
                                          ],
                                        ),
                                      ) ??
                                      false;
                                },
                                onDismissed: (_) {
                                  dependencies.bleGatewayController
                                      .forgetDevice(device.src);
                                  unawaited(
                                    dependencies.preferences.saveCachedN2kDevices(
                                      dependencies.bleGatewayController.devices
                                          .toList(),
                                    ),
                                  );
                                },
                                child: card,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openDevice(BuildContext context, N2kDeviceInfo device) {
    // Temperature must be checked before wind — some sensors broadcast wind
    // PGNs even if they are temp devices.
    if (device.isTemperatureDevice) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TemperatureDataPage(
            device: device,
            telemetryController: dependencies.telemetryController,
            temperatureHistory: dependencies.temperatureHistory,
            settingsService: dependencies.nodeSettings,
          ),
        ),
      );
      return;
    }

    if (device.isFluidLevelDevice) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FluidLevelDataPage(
            device: device,
            telemetryController: dependencies.telemetryController,
            settingsService: dependencies.nodeSettings,
          ),
        ),
      );
      return;
    }

    if (device.isEngineDevice) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EngineDataPage(
            device: device,
            telemetryController: dependencies.telemetryController,
            settingsService: dependencies.nodeSettings,
          ),
        ),
      );
      return;
    }

    if (device.isWindDevice) {
      final devices = filterSetupVisibleDevices(
        dependencies.bleGatewayController.devices,
      );
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WindDataPage(
            device: device,
            telemetryController: dependencies.telemetryController,
            windAngleHistory: dependencies.windAngleHistory,
            windAverages: dependencies.windAverages,
            settingsService: dependencies.nodeSettings,
            hasNavigationDevice: devices.any((d) => d.isNavigationDevice),
          ),
        ),
      );
      return;
    }

    if (device.isNavigationDevice) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NavigationDataPage(
            device: device,
            telemetryController: dependencies.telemetryController,
            settingsService: dependencies.nodeSettings,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => N2kDeviceDetailPage(
          device: device,
          controller: dependencies.bleGatewayController,
        ),
      ),
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

class _HomeDeviceCard extends StatefulWidget {
  const _HomeDeviceCard({
    super.key,
    required this.device,
    required this.isLive,
    required this.onTap,
    this.settingsService,
    this.telemetryController,
  });

  final N2kDeviceInfo device;
  final bool isLive;
  final VoidCallback? onTap;
  final NodeSettingsService? settingsService;
  final BleController? telemetryController;

  @override
  State<_HomeDeviceCard> createState() => _HomeDeviceCardState();
}

class _HomeDeviceCardState extends State<_HomeDeviceCard>
    with SingleTickerProviderStateMixin {
  // Slow, smooth pulse — eased sine, not a hard on/off blink — so the card
  // breathes red rather than flashing aggressively. ~2.4 s full cycle.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  late final Animation<double> _pulseEased = CurvedAnimation(
    parent: _pulse,
    curve: Curves.easeInOutSine,
    reverseCurve: Curves.easeInOutSine,
  );

  bool _alarmActive = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _evaluateAlarm();
  }

  @override
  void didUpdateWidget(covariant _HomeDeviceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _evaluateAlarm();
  }

  void _evaluateAlarm() {
    final active = _isAlarmActive();
    if (active == _alarmActive) return;
    _alarmActive = active;
    if (active) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  bool _isAlarmActive() {
    if (!widget.isLive) return false;
    final settings = widget.settingsService?.forDevice(widget.device);
    // Evaluate alarms against this node's own telemetry — the boat-wide
    // telemetry holds whichever node transmitted last and would trip the
    // alarm on the wrong card when two devices share a PGN.
    final telemetry =
        widget.telemetryController?.telemetryFor(widget.device.sourceAddress);

    if (widget.device.isFluidLevelDevice) {
      if (settings == null || !settings.lowLevelAlarmEnabled) return false;
      final level = telemetry?.fluidLevelPct;
      if (level == null) return false;
      return level <= settings.lowLevelAlarmPct;
    }

    if (widget.device.isTemperatureDevice) {
      if (settings == null) return false;
      final tempC = telemetry?.temperatureC;
      if (tempC == null) return false;
      if (settings.highTempAlarmEnabled && tempC >= settings.highTempAlarmC) {
        return true;
      }
      if (settings.lowTempAlarmEnabled && tempC <= settings.lowTempAlarmC) {
        return true;
      }
      return false;
    }

    return false;
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final device = widget.device;
    final mutedAlpha = widget.isLive ? 1.0 : 0.45;
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.settingsService,
        widget.telemetryController,
        _pulseEased,
      ]),
      builder: (context, _) {
        _evaluateAlarm();
        final settings = widget.settingsService?.forDevice(device);
        final overrideName = settings?.customName;
        final displayName =
            (overrideName != null && overrideName.trim().isNotEmpty)
                ? overrideName.trim()
                : device.displayName;
        // A tank's icon and color follow what it's actually holding (fuel,
        // waste, oil, ...) rather than defaulting every fluid sensor to a
        // generic blue water drop — needs live telemetry, so it's read
        // inside the builder. Matches the fluid detail page's coloring.
        final fluidType = device.isFluidLevelDevice
            ? widget.telemetryController
                ?.telemetryFor(device.sourceAddress)
                .fluidType
            : null;
        return _buildCard(
          context,
          cs: cs,
          tt: tt,
          icon: _iconFor(device, fluidType),
          color: _colorFor(device, cs, fluidType),
          mutedAlpha: mutedAlpha,
          displayName: displayName,
          alarmIntensity: _alarmActive ? _pulseEased.value : 0.0,
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required ColorScheme cs,
    required TextTheme tt,
    required IconData icon,
    required Color color,
    required double mutedAlpha,
    required String displayName,
    required double alarmIntensity,
  }) {
    final device = widget.device;
    final isLive = widget.isLive;
    final cardColor = alarmIntensity > 0
        ? Color.lerp(
            Theme.of(context).cardColor,
            const Color(0xffef4444),
            0.10 + 0.30 * alarmIntensity,
          )
        : null;
    final borderColor = alarmIntensity > 0
        ? const Color(0xffef4444).withValues(alpha: 0.35 + 0.55 * alarmIntensity)
        : null;
    return Opacity(
      opacity: isLive ? 1.0 : 0.7,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 1,
        color: cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: borderColor != null
              ? BorderSide(color: borderColor, width: 1.2)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15 * mutedAlpha),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color.withValues(alpha: mutedAlpha), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isLive
                            ? _capitalize(device.displayCategory)
                            : 'Offline · ${_capitalize(device.displayCategory)}',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(N2kDeviceInfo d, [String? fluidType]) {
    if (d.isBleGatewayDevice) return Icons.bluetooth;
    if (d.isTemperatureDevice) return Icons.thermostat;
    if (d.isFluidLevelDevice) return iconForFluidType(fluidType);
    if (d.isEngineDevice) return Icons.speed;
    if (d.isWindDevice) return Icons.air;
    if (d.isNavigationDevice) return Icons.satellite_alt;
    return Icons.sensors;
  }

  static Color _colorFor(N2kDeviceInfo d, ColorScheme cs, [String? fluidType]) {
    if (d.isBleGatewayDevice) return cs.primary;
    if (d.isTemperatureDevice) return Colors.orange.shade700;
    if (d.isFluidLevelDevice) return colorForFluidType(fluidType);
    if (d.isEngineDevice) return Colors.red.shade600;
    if (d.isWindDevice) return Colors.blue.shade600;
    if (d.isNavigationDevice) return Colors.green.shade700;
    return cs.secondary;
  }
}

class _OfflineDismissBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Remove',
            style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Icon(Icons.delete_outline, color: cs.onErrorContainer),
        ],
      ),
    );
  }
}
