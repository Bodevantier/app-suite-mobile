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
                    final card = _SetupDeviceCard(
                      device: device,
                      isAdded: isAdded,
                      onAdd: () => widget.setupController.addDevice(device),
                      onRemove: isAdded
                          ? () => widget.setupController.removeDevice(device)
                          : null,
                      onTap: () => widget.onOpenDevice(device),
                    );
                    if (!isAdded) return card;
                    return Dismissible(
                      key: ValueKey(device.sourceAddress),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade400,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.delete_outline, color: Colors.white),
                      ),
                      onDismissed: (_) =>
                          widget.setupController.removeDevice(device),
                      child: card,
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

// ── Setup device card ────────────────────────────────────────────────────────

class _SetupDeviceCard extends StatelessWidget {
  const _SetupDeviceCard({
    required this.device,
    required this.isAdded,
    required this.onAdd,
    required this.onTap,
    this.onRemove,
  });

  final N2kDeviceInfo device;
  final bool isAdded;
  final VoidCallback onAdd;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final icon = _iconFor(device);
    final color = _colorFor(device, cs);

    // Temperature must be checked before wind.
    final pageLabel = device.isTemperatureDevice
        ? 'Temperature page'
        : device.isWindDevice
            ? 'Wind page'
            : device.isNavigationDevice
                ? 'Navigation page'
                : 'Details';

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
                      'src ${device.sourceAddress} · $pageLabel',
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
              // Add / Added button
              isAdded
                  ? Text(
                      'Added',
                      style: tt.labelMedium?.copyWith(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : FilledButton(
                      onPressed: onAdd,
                      child: const Text('Add'),
                    ),
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
