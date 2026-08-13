import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/n2k_device_info.dart';
import '../pages/about_page.dart';
import '../pages/ble_connection_page.dart';
import '../pages/n2k_device_detail_page.dart';
import '../pages/navigation_data_page.dart';
import '../pages/temperature_data_page.dart';
import '../pages/fluid_level_data_page.dart';
import '../pages/engine_data_page.dart';
import '../pages/welcome_page.dart';
import '../pages/wind_data_page.dart';
import '../services/node_settings_service.dart';
import '../controllers/ble_controller.dart';
import 'app_dependencies.dart';

class BleGatewayApp extends StatefulWidget {
  const BleGatewayApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<BleGatewayApp> createState() => _BleGatewayAppState();
}

class _BleGatewayAppState extends State<BleGatewayApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startAutoConnectIfKnown();
  }

  void _startAutoConnectIfKnown() {
    final knownId = widget.dependencies.preferences.knownGatewayId;
    if (knownId == null) return;
    final auto = widget.dependencies.autoConnectService;
    // start() is a no-op if already watching this device (e.g. a background
    // watch kept alive while the app was closed) — retryNow() forces an
    // immediate attempt in that case instead of waiting for the next
    // periodic retry.
    if (auto.isRunning) {
      auto.retryNow();
    } else {
      auto.start(knownId);
    }
  }

  @override
  void dispose() {
    widget.dependencies.autoConnectService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(widget.dependencies.bleGatewayController.shutdown());
    } else if (state == AppLifecycleState.resumed) {
      // Returning to the app should feel instant — don't wait on whatever
      // passive reconnect state happens to already be in flight.
      _startAutoConnectIfKnown();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 BLE Gateway',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: RootPage(dependencies: widget.dependencies),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.dependencies.appSetupController,
      builder: (context, _) {
        if (!widget.dependencies.appSetupController.setupComplete) {
          return WelcomePage(
            onStartSetup: () =>
                _openBleSetupFlow(context, widget.dependencies),
          );
        }
        return AppHomePage(dependencies: widget.dependencies);
      },
    );
  }
}

Future<void> _openBleSetupFlow(
  BuildContext context,
  AppDependencies dependencies,
) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BleConnectionPage(
        controller: dependencies.bleGatewayController,
        autoConnectService: dependencies.autoConnectService,
        preferences: dependencies.preferences,
        // BleConnectionPage's own _connect() already remembers the gateway
        // and starts auto-connect for future launches — this callback only
        // needs to advance past the setup flow.
        onConnectionReady: (connectionContext) async {
          // Once paired with the gateway, the home page automatically shows
          // every N2K sensor present on the bus — no per-sensor "Add" step.
          dependencies.appSetupController.completeSetup();
          if (Navigator.of(connectionContext).canPop()) {
            Navigator.of(connectionContext).popUntil((route) => route.isFirst);
          }
        },
      ),
    ),
  );
}

