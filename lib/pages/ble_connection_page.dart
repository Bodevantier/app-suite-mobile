import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/controllers/ble_gateway_controller.dart';
import '../ble/services/auto_connect_service.dart';
import '../ble/services/ble_background_service.dart';
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
  // Null while loading. False shows the "enable reliable background
  // reconnect" card below the status card — see _BatteryOptimizationCard.
  bool? _ignoringBatteryOptimizations;

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
    unawaited(_refreshBatteryOptimizationStatus());
  }

  Future<void> _refreshBatteryOptimizationStatus() async {
    final ignoring = await BleBackgroundService.isIgnoringBatteryOptimizations();
    if (mounted) setState(() => _ignoringBatteryOptimizations = ignoring);
  }

  Future<void> _requestBackgroundReliability() async {
    await BleBackgroundService.requestIgnoreBatteryOptimizations();
    // The system dialog is a separate Activity — re-check once we're back
    // in the foreground rather than guessing the outcome.
    if (mounted) unawaited(_refreshBatteryOptimizationStatus());
  }

  void _showDeviceSheet(ScanResult result) {
    final ad = result.advertisementData;
    final name = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : (ad.advName.isNotEmpty ? ad.advName : 'Unknown Device');
    final id = result.device.remoteId.str;
    final isThisConnected = widget.controller.connectedDevice?.remoteId.str == id;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _DeviceInfoSheet(
        name: name,
        id: id,
        rssi: result.rssi,
        txPower: ad.txPowerLevel,
        connectable: ad.connectable,
        serviceUuids: ad.serviceUuids.map((g) => g.str128).toList(),
        manufacturerData: ad.manufacturerData,
        isConnected: isThisConnected,
      ),
    );
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

  /// Used for both "Disconnect" (while connected) and "Cancel" (while
  /// connecting). Pausing auto-connect FIRST is what makes this stick —
  /// otherwise the transport's own disconnect notification would trigger
  /// AutoConnectService to immediately try reconnecting again.
  Future<void> _disconnectOrCancel() async {
    widget.autoConnectService.pause();
    await widget.controller.disconnect();
  }

  /// Manually reconnects to the known gateway without requiring it to
  /// already be sitting in the current scan results — mirrors how a normal
  /// Bluetooth settings screen lets you reconnect a known/paired device
  /// directly instead of making you re-discover it.
  void _reconnectKnown() {
    final knownId = widget.preferences.knownGatewayId;
    if (knownId == null) return;
    if (widget.autoConnectService.isRunning) {
      widget.autoConnectService.retryNow();
    } else {
      widget.autoConnectService.start(knownId);
    }
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
        // AutoConnectService can be mid-attempt (adapter wait, scan) before
        // the transport itself reports isConnecting — match the home page's
        // definition so the Connecting/Cancel UI shows for the whole window.
        final isConnecting = controller.isConnecting ||
            (widget.autoConnectService.isRunning &&
                !controller.isConnected &&
                widget.autoConnectService.status.isNotEmpty);

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
                isConnecting: isConnecting,
                isScanning: controller.isScanning,
                connectedName: controller.connectedDevice?.platformName,
                connectedId: connectedId,
                hasKnownGateway: knownId != null,
                autoStatus: widget.autoConnectService.status,
                onDisconnect:
                    controller.isConnected ? _disconnectOrCancel : null,
                onCancel: (!controller.isConnected && isConnecting)
                    ? _disconnectOrCancel
                    : null,
                onConnect: (!controller.isConnected &&
                        !isConnecting &&
                        knownId != null)
                    ? _reconnectKnown
                    : null,
                onForget: knownId != null ? _forgetGateway : null,
              ),
              if (knownId != null && _ignoringBatteryOptimizations == false) ...[
                const SizedBox(height: 12),
                _BatteryOptimizationCard(onEnable: _requestBackgroundReliability),
              ],
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
                      onDisconnect: _disconnectOrCancel,
                      onTap: () => _showDeviceSheet(result),
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
    required this.hasKnownGateway,
    required this.autoStatus,
    required this.onDisconnect,
    required this.onCancel,
    required this.onConnect,
    required this.onForget,
  });

  final bool isConnected;
  final bool isConnecting;
  final bool isScanning;
  final String? connectedName;
  final String? connectedId;
  final bool hasKnownGateway;
  final String autoStatus;
  final VoidCallback? onDisconnect;
  final VoidCallback? onCancel;
  final VoidCallback? onConnect;
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
          : hasKnownGateway
              ? 'Tap Connect to reconnect'
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
            if (onDisconnect != null ||
                onCancel != null ||
                onConnect != null ||
                onForget != null) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  if (onConnect != null)
                    FilledButton.icon(
                      onPressed: onConnect,
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: const Text('Connect'),
                    ),
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
                  if (onCancel != null)
                    OutlinedButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Cancel'),
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

