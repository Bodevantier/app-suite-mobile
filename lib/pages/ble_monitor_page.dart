import 'dart:async';

import 'package:flutter/material.dart';

import '../ble/controllers/ble_gateway_controller.dart';

class BleMonitorPage extends StatefulWidget {
  const BleMonitorPage({
    super.key,
    required this.controller,
    this.autoStartScan = false,
    this.onConnectionReady,
  });

  final BleGatewayController controller;
  final bool autoStartScan;
  final Future<void> Function(BuildContext context)? onConnectionReady;

  @override
  State<BleMonitorPage> createState() => _BleMonitorPageState();
}

class _BleMonitorPageState extends State<BleMonitorPage> {
  bool _didForwardAfterConnect = false;
  bool _wasConnectedOnEntry = false;

  @override
  void initState() {
    super.initState();
    // Record whether we were already connected when this page was pushed.
    // onConnectionReady should only fire for connections made AFTER opening.
    _wasConnectedOnEntry = widget.controller.connectedDevice != null;
    unawaited(_initializeBle());
  }

  Future<void> _initializeBle() async {
    await widget.controller.initialize();
    if (widget.autoStartScan &&
        !widget.controller.isScanning &&
        widget.controller.connectedDevice == null) {
      await widget.controller.startScan();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        if (!_didForwardAfterConnect &&
            !_wasConnectedOnEntry &&
            widget.controller.connectedDevice != null &&
            widget.onConnectionReady != null) {
          _didForwardAfterConnect = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            unawaited(widget.onConnectionReady!(context));
          });
        }

        final connectedAddress =
            widget.controller.connectedDevice?.remoteId.str;
        final discoveredDevices = widget.controller.discoveredDevices;

        return Scaffold(
          appBar: AppBar(title: const Text('BLE Gateway Monitor')),
          body: LayoutBuilder(
            builder: (context, constraints) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(widget.controller.bleStatus),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: widget.controller.isScanning
                            ? null
                            : () => unawaited(widget.controller.startScan()),
                        child: const Text('Start scan'),
                      ),
                      OutlinedButton(
                        onPressed: widget.controller.isScanning
                            ? () => unawaited(widget.controller.stopScan())
                            : null,
                        child: const Text('Stop scan'),
                      ),
                      if (widget.controller.connectedDevice != null)
                        OutlinedButton(
                          onPressed: () =>
                              unawaited(widget.controller.disconnect()),
                          child: const Text('Disconnect'),
                        ),
                      FilledButton(
                        onPressed: widget.controller.connectedDevice == null
                            ? null
                            : () => unawaited(
                                widget.controller.requestDeviceList(),
                              ),
                        child: const Text('Request device list'),
                      ),
                      TextButton(
                        onPressed: () => unawaited(
                          widget.controller.loadMockDeviceListFixture(),
                        ),
                        child: const Text('Load mock fixture'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Discovered devices (${discoveredDevices.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (discoveredDevices.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No BLE devices discovered yet.'),
                      ),
                    )
                  else
                    ...discoveredDevices.map((result) {
                      final isConnected =
                          connectedAddress == result.device.remoteId.str;
                      return Card(
                        child: ListTile(
                          title: Text(
                            _deviceTitle(
                              result.device.platformName,
                              result.device.remoteId.str,
                            ),
                          ),
                          subtitle: Text(
                            '${result.device.remoteId.str} | RSSI ${result.rssi}',
                          ),
                          trailing: isConnected
                              ? const Text('Connected')
                              : ElevatedButton(
                                  onPressed: widget.controller.isConnecting
                                      ? null
                                      : () => unawaited(
                                          widget.controller.connect(result),
                                        ),
                                  child: const Text('Connect'),
                                ),
                        ),
                      );
                    }),
                ],
              );
            },
          ),
        );
      },
    );
  }

  String _deviceTitle(String? name, String fallback) {
    if (name == null || name.isEmpty) {
      return fallback;
    }
    return name;
  }
}
