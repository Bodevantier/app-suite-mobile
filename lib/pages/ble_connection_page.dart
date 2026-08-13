import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/controllers/ble_gateway_controller.dart';
import '../ble/services/auto_connect_service.dart';
import '../ble/services/ble_background_service.dart';
import '../services/app_preferences_service.dart';

/// Friendly name for the connected gateway. While connected we already know
/// exactly which physical device this is — the question is only whether we
/// have a human-friendly label for it yet, never whether the device itself
/// is "unknown". Priority: [confirmedName] (read directly off the connected
/// peripheral's own GAP Device Name characteristic — the ground truth, not
/// dependent on OS caching), then `platformName` (often empty right after a
/// direct-by-id reconnect, since Android hasn't cached it), then the
/// advertised name seen during the current scan, then the name saved the
/// last time we actually saw one (auto-reconnect skips scanning entirely,
/// so there may be no live scan result at all). If truly none of those are
/// available, fall back to the device's own address rather than a vague
/// placeholder — that's still an honest, specific answer to "which device".
String? _resolveConnectedDeviceName(
  BluetoothDevice? device,
  List<ScanResult> discovered,
  String? savedName,
  String? confirmedName,
) {
  if (device == null) return null;
  if (confirmedName != null && confirmedName.isNotEmpty) return confirmedName;
  final platformName = device.platformName;
  if (platformName.isNotEmpty) return platformName;
  for (final result in discovered) {
    if (result.device.remoteId != device.remoteId) continue;
    final advName = result.advertisementData.advName;
    if (advName.isNotEmpty) return advName;
    break;
  }
  if (savedName != null && savedName.isNotEmpty) return savedName;
  return device.remoteId.str;
}

/// Friendly name for a scan result — `platformName` is frequently empty
/// right when a device is first seen (the OS hasn't cached it yet), so fall
/// back to the name it's actively advertising.
String _scanResultName(ScanResult result) {
  final platformName = result.device.platformName;
  if (platformName.isNotEmpty) return platformName;
  final advName = result.advertisementData.advName;
  if (advName.isNotEmpty) return advName;
  return 'Unknown Device';
}

/// Qualitative signal strength — easier for a normal user to read than a
/// raw dBm number.
String _rssiSignalLabel(int rssi) {
  if (rssi >= -60) return 'Excellent';
  if (rssi >= -70) return 'Good';
  if (rssi >= -80) return 'Fair';
  if (rssi >= -90) return 'Weak';
  return 'Poor';
}

class BleConnectionPage extends StatefulWidget {
  const BleConnectionPage({
    super.key,
    required this.controller,
    required this.autoConnectService,
    required this.preferences,
    this.onConnectionReady,
    this.demoModeActive = false,
  });

  final BleGatewayController controller;
  final AutoConnectService autoConnectService;
  final AppPreferencesService preferences;
  // Fired once when a connection is established after this page was opened
  // (not for a connection that already existed on entry) — used by the
  // first-time setup flow to advance past pairing automatically.
  final Future<void> Function(BuildContext context)? onConnectionReady;
  // While Demo Mode is simulating a connection, real scanning/connecting
  // would race the simulated data — this page shows an explainer instead.
  final bool demoModeActive;

  @override
  State<BleConnectionPage> createState() => _BleConnectionPageState();
}

class _BleConnectionPageState extends State<BleConnectionPage> {
  // Null while loading. False shows the "enable reliable background
  // reconnect" card below the status card — see _BatteryOptimizationCard.
  bool? _ignoringBatteryOptimizations;
  bool _didForwardAfterConnect = false;
  late final bool _wasConnectedOnEntry;