class AppHomePage extends StatefulWidget {
  const AppHomePage({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<AppHomePage> createState() => _AppHomePageState();
}

class _AppHomePageState extends State<AppHomePage> {
  // Minimum spacing between visible rebuilds. The underlying controllers
  // notify on every BLE chunk (often 20+ Hz under heavy N2K traffic), which
  // made the home page list and the per-card pulse indicator visibly jitter.
  // Coalescing into ~4 frames per second still feels live but is rock steady.
  static const Duration _kRebuildInterval = Duration(milliseconds: 250);

  Timer? _stalenessTicker;
  Timer? _coalesceTimer;
  DateTime? _lastRebuildAt;
  Listenable? _listenable;
  // Visual fingerprint of the last queued rebuild. Allows _onSourceChanged to
  // bail early when only lastSeen timestamps changed — those don't affect
  // what the home page renders (isLive transitions are caught by _stalenessTicker).
  String? _lastQueuedVisualState;

  @override
  void initState() {
    super.initState();
    _listenable = Listenable.merge([
      dependencies.appSetupController,
      dependencies.bleGatewayController,
      dependencies.autoConnectService,
      dependencies.demoMode,
    ]);
    _listenable!.addListener(_onSourceChanged);
    // Re-evaluate device freshness periodically so cards flip to "offline"
    // even when no new BLE notifications arrive (no notifyListeners fires
    // when a device simply stops transmitting).
    _stalenessTicker = Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _listenable?.removeListener(_onSourceChanged);
    _coalesceTimer?.cancel();
    _stalenessTicker?.cancel();
    super.dispose();
  }

  /// Compact fingerprint of the fields each home-page card renders.
  /// Intentionally excludes [lastSeen] — that changes every BLE frame but
  /// does not affect what the card displays; isLive transitions are caught
  /// by the 2-second staleness ticker instead.
  String _deviceFingerprint(N2kDeviceInfo d) =>
      '${d.src}|${d.displayName}|${d.displayCategory}|'
      '${d.online ? 1 : 0}';

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
    // Fast exit: skip rebuild when nothing the home page renders has changed.
    // Telemetry values (wind/temp readings) are handled by each card's own
    // AnimatedBuilder; isLive transitions are handled by _stalenessTicker.
    final newState = _computeVisualState();
    if (newState == _lastQueuedVisualState) return;
    _lastQueuedVisualState = newState;

    final now = DateTime.now();
    final last = _lastRebuildAt;
    if (last == null || now.difference(last) >= _kRebuildInterval) {
      // Far enough from the previous frame: rebuild immediately.
      _lastRebuildAt = now;
      _coalesceTimer?.cancel();
      _coalesceTimer = null;
      setState(() {});
      return;
    }
    // Inside the cool-down window: coalesce into a single trailing rebuild.
    if (_coalesceTimer?.isActive ?? false) return;
    final wait = _kRebuildInterval - now.difference(last);
    _coalesceTimer = Timer(wait, () {
      _coalesceTimer = null;
      if (!mounted) return;
      _lastRebuildAt = DateTime.now();
      setState(() {});
    });
  }

  AppDependencies get dependencies => widget.dependencies;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        // Show every N2K sensor the gateway currently sees on the bus
        // (excluding the gateway itself). The user has already chosen which
        // physical devices belong on their N2K network — the app should just
        // display them automatically, no manual "Add device" step.
        final devices = filterSetupVisibleDevices(
          dependencies.bleGatewayController.devices,
        );
        final isConnected = dependencies.bleGatewayController.isConnected;
        final isConnecting = dependencies.bleGatewayController.isConnecting ||
            dependencies.autoConnectService.isRunning &&
                !isConnected &&
                dependencies.autoConnectService.status.isNotEmpty;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Home'),
            actions: [
              IconButton(
                tooltip: 'About',
                icon: const Icon(Icons.info_outline),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AboutPage(demoMode: dependencies.demoMode),
                    ),
                  );
                },
              ),
              _GatewayStatusIcon(
                isConnected: isConnected,
                isConnecting: isConnecting,
                lastChunkAt:
                    dependencies.bleGatewayController.lastChunkAt,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BleConnectionPage(
                        controller: dependencies.bleGatewayController,
                        autoConnectService:
                            dependencies.autoConnectService,
                        preferences: dependencies.preferences,
                        demoModeActive: dependencies.demoMode.isActive,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: [
              if (dependencies.demoMode.isActive)
                _DemoModeBanner(onTurnOff: dependencies.demoMode.disable),
              if (isConnecting && !isConnected)
                _ConnectingBanner(
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
              // ── Body ──────────────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Devices on the N2K network',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w700),
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
                                  // A device is considered offline when the
                                  // gateway link is down OR we haven't seen
                                  // any frame from it for a while. Tapping it
                                  // should not open the data page — the data
                                  // would be stale and misleading.
                                  final isDeviceLive = isConnected &&
                                      _isDeviceLive(device);
                                  final card = _HomeDeviceCard(
                                      key: ValueKey<int>(device.src),
                                      device: device,
                                      isLive: isDeviceLive,
                                      settingsService:
                                          dependencies.nodeSettings,
                                      telemetryController:
                                          dependencies.telemetryController,
                                      onTap: !isDeviceLive
                                          ? null
                                          : () {
                                        // Temperature must be checked before
                                        // wind — some sensors broadcast wind
                                        // PGNs even if they are temp devices.
                                        if (device.isTemperatureDevice) {
                                          Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) => TemperatureDataPage(
                                                device: device,
                                                telemetryController: dependencies
                                                    .telemetryController,
                                                temperatureHistory: dependencies
                                                    .temperatureHistory,
                                                settingsService:
                                                    dependencies.nodeSettings,
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
                                                telemetryController: dependencies
                                                    .telemetryController,
                                                settingsService:
                                                    dependencies.nodeSettings,
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
                                                telemetryController: dependencies
                                                    .telemetryController,
                                                settingsService:
                                                    dependencies.nodeSettings,
                                              ),
                                            ),
                                          );
                                          return;
                                        }

                                        if (device.isWindDevice) {
                                          Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) => WindDataPage(
                                                device: device,
                                                telemetryController: dependencies
                                                    .telemetryController,
                                                windAngleHistory: dependencies
                                                    .windAngleHistory,
                                                windAverages:
                                                    dependencies.windAverages,
                                                settingsService:
                                                    dependencies.nodeSettings,
                                                hasNavigationDevice:
                                                    devices.any(
                                                  (d) => d.isNavigationDevice,
                                                ),
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
                                                telemetryController: dependencies
                                                    .telemetryController,
                                                settingsService:
                                                    dependencies.nodeSettings,
                                              ),
                                            ),
                                          );
                                          return;
                                        }

                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => N2kDeviceDetailPage(
                                              device: device,
                                              controller: dependencies
                                                  .bleGatewayController,
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  // Offline devices can be removed with a
                                  // right-to-left swipe. Live devices are
                                  // never dismissible — they will reappear
                                  // immediately on the next frame anyway.
                                  if (isDeviceLive) {
                                    return card;
                                  }
                                  return Dismissible(
                                    key: ValueKey<String>(
                                        'n2k-device-${device.src}'),
                                    direction: DismissDirection.endToStart,
                                    background: _OfflineDismissBackground(),
                                    confirmDismiss: (_) async {
                                      return await showDialog<bool>(
                                            context: context,
                                            builder: (dialogCtx) => AlertDialog(
                                              title: const Text(
                                                  'Remove offline device?'),
                                              content: Text(
                                                '${device.displayName} (src ${device.sourceAddress}) will be removed from the list. '
                                                'It will reappear automatically if it comes back on the bus.',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.of(dialogCtx)
                                                          .pop(false),
                                                  child:
                                                      const Text('Cancel'),
                                                ),
                                                FilledButton.tonal(
                                                  onPressed: () =>
                                                      Navigator.of(dialogCtx)
                                                          .pop(true),
                                                  child:
                                                      const Text('Remove'),
                                                ),
                                              ],
                                            ),
                                          ) ??
                                          false;
                                    },
                                    onDismissed: (_) {
                                      dependencies.bleGatewayController
                                          .forgetDevice(device.src);
                                      // Persist the trimmed cache so the
                                      // node does not reappear on next launch
                                      // before the gateway re-snapshots.
                                      unawaited(
                                        dependencies.preferences
                                            .saveCachedN2kDevices(
                                          dependencies
                                              .bleGatewayController.devices
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
      },
    );
  }
}

