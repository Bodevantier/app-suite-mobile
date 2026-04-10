import 'package:flutter/material.dart';

import '../ble/controllers/ble_gateway_controller.dart';
import '../controllers/app_setup_controller.dart';
import '../models/n2k_device_info.dart';

class DeviceSetupPage extends StatefulWidget {
  const DeviceSetupPage({
    super.key,
    required this.controller,
    required this.setupController,
    required this.onOpenDevice,
    required this.onFinishSetup,
  });

  final BleGatewayController controller;
  final AppSetupController setupController;
  final Future<void> Function(N2kDeviceInfo device) onOpenDevice;
  final VoidCallback onFinishSetup;

  @override
  State<DeviceSetupPage> createState() => _DeviceSetupPageState();
}

class _DeviceSetupPageState extends State<DeviceSetupPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.controller.isConnected) {
        await _refresh();
      }
    });
  }

  String _loadingMessage(BleGatewayController c) {
    final expected = c.progressExpected;
    final received = c.progressReceived ?? 0;
    if (expected == null) {
      return 'Waiting for N2K device list...';
    }
    if (received < expected) {
      return 'Discovering devices ($received/$expected)...';
    }
    // All addresses found — gateway is now querying device details over N2K
    return 'Querying device details ($expected found)...';
  }

  Future<void> _refresh() async {
    if (!widget.controller.isConnected) {
      return;
    }
    try {
      await widget.controller.requestDeviceList();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, widget.setupController]),
      builder: (context, _) {
        final devices = filterSetupVisibleDevices(widget.controller.devices);
        final addedDevices = widget.setupController.addedDevices;
        final isLoading = widget.controller.snapshotInProgress;

        return Scaffold(
          appBar: AppBar(title: const Text('Choose Devices')),
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(widget.controller.statusLine),
                const SizedBox(height: 12),
                const Text('Add the devices you want on your home page.'),
                const SizedBox(height: 8),
                Text('Added devices: ${addedDevices.length}'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton(
                      onPressed: isLoading || !widget.controller.isConnected
                          ? null
                          : () => _refresh(),
                      child: const Text('Refresh devices'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: addedDevices.isEmpty
                            ? null
                            : widget.onFinishSetup,
                        child: const Text('Finish setup'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 16),
                if (isLoading)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(_loadingMessage(widget.controller)),
                        ],
                      ),
                    ),
                  )
                else if (devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: Text('No N2K devices reported yet.')),
                  )
                else
                  ...devices.map((device) {
                    final isAdded = widget.setupController.isAdded(device);

                    return Card(
                      child: ListTile(
                        title: Text(device.displayName),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Source ${device.sourceAddress}'),
                            Text(
                              '${device.displayCategory} • ${device.displayModel}',
                            ),
                            if (device.isWindDevice) const Text('Wind page'),
                          ],
                        ),
                        trailing: isAdded
                            ? Text(
                                'Added',
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : FilledButton(
                                onPressed: () {
                                  widget.setupController.addDevice(device);
                                },
                                child: const Text('Add'),
                              ),
                        onTap: () => widget.onOpenDevice(device),
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }
}
