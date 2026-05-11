import 'dart:async';

import 'package:flutter/material.dart';

import '../ble/controllers/ble_gateway_controller.dart';
import '../ble/services/auto_connect_service.dart';
import '../services/app_preferences_service.dart';

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
        SnackBar(
          content: Text('Connection failed: $error'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
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
                tooltip:
                    controller.isScanning ? 'Stop scanning' : 'Scan for devices',
                icon: Icon(
                  controller.isScanning
                      ? Icons.stop_circle_outlined
                      : Icons.radar,
                ),
                onPressed: controller.isScanning
                    ? () => unawaited(controller.stopScan())
                    : () => unawaited(controller.startScan()),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              _StatusCard(
                isConnected: controller.isConnected,
                isConnecting: controller.isConnecting,
                isScanning: controller.isScanning,
                connectedName: controller.connectedDevice?.platformName,
                connectedId: connectedId,
                autoStatus: widget.autoConnectService.status,
                onDisconnect: controller.isConnected ? _disconnect : null,
                onForget: knownId != null ? _forgetGateway : null,
              ),
              const SizedBox(height: 28),
              _SectionHeader(
                isScanning: controller.isScanning,
                onScanToggle: controller.isScanning
                    ? () => unawaited(controller.stopScan())
                    : () => unawaited(controller.startScan()),
              ),
              const SizedBox(height: 10),
              if (discovered.isEmpty)
                _EmptyState(isScanning: controller.isScanning)
              else
                ...discovered.map((result) {
                  final id = result.device.remoteId.str;
                  final isThisConnected = connectedId == id;
                  final isKnown = knownId == id;
                  final name = result.device.platformName;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _GatewayCard(
                      name: name,
                      id: id,
                      rssi: result.rssi,
                      isConnected: isThisConnected,
                      isKnown: isKnown,
                      isConnecting: controller.isConnecting,
                      onConnect: () => unawaited(_connect(result)),
                      onDisconnect: _disconnect,
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

// ─── Status card ────────────────────────────────────────────────────────────

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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final IconData icon;
    final Color accentColor;
    final Color bgColor;
    final String title;
    final String detail;

    if (isConnected) {
      icon = Icons.bluetooth_connected_rounded;
      accentColor = Colors.green.shade600;
      bgColor = Colors.green.shade50;
      title = connectedName ?? '';
      detail = 'Connected';
    } else if (isConnecting) {
      icon = Icons.bluetooth_searching_rounded;
      accentColor = Colors.orange.shade700;
      bgColor = Colors.orange.shade50;
      title = 'Connecting…';
      detail = autoStatus.isNotEmpty ? autoStatus : 'Please wait';
    } else {
      icon = Icons.bluetooth_disabled_rounded;
      accentColor = colorScheme.onSurfaceVariant;
      bgColor = colorScheme.surfaceContainerHighest;
      title = 'Not Connected';
      detail = autoStatus.isNotEmpty
          ? autoStatus
          : 'Tap a device below to connect';
    }

    return Card(
      elevation: 0,
      color: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: accentColor, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        style: textTheme.bodySmall?.copyWith(
                          color: accentColor.withValues(alpha: 0.8),
                        ),
                      ),
                      if (connectedId != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          connectedId!,
                          style: textTheme.bodySmall?.copyWith(
                            color: accentColor.withValues(alpha: 0.55),
                            fontFamily: 'monospace',
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (onDisconnect != null || onForget != null) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  if (onDisconnect != null)
                    OutlinedButton.icon(
                      onPressed: onDisconnect,
                      icon: const Icon(Icons.link_off_rounded, size: 18),
                      label: const Text('Disconnect'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accentColor,
                        side: BorderSide(color: accentColor.withValues(alpha: 0.5)),
                      ),
                    ),
                  if (onForget != null)
                    TextButton.icon(
                      onPressed: onForget,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Forget'),
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.onSurfaceVariant,
                      ),
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

// ─── Section header ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.isScanning,
    required this.onScanToggle,
  });

  final bool isScanning;
  final VoidCallback onScanToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          'Nearby Bluetooth Devices',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(width: 8),
        if (isScanning) ...[
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Scanning…',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
        const Spacer(),
        TextButton.icon(
          onPressed: onScanToggle,
          icon: Icon(
            isScanning ? Icons.stop_rounded : Icons.refresh_rounded,
            size: 18,
          ),
          label: Text(isScanning ? 'Stop' : 'Rescan'),
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
        ),
      ],
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isScanning});

  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            isScanning ? Icons.radar : Icons.bluetooth_searching_rounded,
            size: 48,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            isScanning ? 'Scanning for Bluetooth devices…' : 'No devices found',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (!isScanning) ...[
            const SizedBox(height: 6),
            Text(
              'Tap Rescan to search again',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Gateway device card ─────────────────────────────────────────────────────

class _GatewayCard extends StatelessWidget {
  const _GatewayCard({
    required this.name,
    required this.id,
    required this.rssi,
    required this.isConnected,
    required this.isKnown,
    required this.isConnecting,
    required this.onConnect,
    required this.onDisconnect,
  });

  final String name;
  final String id;
  final int rssi;
  final bool isConnected;
  final bool isKnown;
  final bool isConnecting;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final Color iconColor =
        isConnected ? Colors.green.shade600 : colorScheme.primary;

    return Card(
      elevation: isConnected ? 1 : 0,
      color: isConnected
          ? Colors.green.shade50
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isConnected
            ? BorderSide(color: Colors.green.shade200, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isConnected
                    ? Icons.bluetooth_connected_rounded
                    : Icons.bluetooth_rounded,
                color: iconColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (isKnown) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Saved',
                            style: textTheme.labelSmall?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _RssiBars(rssi: rssi),
                      const SizedBox(width: 6),
                      Text(
                        '$rssi dBm  ·  $id',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isConnected)
              IconButton.outlined(
                onPressed: onDisconnect,
                tooltip: 'Disconnect',
                icon: const Icon(Icons.link_off_rounded),
                style: IconButton.styleFrom(
                  foregroundColor: Colors.green.shade700,
                  side: BorderSide(color: Colors.green.shade300),
                ),
              )
            else
              IconButton.filled(
                onPressed: isConnecting ? null : onConnect,
                tooltip: 'Connect',
                icon: const Icon(Icons.link_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── RSSI signal-strength bars ────────────────────────────────────────────────

class _RssiBars extends StatelessWidget {
  const _RssiBars({required this.rssi});

  final int rssi;

  /// Map rssi to 0–4 bars: ≥ -60 → 4, -70 → 3, -80 → 2, -90 → 1, else 0.
  int get _bars {
    if (rssi >= -60) return 4;
    if (rssi >= -70) return 3;
    if (rssi >= -80) return 2;
    if (rssi >= -90) return 1;
    return 0;
  }

  Color _barColor(BuildContext context) {
    if (_bars >= 3) return Colors.green.shade600;
    if (_bars == 2) return Colors.orange.shade600;
    return Colors.red.shade400;
  }

  @override
  Widget build(BuildContext context) {
    final active = _barColor(context);
    final inactive =
        Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.2);
    const totalBars = 4;
    const barWidth = 4.0;
    const barSpacing = 2.0;
    const maxHeight = 14.0;

    return SizedBox(
      width: totalBars * barWidth + (totalBars - 1) * barSpacing,
      height: maxHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.start,
        children: List.generate(totalBars, (i) {
          final height = maxHeight * (i + 1) / totalBars;
          return Padding(
            padding: EdgeInsets.only(
                right: i < totalBars - 1 ? barSpacing : 0),
            child: Container(
              width: barWidth,
              height: height,
              decoration: BoxDecoration(
                color: i < _bars ? active : inactive,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}