// ─── Background reliability prompt ──────────────────────────────────────────

/// Shown when the gateway is known but Android hasn't granted the battery-
/// optimization exemption — without it, the app can't reliably reconnect in
/// the background when fully closed (it can only show a plain "tap to open"
/// notification instead of actually connecting). Purely informational/opt-in
/// — the app works fine without this, just less automatically.
class _BatteryOptimizationCard extends StatelessWidget {
  const _BatteryOptimizationCard({required this.onEnable});

  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.battery_alert_outlined,
                color: colorScheme.onSurfaceVariant, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reconnect automatically when closed',
                    style: textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Allow SDolve to run in the background so it connects to '
                    'the gateway on its own, even after fully closing the app.',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: onEnable,
                    child: const Text('Enable'),
                  ),
                ],
              ),
            ),
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
        Flexible(
          child: Text(
            'Nearby Devices',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurfaceVariant,
                  letterSpacing: 0.5,
                ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
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
          Flexible(
            child: Text(
              'Scanning…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                    fontStyle: FontStyle.italic,
                  ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
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
    this.onTap,
  });

  final String name;
  final String id;
  final int rssi;
  final bool isConnected;
  final bool isKnown;
  final bool isConnecting;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final Color iconColor =
        isConnected ? Colors.green.shade600 : colorScheme.primary;

    return Card(
      elevation: isConnected ? 1 : 0,
      clipBehavior: Clip.antiAlias,
      color: isConnected
          ? Colors.green.shade50
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isConnected
            ? BorderSide(color: Colors.green.shade200, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
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
                      Expanded(
                        child: Text(
                          '$rssi dBm  ·  $id',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
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
      ),
    );
  }
}

// ─── Device info bottom sheet ────────────────────────────────────────────────

class _DeviceInfoSheet extends StatelessWidget {
  const _DeviceInfoSheet({
    required this.name,
    required this.id,
    required this.rssi,
    required this.txPower,
    required this.connectable,
    required this.serviceUuids,
    required this.manufacturerData,
    required this.isConnected,
  });

  final String name;
  final String id;
  final int rssi;
  final int? txPower;
  final bool connectable;
  final List<String> serviceUuids;
  final Map<int, List<int>> manufacturerData;
  final bool isConnected;

  String _signalLabel() {
    if (rssi >= -60) return 'Excellent';
    if (rssi >= -70) return 'Good';
    if (rssi >= -80) return 'Fair';
    if (rssi >= -90) return 'Weak';
    return 'Poor';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final iconColor = isConnected ? Colors.green.shade600 : colorScheme.primary;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          // Icon + name
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isConnected
                  ? Icons.bluetooth_connected_rounded
                  : Icons.bluetooth_rounded,
              color: iconColor,
              size: 28,
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              name,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ),
          if (isConnected) ...[            
            const SizedBox(height: 4),
            Text(
              'Connected',
              style: textTheme.bodySmall?.copyWith(
                color: Colors.green.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Divider(height: 1, indent: 24, endIndent: 24),
          const SizedBox(height: 8),
          // Info rows
          _InfoRow(label: 'MAC Address', value: id, monospace: true),
          _InfoRow(
            label: 'Signal',
            value: '${_signalLabel()}  ·  $rssi dBm',
            trailing: _RssiBars(rssi: rssi),
          ),
          if (txPower != null)
            _InfoRow(label: 'TX Power', value: '$txPower dBm'),
          _InfoRow(label: 'Connectable', value: connectable ? 'Yes' : 'No'),
          if (serviceUuids.isNotEmpty)
            _InfoRow(
              label: 'Service UUID',
              value: serviceUuids.first,
              monospace: true,
            ),
          if (manufacturerData.isNotEmpty)
            _InfoRow(
              label: 'Manufacturer',
              value: manufacturerData.keys
                  .map((k) => '0x${k.toRadixString(16).toUpperCase().padLeft(4, "0")}')
                  .join(', '),
              monospace: true,
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.monospace = false,
    this.trailing,
  });

  final String label;
  final String value;
  final bool monospace;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null) ...[            
            trailing!,
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              value,
              style: textTheme.bodyMedium?.copyWith(
                fontFamily: monospace ? 'monospace' : null,
                fontSize: monospace ? 12 : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
