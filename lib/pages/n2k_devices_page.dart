import 'package:flutter/material.dart';
import 'dart:async';

import '../ble/controllers/ble_gateway_controller.dart';
import '../models/n2k_device_info.dart';
import 'n2k_device_detail_page.dart';

class N2kDevicesPage extends StatefulWidget {
  const N2kDevicesPage({
    super.key,
    required this.controller,
  });

  final BleGatewayController controller;

  @override
  State<N2kDevicesPage> createState() => _N2kDevicesPageState();
}

class _N2kDevicesPageState extends State<N2kDevicesPage> {
  static const Duration _initialRequestDelay = Duration(milliseconds: 500);
  static const Duration _minRequestSpacing = Duration(milliseconds: 700);

  Timer? _initialRequestTimer;
  bool _initialRequestSent = false;
  DateTime? _nextRequestAllowedAt;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleControllerChanged();
    });
  }

  Future<void> _refresh() async {
    _initialRequestSent = true;
    _cancelInitialRequest();

    final sent = await _requestDeviceListIfAllowed();
    if (sent) {
      await _waitForScanToFinish();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _cancelInitialRequest();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) return;

    if (!widget.controller.isConnected) {
      _cancelInitialRequest();
      _initialRequestSent = false;
      _nextRequestAllowedAt = null;
      return;
    }

    // Auto-trigger scan once when page opens, if not already scanning.
    if (!_initialRequestSent &&
        _initialRequestTimer == null &&
        !widget.controller.n2kScanInProgress) {
      _initialRequestTimer = Timer(_initialRequestDelay, () async {
        _initialRequestTimer = null;
        if (!mounted ||
            !widget.controller.isConnected ||
            widget.controller.n2kScanInProgress ||
            !_isRequestAllowedNow) {
          return;
        }
        _initialRequestSent = true;
        await _requestDeviceListIfAllowed();
      });
    }
  }

  bool get _isRequestAllowedNow {
    final nextAllowedAt = _nextRequestAllowedAt;
    if (nextAllowedAt == null) return true;
    return DateTime.now().toUtc().isAfter(nextAllowedAt);
  }

  Future<bool> _requestDeviceListIfAllowed() async {
    if (!widget.controller.isConnected ||
        widget.controller.n2kScanInProgress ||
        !_isRequestAllowedNow) {
      return false;
    }
    _nextRequestAllowedAt = DateTime.now().toUtc().add(_minRequestSpacing);
    try {
      await widget.controller.requestDeviceList();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _waitForScanToFinish() async {
    if (!widget.controller.n2kScanInProgress) return;
    final completer = Completer<void>();
    late final VoidCallback listener;
    listener = () {
      if (!mounted || !widget.controller.n2kScanInProgress) {
        if (!completer.isCompleted) completer.complete();
      }
    };
    widget.controller.addListener(listener);
    listener();
    try {
      await completer.future.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      // Hard cap in N2kDeviceTracker is 15s — 20s here is just a safety net.
    } finally {
      widget.controller.removeListener(listener);
    }
  }

  void _cancelInitialRequest() {
    _initialRequestTimer?.cancel();
    _initialRequestTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final devices = widget.controller.devices;
        final isLoading = widget.controller.n2kScanInProgress;

        return Scaffold(
          appBar: AppBar(title: const Text('N2K Devices')),
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (isLoading) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 16),
                if (devices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: isLoading
                          ? const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 12),
                                Text('Waiting for N2K devices...'),
                              ],
                            )
                          : const Text('No N2K devices found yet.\nPull down to scan again.'),
                    ),
                  )
                else
                  ...devices.map(
                    (device) => _N2kDeviceCard(
                      device: device,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => N2kDeviceDetailPage(
                              device: device,
                              controller: widget.controller,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Device card
// ---------------------------------------------------------------------------

class _N2kDeviceCard extends StatelessWidget {
  const _N2kDeviceCard({required this.device, required this.onTap});

  final N2kDeviceInfo device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final icon = _iconForDevice(device);
    final iconColor = _colorForDevice(device, cs);

    final subtitleParts = <String>[];
    if (device.displayManufacturer != 'Unknown manufacturer') {
      subtitleParts.add(device.displayManufacturer);
    }
    if (device.displayModel != 'Unknown model' && device.displayModel != '-') {
      subtitleParts.add(device.displayModel);
    }

    final categoryLabel = _categoryLabel(device);

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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Leading icon bubble
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 22),
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
                    if (subtitleParts.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitleParts.join(' · '),
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.65),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Category chip
                        _SmallChip(label: categoryLabel, color: iconColor),
                        const SizedBox(width: 6),
                        // Live-data badges — only shown when they add info
                        // beyond what the category chip already says.
                        if (device.hasLiveWindData &&
                            device.category != 'wind')
                          _SmallChip(
                            label: 'Wind',
                            color: Colors.blue.shade600,
                          ),
                        if (device.isTemperatureDevice &&
                            device.category != 'temperature')
                          _SmallChip(
                            label: 'Temp',
                            color: Colors.orange.shade700,
                          ),
                        if (device.isFluidLevelDevice &&
                            device.category != 'fluid')
                          _SmallChip(
                            label: 'Fluid',
                            color: Colors.blue.shade700,
                          ),
                        if (device.isNavigationDevice &&
                            device.category != 'navigation')
                          _SmallChip(
                            label: 'Nav',
                            color: Colors.green.shade700,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Trailing: online dot + src address
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: device.isOnline
                              ? Colors.green.shade500
                              : Colors.grey.shade400,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        device.isOnline ? 'Online' : 'Offline',
                        style: tt.labelSmall?.copyWith(
                          color: device.isOnline
                              ? Colors.green.shade700
                              : Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'src ${device.sourceAddress}',
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: cs.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconForDevice(N2kDeviceInfo d) {
    if (d.isBleGatewayDevice) return Icons.bluetooth;
    // Temperature takes priority over wind — a sensor can have both live flags
    // but show the more specific icon (e.g. SDolve Temperature).
    if (d.isTemperatureDevice) return Icons.thermostat;
    if (d.isFluidLevelDevice) return Icons.water_drop;
    if (d.isWindDevice) return Icons.air;
    if (d.isNavigationDevice) return Icons.satellite_alt;
    final fn = d.deviceFunction ?? 0;
    if (fn == 205) return Icons.satellite_alt; // chartplotter / GPS
    return Icons.sensors;
  }

  static Color _colorForDevice(N2kDeviceInfo d, ColorScheme cs) {
    if (d.isBleGatewayDevice) return cs.primary;
    if (d.isTemperatureDevice) return Colors.orange.shade700;
    if (d.isFluidLevelDevice) return Colors.blue.shade700;
    if (d.isWindDevice) return Colors.blue.shade600;
    if (d.isNavigationDevice) return Colors.green.shade700;
    return cs.secondary;
  }

  static String _categoryLabel(N2kDeviceInfo d) {
    if (d.isBleGatewayDevice) return 'Gateway';
    switch (d.category.toLowerCase()) {
      case 'wind':
        return 'Wind';
      case 'navigation':
        return 'Navigation';
      case 'temperature':
        return 'Temperature';
      case 'fluid':
        return 'Fluid level';
      default:
        final fn = d.deviceFunction;
        if (fn != null) return 'fn $fn';
        return d.displayCategory;
    }
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
