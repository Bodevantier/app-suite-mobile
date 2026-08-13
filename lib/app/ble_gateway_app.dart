import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../pages/ble_connection_page.dart';
import '../pages/dashboard_home_page.dart';
import '../pages/n2k_devices_list_page.dart';
import '../pages/settings_page.dart';
import '../pages/welcome_page.dart';
import '../widgets/connection_banners.dart';
import '../widgets/night_mode_filter.dart';
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
    // Only the visible app should ever start Night Mode's recheck/location
    // loop — never the headless BLE-wake isolate in main.dart, which has no
    // UI and nothing to theme.
    widget.dependencies.nightMode.startForeground();
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
    widget.dependencies.nightMode.dispose();
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
      // The OS may have throttled our timer while backgrounded — re-check
      // right away rather than waiting up to a minute.
      widget.dependencies.nightMode.recheckNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 BLE Gateway',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      builder: (context, child) => NightModeFilter(
        nightMode: widget.dependencies.nightMode,
        child: child!,
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

/// The app's main screen: a persistent shell (gateway status, Settings,
/// raw Devices list) wrapped around the swipeable dashboard content in
/// [DashboardHomePage].
class AppHomePage extends StatefulWidget {
  const AppHomePage({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<AppHomePage> createState() => _AppHomePageState();
}

class _AppHomePageState extends State<AppHomePage> {
  AppDependencies get dependencies => widget.dependencies;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        dependencies.bleGatewayController,
        dependencies.autoConnectService,
        dependencies.demoMode,
      ]),
      builder: (context, _) {
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
                tooltip: 'N2K devices',
                icon: const Icon(Icons.sensors),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => N2kDevicesListPage(dependencies: dependencies),
                    ),
                  );
                },
              ),
              _GatewayStatusChip(
                isConnected: isConnected,
                isConnecting: isConnecting,
                lastChunkAt: dependencies.bleGatewayController.lastChunkAt,
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
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsPage(
                        nightMode: dependencies.nightMode,
                        demoMode: dependencies.demoMode,
                        bleGatewayController: dependencies.bleGatewayController,
                        autoConnectService: dependencies.autoConnectService,
                        preferences: dependencies.preferences,
                        dashboards: dependencies.dashboards,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
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
              Expanded(child: DashboardHomePage(dependencies: dependencies)),
            ],
          ),
        );
      },
    );
  }
}

/// Compact, always-visible connection status pill shown on the Home app bar
/// — glanceable at a distance (helm, cockpit) without needing to open
/// Settings. Tapping it still jumps straight to [BleConnectionPage], since
/// that's the fastest path when something needs fixing; the same page is
/// also reachable from Settings for discoverability/consistency with the
/// app's other secondary screens.
class _GatewayStatusChip extends StatefulWidget {
  const _GatewayStatusChip({
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
  State<_GatewayStatusChip> createState() => _GatewayStatusChipState();
}

class _GatewayStatusChipState extends State<_GatewayStatusChip>
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
