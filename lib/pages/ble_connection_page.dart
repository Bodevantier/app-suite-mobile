import 'dart:async';

import 'package:flutter/material.dart';

import '../ble/controllers/ble_gateway_controller.dart';
import '../ble/services/auto_connect_service.dart';
import '../services/app_preferences_service.dart';

/// Simple Bluetooth connection page.
///
/// Lets the user see the current gateway connection, scan for nearby
/// gateways, connect to one, disconnect, or forget the saved gateway so
/// auto-connect won't keep retrying it.
class BleConnectionPage extends StatefulWidget {
  const BleConnectionPage({
    super.key,
    required this.controller,
    required this.autoConnectService,
    required this.preferences,
  });

  final BleGatewayController controller;
  final AutoConnectService autoConnectService;
  final AppPreferencesService preferences;

  @override
  State<BleConnectionPage> createState() => _BleConnectionPageState();
}

class _BleConnectionPageState extends State<BleConnectionPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.controller.initialize();
      if (!mounted) return;
      // Auto-start a scan if we're not already connected, so the list
      // populates without the user having to tap anything.
      if (!widget.controller.isConnected && !widget.controller.isScanning) {
        unawaited(widget.controller.startScan());
      }
    });
  }

  Future<void> _connect(dynamic scanResult) async {
    try {
      await widget.controller.connect(scanResult);
      final id = widget.controller.connectedDevice?.remoteId.str;
      if (id != null) {
        unawaited(widget.preferences.saveKnownGatewayId(id));
        widget.autoConnectService.start(id);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connect failed: $error')),
      );
    }
  }

  Future<void> _disconnect() async {
    await widget.controller.disconnect();
  }

  Future<void> _forgetGateway() async {
    widget.autoConnectService.stop();
    await widget.preferences.saveKnownGatewayId(null);
    await widget.controller.disconnect();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.autoConnectService,
      ]),
      builder: (context, _) {
        final controller = widget.controller;
        final connectedId = controller.connectedDevice?.remoteId.str;
        final knownId = widget.preferences.knownGatewayId;
        final discovered = controller.discoveredDevices;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Bluetooth'),
            actions: [
              IconButton(
                tooltip: controller.isScanning ? 'Stop scan' : 'Scan',
                icon: Icon(
                  controller.isScanning ? Icons.stop : Icons.refresh,
                ),
                onPressed: controller.isScanning
                    ? () => unawaited(controller.stopScan())
                    : () => unawaited(controller.startScan()),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusCard(
                isConnected: controller.isConnected,
                isConnecting: controller.isConnecting,
                isScanning: controller.isScanning,
                connectedName: controller.connectedDevice?.platformName,
                connectedId: connectedId,
                autoStatus: widget.autoConnectService.status,
                onDisconnect:
                    controller.isConnected ? _disconnect : null,
                onForget: knownId != null ? _forgetGateway : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Nearby gateways',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(width: 8),
                  if (controller.isScanning)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child:
                          CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (discovered.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      controller.isScanning
                          ? 'Scanning...'
                          : 'No gateways found. Tap the refresh icon to scan.',
                    ),
                  ),
                )
              else
                ...discovered.map((result) {
                  final id = result.device.remoteId.str;
                  final isThisConnected = connectedId == id;
                  final isKnown = knownId == id;
                  final name = result.device.platformName.isNotEmpty
                      ? result.device.platformName
                      : 'Unnamed gateway';

                  return Card(
                    child: ListTile(
                      leading: Icon(
                        isThisConnected
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth,
                        color: isThisConnected
                            ? Colors.green.shade600
                            : null,
                      ),
                      title: Text(name),
                      subtitle: Text(
                        '$id  ·  RSSI ${result.rssi}'
                        '${isKnown ? '  ·  saved' : ''}',
                      ),
                      trailing: isThisConnected
                          ? TextButton(
                              onPressed: _disconnect,
                              child: const Text('Disconnect'),
                            )
                          : FilledButton(
                              onPressed: controller.isConnecting
                                  ? null
                                  : () => unawaited(_connect(result)),
                              child: const Text('Connect'),
                            ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.isConnected,
    required this.isConnecting,
    required this.isScanning,
    required this.connectedName,
    required this.connectedId,
    required this.autoStatus,
    required this.onDisconnect,
    required this.onForget,
  });

  final bool isConnected;
  final bool isConnecting;
  final bool isScanning;
  final String? connectedName;
  final String? connectedId;
  final String autoStatus;
  final VoidCallback? onDisconnect;
  final VoidCallback? onForget;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    final String title;
    final String? subtitle;

    if (isConnected) {
      icon = Icons.bluetooth_connected;
      color = Colors.green.shade600;
      title = (connectedName != null && connectedName!.isNotEmpty)
          ? connectedName!
          : 'Gateway';
      subtitle = connectedId;
    } else if (isConnecting) {
      icon = Icons.bluetooth_searching;
      color = Colors.orange.shade700;
      title = 'Connecting...';
      subtitle = autoStatus.isNotEmpty ? autoStatus : null;
    } else {
      icon = Icons.bluetooth_disabled;
      color = Colors.red.shade400;
      title = 'Not connected';
      subtitle = autoStatus.isNotEmpty ? autoStatus : null;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (onDisconnect != null || onForget != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  if (onDisconnect != null)
                    OutlinedButton.icon(
                      onPressed: onDisconnect,
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnect'),
                    ),
                  if (onForget != null)
                    TextButton.icon(
                      onPressed: onForget,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Forget gateway'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
