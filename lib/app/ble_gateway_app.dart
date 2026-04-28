import 'dart:async';

import 'package:flutter/material.dart';

import '../ble/controllers/ble_gateway_controller.dart';
import '../controllers/app_setup_controller.dart';
import '../models/n2k_device_info.dart';
import '../pages/ble_monitor_page.dart';
import '../pages/device_setup_page.dart';
import '../pages/n2k_device_detail_page.dart';
import '../pages/navigation_data_page.dart';
import '../pages/temperature_data_page.dart';
import '../pages/welcome_page.dart';
import '../pages/wind_data_page.dart';
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
    if (knownId != null) {
      widget.dependencies.autoConnectService.start(knownId);
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

class RootPage extends StatelessWidget {
  const RootPage({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: dependencies.appSetupController,
      builder: (context, _) {
        if (!dependencies.appSetupController.setupComplete) {
          return WelcomePage(
            onStartSetup: () => _openBleSetupFlow(context, dependencies),
          );
        }
        return AppHomePage(dependencies: dependencies);
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
      builder: (_) => BleMonitorPage(
        controller: dependencies.bleGatewayController,
        autoStartScan: true,
        onConnectionReady: (monitorContext) async {
          // Remember this gateway and start auto-connect for future launches.
          final deviceId =
              dependencies.bleGatewayController.connectedDevice?.remoteId.str;
          if (deviceId != null) {
            unawaited(dependencies.preferences.saveKnownGatewayId(deviceId));
            dependencies.autoConnectService.start(deviceId);
          }

          await Navigator.of(monitorContext).pushReplacement(
            MaterialPageRoute<void>(
              builder: (deviceContext) => DeviceSetupPage(
                controller: dependencies.bleGatewayController,
                setupController: dependencies.appSetupController,
                onOpenDevice: (device) => _openSetupDevicePage(
                  deviceContext,
                  device,
                  dependencies.bleGatewayController,
                  dependencies.appSetupController,
                ),
                onFinishSetup: () {
                  dependencies.appSetupController.completeSetup();
                  Navigator.of(deviceContext).popUntil((route) => route.isFirst);
                },
              ),
            ),
          );
        },
      ),
    ),
  );
}

Future<void> _openSetupDevicePage(
  BuildContext context,
  N2kDeviceInfo device,
  BleGatewayController controller,
  AppSetupController setupController,
) async {
  final addLabel = setupController.isAdded(device) ? 'Added to home' : 'Add device';
  final onAdd = setupController.isAdded(device)
      ? null
      : (BuildContext pageContext) {
          setupController.addDevice(device);
          Navigator.of(pageContext).pop();
        };

  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (pageContext) => N2kDeviceDetailPage(
        device: device,
        controller: controller,
        primaryActionLabel: addLabel,
        onPrimaryAction: onAdd == null ? null : () => onAdd(pageContext),
      ),
    ),
  );
}

class AppHomePage extends StatelessWidget {
  const AppHomePage({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        dependencies.appSetupController,
        dependencies.bleGatewayController,
        dependencies.autoConnectService,
      ]),
      builder: (context, _) {
        final devices = dependencies.appSetupController.addedDevices;
        final isConnected = dependencies.bleGatewayController.isConnected;
        final isConnecting = dependencies.bleGatewayController.isConnecting ||
            dependencies.autoConnectService.isRunning &&
                !isConnected &&
                dependencies.autoConnectService.status.isNotEmpty;
        final autoStatus = dependencies.autoConnectService.status;

        return Scaffold(
          appBar: AppBar(title: const Text('Home')),
          body: Column(
            children: [
              // ── Connection status banner ──────────────────────────────
              _ConnectionBanner(
                isConnected: isConnected,
                isConnecting: isConnecting,
                statusText: isConnected
                    ? 'Connected to gateway'
                    : isConnecting
                        ? autoStatus.isNotEmpty
                            ? autoStatus
                            : 'Connecting...'
                        : autoStatus.isNotEmpty
                            ? autoStatus
                            : 'Not connected',
                onReconnect: isConnected || isConnecting
                    ? null
                    : () {
                        final knownId =
                            dependencies.preferences.knownGatewayId;
                        if (knownId != null) {
                          dependencies.autoConnectService.start(knownId);
                        } else {
                          _openBleSetupFlow(context, dependencies);
                        }
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
                        'Configured devices',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        devices.isEmpty
                            ? 'No devices have been added yet.'
                            : 'Open a configured device below, or add more devices from the gateway.',
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton(
                            onPressed: () {
                              if (isConnected) {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (ctx) => DeviceSetupPage(
                                      controller:
                                          dependencies.bleGatewayController,
                                      setupController:
                                          dependencies.appSetupController,
                                      onOpenDevice: (device) =>
                                          _openSetupDevicePage(
                                        ctx,
                                        device,
                                        dependencies.bleGatewayController,
                                        dependencies.appSetupController,
                                      ),
                                      onFinishSetup: () =>
                                          Navigator.of(ctx).pop(),
                                    ),
                                  ),
                                );
                              } else {
                                _openBleSetupFlow(context, dependencies);
                              }
                            },
                            child: const Text('Add devices'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: devices.isEmpty
                            ? const Center(
                                child:
                                    Text('Run setup to add your first device.'),
                              )
                            : ListView.builder(
                                itemCount: devices.length,
                                itemBuilder: (context, index) {
                                  final device = devices[index];
                                  return _HomeDeviceCard(
                                      device: device,
                                      onTap: () {
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
                                                windAverages:
                                                    dependencies.windAverages,
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

// ── Home page device card ────────────────────────────────────────────────────

class _HomeDeviceCard extends StatelessWidget {
  const _HomeDeviceCard({required this.device, required this.onTap});

  final N2kDeviceInfo device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final icon = _iconFor(device);
    final color = _colorFor(device, cs);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Icon bubble
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              // Name + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.displayName,
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'src ${device.sourceAddress} · ${device.displayCategory}',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Chevron
              Icon(Icons.chevron_right, size: 18,
                  color: cs.onSurface.withOpacity(0.3)),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(N2kDeviceInfo d) {
    if (d.isBleGatewayDevice) return Icons.bluetooth;
    if (d.isTemperatureDevice) return Icons.thermostat;
    if (d.isWindDevice) return Icons.air;
    if (d.isNavigationDevice) return Icons.satellite_alt;
    return Icons.sensors;
  }

  static Color _colorFor(N2kDeviceInfo d, ColorScheme cs) {
    if (d.isBleGatewayDevice) return cs.primary;
    if (d.isTemperatureDevice) return Colors.orange.shade700;
    if (d.isWindDevice) return Colors.blue.shade600;
    if (d.isNavigationDevice) return Colors.green.shade700;
    return cs.secondary;
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({
    required this.isConnected,
    required this.isConnecting,
    required this.statusText,
    this.onReconnect,
  });

  final bool isConnected;
  final bool isConnecting;
  final String statusText;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    final color = isConnected
        ? Colors.green.shade700
        : isConnecting
            ? Colors.orange.shade700
            : Colors.red.shade700;

    return Container(
      width: double.infinity,
      color: color.withAlpha(30),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            isConnected
                ? Icons.bluetooth_connected
                : isConnecting
                    ? Icons.bluetooth_searching
                    : Icons.bluetooth_disabled,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(color: color, fontWeight: FontWeight.w500),
            ),
          ),
          if (isConnecting) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
            ),
          ],
          if (onReconnect != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onReconnect,
              style: TextButton.styleFrom(foregroundColor: color),
              child: const Text('Reconnect'),
            ),
          ],
        ],
      ),
    );
  }
}