  @override
  void initState() {
    super.initState();
    _wasConnectedOnEntry = widget.controller.isConnected;
    if (widget.demoModeActive) return;
    // Continuously enforce "should be scanning" any time connection state
    // changes while this page is open — not just at mount — so a manual
    // Disconnect (or a dropped connection, or Forget) always brings the
    // device list back to life instead of leaving it stale/empty.
    widget.controller.addListener(_syncScanState);
    widget.autoConnectService.addListener(_syncScanState);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.controller.initialize();
      _syncScanState();
    });
    unawaited(_refreshBatteryOptimizationStatus());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncScanState);
    widget.autoConnectService.removeListener(_syncScanState);
    // Standard BLE practice (see Android's own BLE guide): don't leave a
    // scan running once the user isn't looking at the discovery UI anymore
    // — it keeps the radio hot for no benefit. Skip it while a connect
    // attempt is actually in flight, including AutoConnectService's own
    // brief scan-fallback window, so navigating away doesn't cut that off.
    if (widget.controller.isScanning && !_isConnectingNow) {
      unawaited(widget.controller.stopScan());
    }
    super.dispose();
  }

  // Reentrancy guard for _syncScanState — see its doc comment. Crash-tested
  // fix: without this, this method caused an infinite synchronous recursion
  // and a real stack-overflow crash on device.
  bool _syncingScanState = false;

  // Debounce for retrying a *failed* startScan() — see doc comment below.
  // Crash-tested fix #2: without this, a rejected scan registration (Android
  // throttles BluetoothLeScanner.startScan to ~5 calls per 30s) caused an
  // unbounded async retry storm — each failure's own status notification
  // immediately triggered another attempt, so it never backed off long
  // enough for Android's throttle window to clear.
  DateTime? _lastScanAttemptAt;
  static const _minScanRetryInterval = Duration(seconds: 8);

  /// Single source of truth for "should the radio be scanning right now" —
  /// re-evaluated on every connection-state change (disconnect, forget, a
  /// dropped connection, a completed reconnect), not just at page-mount.
  ///
  /// Two failure modes had to be guarded against here, both found by
  /// actually running this on a phone rather than trusting static analysis:
  ///
  /// 1. Reentrancy: `BleGatewayTransportService.startScan()` calls
  ///    `notifyListeners()` (status = 'Scanning...') *before* the native
  ///    scan actually starts — `isScanning` (`FlutterBluePlus.isScanningNow`)
  ///    is still `false` at that instant. That notification bubbles straight
  ///    up through `BleGatewayController._handleDependencyChanged` (which
  ///    unconditionally re-notifies) to this same listener, which would see
  ///    `isScanning == false` again and call `startScan()` again —
  ///    synchronously, before the first call ever returns — recursing until
  ///    the stack overflows. `_syncingScanState` makes every nested call
  ///    during that synchronous notification burst a no-op.
  /// 2. Retry storm: even with (1) fixed, a *failed* scan registration
  ///    (e.g. Android's own throttling) also calls `notifyListeners()` on
  ///    the way out of the catch block, in a later, separate (non-nested)
  ///    call — the reentrancy guard doesn't cover that. Left unthrottled,
  ///    each failure immediately triggered another attempt, in a tight async
  ///    loop that kept re-tripping Android's throttle. `_lastScanAttemptAt`
  ///    caps retries to once per [_minScanRetryInterval].
  void _syncScanState() {
    if (!mounted || _syncingScanState) return;
    _syncingScanState = true;
    try {
      final shouldScan = !widget.controller.isConnected;
      if (shouldScan && !widget.controller.isScanning) {
        final lastAttempt = _lastScanAttemptAt;
        final now = DateTime.now();
        if (lastAttempt == null || now.difference(lastAttempt) >= _minScanRetryInterval) {
          _lastScanAttemptAt = now;
          unawaited(widget.controller.startScan());
        }
      } else if (!shouldScan && widget.controller.isScanning) {
        unawaited(widget.controller.stopScan());
      }
    } finally {
      _syncingScanState = false;
    }
  }

  /// Mirrors the "Connecting…" condition used in [build] — AutoConnectService
  /// can be mid-attempt (adapter wait, its own scan-fallback) before the
  /// transport itself reports isConnecting.
  bool get _isConnectingNow =>
      widget.controller.isConnecting ||
      (widget.autoConnectService.isRunning &&
          !widget.controller.isConnected &&
          widget.autoConnectService.status.isNotEmpty);

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

  /// Long-press action sheet for one specific device row — makes Forget
  /// unambiguous by tying it to the device the user is actually holding,
  /// instead of a single top-of-page button whose target isn't obvious when
  /// a gateway is already connected. [liveResult] is only available when
  /// this device currently has a fresh scan result behind it; the saved
  /// gateway's pinned row can be long-pressed even before/without one, in
  /// which case Connect falls back to the direct-by-id reconnect path.
  void _showDeviceActions({
    required String name,
    required String id,
    required bool isKnown,
    ScanResult? liveResult,
  }) {
    final isThisConnected = widget.controller.connectedDevice?.remoteId.str == id;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _DeviceActionsSheet(
        name: name,
        isConnected: isThisConnected,
        isConnecting: widget.controller.isConnecting,
        isKnown: isKnown,
        onConnect: () {
          Navigator.of(sheetContext).pop();
          if (liveResult != null) {
            unawaited(_connect(liveResult));
          } else {
            _reconnectKnown();
          }
        },
        onDisconnect: () {
          Navigator.of(sheetContext).pop();
          unawaited(_disconnectOrCancel());
        },
        onForget: () async {
          Navigator.of(sheetContext).pop();
          final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogCtx) => AlertDialog(
                  title: const Text('Forget this gateway?'),
                  content: Text(
                    "$name will be forgotten. You'll need to pick it from "
                    'Nearby Devices again to reconnect.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogCtx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => Navigator.of(dialogCtx).pop(true),
                      child: const Text('Forget'),
                    ),
                  ],
                ),
              ) ??
              false;
          if (confirmed) unawaited(_forgetGateway());
        },
      ),
    );
  }

  void _showDeviceSheet(ScanResult result) {
    final ad = result.advertisementData;
    final name = _scanResultName(result);
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

  Future<void> _connect(ScanResult scanResult) async {
    try {
      await widget.controller.connect(scanResult);
      final id = widget.controller.connectedDevice?.remoteId.str;
      if (id != null) {
        unawaited(widget.preferences.saveKnownGatewayId(id));
        // Remember whichever name we actually saw advertised, so a future
        // direct reconnect (no scan step) can still show a real name.
        final name = _scanResultName(scanResult);
        if (name != 'Unknown Device') {
          unawaited(widget.preferences.saveKnownGatewayName(name));
        }
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
    await widget.preferences.saveKnownGatewayName(null);
    // disconnect() firing notifyListeners() is what makes _syncScanState
    // (attached in initState) bring scanning back — no need to force it here.
    await widget.controller.disconnect();
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.demoModeActive) {
      return const _DemoModeExplainer();
    }
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
        final connectedName = _resolveConnectedDeviceName(
          controller.connectedDevice,
          discovered,
          widget.preferences.knownGatewayName,
          controller.connectedDeviceName,
        );
        final isConnecting = _isConnectingNow;

        if (!_didForwardAfterConnect &&
            !_wasConnectedOnEntry &&
            controller.isConnected &&
            widget.onConnectionReady != null) {
          _didForwardAfterConnect = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            unawaited(widget.onConnectionReady!(context));
          });
        }

        // The saved gateway is always shown as the first row — live scan
        // data when we have it, a synthesized entry (no RSSI yet) otherwise
        // — so there is never a Connect/Disconnect/Forget action whose
        // target isn't visible on screen.
        ScanResult? knownResult;
        if (knownId != null) {
          for (final result in discovered) {
            if (result.device.remoteId.str == knownId) {
              knownResult = result;
              break;
            }
          }
        }
        final others =
            discovered.where((r) => r.device.remoteId.str != knownId).toList();
        final showOthersSection = others.isNotEmpty || controller.isScanning;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Bluetooth'),
            actions: [
              IconButton(
                tooltip: 'Scan for devices',
                icon: const Icon(Icons.radar),
                onPressed: () => unawaited(controller.startScan()),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              // One card per gateway concept — not two. Before a gateway is
              // ever saved, a plain status readout is all there is to show.
              // Once one is saved, it *is* the status (name, connection
              // state, signal) plus the connect/disconnect/forget actions,
              // instead of a redundant summary banner floating above a
              // second card that repeats the same device's name.
              if (knownId == null)
                _StatusCard(
                  isConnected: controller.isConnected,
                  isConnecting: isConnecting,
                  connectedName: connectedName,
                  hasKnownGateway: false,
                  autoStatus: widget.autoConnectService.status,
                )
              else
                Builder(builder: (context) {
                  final result = knownResult;
                  final pinnedName = result != null
                      ? _scanResultName(result)
                      : (widget.preferences.knownGatewayName ?? knownId);
                  return _KnownGatewayCard(
                    name: pinnedName,
                    rssi: result?.rssi,
                    isConnected: connectedId == knownId,
                    isConnecting: isConnecting,
                    autoStatus: widget.autoConnectService.status,
                    onConnect: result != null
                        ? () => unawaited(_connect(result))
                        : _reconnectKnown,
                    onDisconnect: _disconnectOrCancel,
                    onTap: result != null ? () => _showDeviceSheet(result) : null,
                    onLongPress: () => _showDeviceActions(
                      name: pinnedName,
                      id: knownId,
                      isKnown: true,
                      liveResult: result,
                    ),
                  );
                }),
              if (knownId != null && _ignoringBatteryOptimizations == false) ...[
                const SizedBox(height: 12),
                _BatteryOptimizationCard(onEnable: _requestBackgroundReliability),
              ],
              const SizedBox(height: 24),
              if (knownId == null && others.isEmpty)
                _EmptyState(isScanning: controller.isScanning)
              else if (showOthersSection) ...[
                _SectionHeader(
                  title: knownId == null ? 'Nearby Devices' : 'Other Nearby Devices',
                  isScanning: controller.isScanning,
                  onRescan: () => unawaited(controller.startScan()),
                ),
                const SizedBox(height: 10),
                ...others.map((result) {
                  final id = result.device.remoteId.str;
                  final name = _scanResultName(result);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _GatewayCard(
                      name: name,
                      id: id,
                      rssi: result.rssi,
                      isConnected: connectedId == id,
                      isKnown: false,
                      isConnecting: false,
                      onConnect: () => unawaited(_connect(result)),
                      onDisconnect: _disconnectOrCancel,
                      onTap: () => _showDeviceSheet(result),
                      onLongPress: () => _showDeviceActions(
                        name: name,
                        id: id,
                        isKnown: false,
                        liveResult: result,
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─── Demo mode explainer ──────────────────────────────────────────────────────

/// Shown instead of the real scan/connect UI while Demo Mode is active —
/// scanning or connecting for real would just race the simulated data.
class _DemoModeExplainer extends StatelessWidget {
  const _DemoModeExplainer();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Bluetooth')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.theater_comedy_outlined, size: 48, color: cs.primary),
              const SizedBox(height: 16),
              const Text(
                'Demo Mode is active',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Bluetooth scanning is disabled while showing simulated data. '
                'Turn off Demo Mode from the About page to connect to a real gateway.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Status card ────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.isConnected,
    required this.isConnecting,
    required this.connectedName,
    required this.hasKnownGateway,
    required this.autoStatus,
  });

  final bool isConnected;
  final bool isConnecting;
  final String? connectedName;
  final bool hasKnownGateway;
  final String autoStatus;

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
      // connectedName is only null when there's no connected device at all,
      // which can't happen while isConnected is true — this is unreachable
      // in practice, just satisfying the nullable type.
      title = connectedName ?? 'Connected Device';
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
              ? 'Tap your saved gateway below to reconnect'
              : 'Tap a device below to connect';
    }

    // Pure status readout — no buttons. Connect/Disconnect/Forget all live
    // on the relevant device row below, so there is never an action here
    // whose target device is ambiguous.
    return Card(
      elevation: 0,
      color: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Known gateway card ───────────────────────────────────────────────────────

/// The single card for the saved gateway — status readout AND the device
/// row in one, since there's only ever one gateway and a separate summary
/// banner above it just repeated the same name with inconsistent wording
/// (e.g. "Connected" up top but a bare signal reading below, with no
/// indication they're the same device's two halves).
class _KnownGatewayCard extends StatelessWidget {
  const _KnownGatewayCard({
    required this.name,
    required this.rssi,
    required this.isConnected,
    required this.isConnecting,
    required this.autoStatus,
    required this.onConnect,
    required this.onDisconnect,
    required this.onLongPress,
    this.onTap,
  });

  final String name;
  // Null when we don't have a live scan result behind this device (e.g.
  // already connected, so it won't show up as a fresh scan result — or
  // simply not currently in range).
  final int? rssi;
  final bool isConnected;
  final bool isConnecting;
  final String autoStatus;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onLongPress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final IconData icon;
    final Color accentColor;
    final Color bgColor;
    final Color? borderColor;
    final String detail;

    if (isConnected) {
      icon = Icons.bluetooth_connected_rounded;
      accentColor = Colors.green.shade600;
      bgColor = Colors.green.shade50;
      borderColor = Colors.green.shade200;
      detail = rssi != null
          ? 'Connected  ·  ${_rssiSignalLabel(rssi!)} signal'
          : 'Connected';
    } else if (isConnecting) {
      icon = Icons.bluetooth_searching_rounded;
      accentColor = Colors.orange.shade700;
      bgColor = Colors.orange.shade50;
      borderColor = Colors.orange.shade200;
      detail = autoStatus.isNotEmpty ? autoStatus : 'Connecting…';
    } else {
      icon = Icons.bluetooth_disabled_rounded;
      accentColor = colorScheme.onSurfaceVariant;
      bgColor = colorScheme.surfaceContainerHighest;
      borderColor = null;
      detail = rssi != null
          ? '${_rssiSignalLabel(rssi!)} signal — tap to reconnect'
          : 'Not currently in range — tap to reconnect';
    }

    return Card(
      elevation: isConnected ? 1 : 0,
      clipBehavior: Clip.antiAlias,
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: borderColor != null
            ? BorderSide(color: borderColor, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
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
                    // Name gets the full width to itself — putting the
                    // "Saved" badge on this line at titleMedium size was
                    // truncating ordinary-length names (e.g. "SDolve
                    // Bluetooth" → "SDolve Blue…").
                    Text(
                      name,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
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
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            detail,
                            style: textTheme.bodySmall?.copyWith(
                              color: accentColor.withValues(alpha: 0.8),
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
              else if (isConnecting)
                // Tappable to cancel — _disconnectOrCancel handles both.
                InkResponse(
                  onTap: onDisconnect,
                  radius: 22,
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  ),
                )
              else
                IconButton.filled(
                  onPressed: onConnect,
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
    required this.title,
    required this.isScanning,
    required this.onRescan,
  });

  final String title;
  final bool isScanning;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Flexible(
          child: Text(
            title,
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
        // No manual "Stop" — scanning while this page is open and not
        // connected is a standing invariant (_syncScanState), not something
        // a user toggle should fight. Rescan just forces a fresh burst.
        TextButton.icon(
          onPressed: onRescan,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Rescan'),
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
    this.onLongPress,
  });

  final String name;
  final String id;
  // Null when this row is the saved gateway shown before/without a live
  // scan result behind it (e.g. already connected, so it won't show up as
  // a fresh scan result — or simply not currently in range).
  final int? rssi;
  final bool isConnected;
  final bool isKnown;
  final bool isConnecting;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

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
        onLongPress: onLongPress,
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
                  if (rssi != null)
                    Row(
                      children: [
                        _RssiBars(rssi: rssi!),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _rssiSignalLabel(rssi!),
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      isConnected ? 'Connected' : 'Not currently in range',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
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
            else if (isConnecting)
              // Tappable to cancel — _disconnectOrCancel handles both.
              InkResponse(
                onTap: onDisconnect,
                radius: 22,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ),
              )
            else
              IconButton.filled(
                onPressed: onConnect,
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

// ─── Device actions bottom sheet (long-press) ────────────────────────────────

/// Opened by long-pressing a device row in Nearby Devices — a focused
/// "manage this device" sheet (connect/disconnect + forget), as opposed to
/// [_DeviceInfoSheet]'s read-only technical details reached by a plain tap.
class _DeviceActionsSheet extends StatelessWidget {
  const _DeviceActionsSheet({
    required this.name,
    required this.isConnected,
    required this.isConnecting,
    required this.isKnown,
    required this.onConnect,
    required this.onDisconnect,
    required this.onForget,
  });

  final String name;
  final bool isConnected;
  final bool isConnecting;
  final bool isKnown;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final iconColor = isConnected ? Colors.green.shade600 : colorScheme.primary;

    return SafeArea(
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
          const SizedBox(height: 4),
          Text(
            isConnected
                ? 'Connected'
                : isKnown
                    ? 'Saved gateway'
                    : 'Not connected',
            style: textTheme.bodySmall?.copyWith(
              color: isConnected
                  ? Colors.green.shade600
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          if (isConnected)
            ListTile(
              leading: const Icon(Icons.link_off_rounded),
              title: const Text('Disconnect'),
              onTap: onDisconnect,
            )
          else
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Connect'),
              enabled: !isConnecting,
              onTap: onConnect,
            ),
          if (isKnown)
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
              title: Text(
                'Forget device',
                style: TextStyle(color: colorScheme.error),
              ),
              onTap: onForget,
            ),
          const SizedBox(height: 12),
        ],
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
            value: '${_rssiSignalLabel(rssi)}  ·  $rssi dBm',
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