// ── Demo mode banner ─────────────────────────────────────────────────────────

/// Sits above the device list whenever Demo Mode is active, so simulated
/// data is never mistaken for a real boat's readings.
class _DemoModeBanner extends StatelessWidget {
  const _DemoModeBanner({required this.onTurnOff});

  final VoidCallback onTurnOff;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer,
      child: InkWell(
        onTap: onTurnOff,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.theater_comedy_outlined,
                  size: 18, color: cs.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Demo Mode — showing simulated data',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
              Text(
                'Turn off',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: cs.onPrimaryContainer,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Prominent "reconnecting" banner shown on the Home page body while a
/// known gateway is being auto-connected to — so the user always has
/// visible, live feedback instead of a page that just looks inert. Mirrors
/// [_GatewayStatusIcon]'s "connecting" color so the two agree at a glance.
class _ConnectingBanner extends StatelessWidget {
  const _ConnectingBanner({required this.status, required this.onTap});

  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Colors.orange.shade700;
    return Material(
      color: Colors.orange.shade50,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  status,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Colors.orange.shade900,
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

// ── Home page device card ────────────────────────────────────────────────────

/// Maximum age of the last frame for a device to still be considered "live"
/// enough to open its data page. Beyond this, the card greys out and tapping
/// is disabled — opening the data page would only show stale numbers.
const Duration _kDeviceOfflineAfter = Duration(seconds: 15);

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

bool _isDeviceLive(N2kDeviceInfo device) {
  if (!device.isOnline) return false;
  final lastSeen = device.lastSeen;
  if (lastSeen == null) return false;
  return DateTime.now().difference(lastSeen) < _kDeviceOfflineAfter;
}

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

    // Fluid level — low alarm.
    if (widget.device.isFluidLevelDevice) {
      if (settings == null || !settings.lowLevelAlarmEnabled) return false;
      final level = telemetry?.fluidLevelPct;
      if (level == null) return false;
      return level <= settings.lowLevelAlarmPct;
    }

    // Temperature — high or low alarm.
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
    final icon = _iconFor(device);
    final color = _colorFor(device, cs);
    final mutedAlpha = widget.isLive ? 1.0 : 0.45;
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.settingsService,
        widget.telemetryController,
        _pulseEased,
      ]),
      builder: (context, _) {
        // Re-evaluate every rebuild — settings or telemetry may have changed
        // since the last frame and we need to start/stop the pulse promptly.
        _evaluateAlarm();
        final settings = widget.settingsService?.forDevice(device);
        final overrideName = settings?.customName;
        final displayName =
            (overrideName != null && overrideName.trim().isNotEmpty)
                ? overrideName.trim()
                : device.displayName;
        return _buildCard(
          context,
          cs: cs,
          tt: tt,
          icon: icon,
          color: color,
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
    // Blend card surface from neutral toward a soft red as the pulse rises.
    // We never go fully saturated — the card must remain readable and the
    // animation must feel like a heartbeat, not a strobe.
    final cardColor = alarmIntensity > 0
        ? Color.lerp(
            Theme.of(context).cardColor,
            const Color(0xffef4444), // red-500
            0.10 + 0.30 * alarmIntensity,
          )
        : null;
    final borderColor = alarmIntensity > 0
        ? const Color(0xffef4444).withValues(
            alpha: 0.35 + 0.55 * alarmIntensity,
          )
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
                // Icon bubble
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15 * mutedAlpha),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: color.withValues(alpha: mutedAlpha),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                // Name + subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
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

  static IconData _iconFor(N2kDeviceInfo d) {
    if (d.isBleGatewayDevice) return Icons.bluetooth;
    if (d.isTemperatureDevice) return Icons.thermostat;
    if (d.isFluidLevelDevice) return Icons.water_drop;
    if (d.isEngineDevice) return Icons.speed;
    if (d.isWindDevice) return Icons.air;
    if (d.isNavigationDevice) return Icons.satellite_alt;
    return Icons.sensors;
  }

  static Color _colorFor(N2kDeviceInfo d, ColorScheme cs) {
    if (d.isBleGatewayDevice) return cs.primary;
    if (d.isTemperatureDevice) return Colors.orange.shade700;
    if (d.isFluidLevelDevice) return Colors.blue.shade700;
    if (d.isEngineDevice) return Colors.red.shade600;
    if (d.isWindDevice) return Colors.blue.shade600;
    if (d.isNavigationDevice) return Colors.green.shade700;
    return cs.secondary;
  }
}

/// Red "delete" background revealed while swiping an offline device card.
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
            style: TextStyle(
              color: cs.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.delete_outline, color: cs.onErrorContainer),
        ],
      ),
    );
  }
}

class _GatewayStatusIcon extends StatefulWidget {
  const _GatewayStatusIcon({
    required this.isConnected,
    required this.isConnecting,
    required this.lastChunkAt,
    required this.onTap,
  });

  final bool isConnected;
  final bool isConnecting;
  final DateTime? lastChunkAt;
  final VoidCallback onTap;

  @override
  State<_GatewayStatusIcon> createState() => _GatewayStatusIconState();
}

class _GatewayStatusIconState extends State<_GatewayStatusIcon>
    with SingleTickerProviderStateMixin {
  static const Duration _staleAfter = Duration(seconds: 6);
  static const Duration _pulsePeriod = Duration(milliseconds: 2200);

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _pulsePeriod)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _freshness() {
    final last = widget.lastChunkAt;
    if (last == null) return 0;
    final elapsedMs = DateTime.now().difference(last).inMilliseconds.toDouble();
    final staleMs = _staleAfter.inMilliseconds.toDouble();
    if (elapsedMs <= 0) return 1;
    if (elapsedMs >= staleMs) return 0;
    return Curves.easeOut.transform(1.0 - (elapsedMs / staleMs));
  }

  @override
  Widget build(BuildContext context) {
    final IconData iconData;
    final Color baseColor;
    final String tooltip;

    if (widget.isConnected) {
      iconData = Icons.bluetooth_connected;
      baseColor = Colors.green.shade600;
      tooltip = 'Bluetooth connected — tap to manage';
    } else if (widget.isConnecting) {
      iconData = Icons.bluetooth_searching;
      baseColor = Colors.orange.shade700;
      tooltip = 'Connecting — tap to manage';
    } else {
      iconData = Icons.bluetooth_disabled;
      baseColor = Colors.red.shade400;
      tooltip = 'Not connected — tap to connect';
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final freshness = widget.isConnected ? _freshness() : 0.0;
        final pulse = (math.sin(_controller.value * 2 * math.pi) + 1) / 2;
        // Subtle, calm modulation when data is flowing.
        final brightness = 0.78 + 0.22 * pulse * freshness;

        final iconColor = widget.isConnected
            ? Color.lerp(
                Colors.grey.shade500,
                baseColor,
                freshness.clamp(0.25, 1.0),
              )!
            : baseColor;

        return IconButton(
          tooltip: tooltip,
          onPressed: widget.onTap,
          icon: Container(
            decoration: freshness <= 0.05
                ? null
                : BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: baseColor.withValues(alpha: 0.18 * freshness),
                        blurRadius: 10 * freshness,
                      ),
                    ],
                  ),
            child: Icon(
              iconData,
              color: iconColor.withValues(alpha: brightness),
              size: 22,
            ),
          ),
        );
      },
    );
  }
}