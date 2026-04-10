import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;

import '../ble/controllers/ble_gateway_controller.dart';
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
  static const int _maxAutoRetries = 4;
  static const Duration _initialRequestDelay = Duration(milliseconds: 500);
  static const Duration _activityQuietWindow = Duration(milliseconds: 1200);
  static const Duration _minRequestSpacing = Duration(milliseconds: 700);
  static const Duration _inFlightStallTimeout = Duration(seconds: 10);
  static const Duration _timeoutBackoffBase = Duration(milliseconds: 1400);
  static const Duration _timeoutBackoffStep = Duration(milliseconds: 1200);
  static const Duration _timeoutBackoffMax = Duration(milliseconds: 5000);

  Timer? _autoRetryTimer;
  Timer? _initialRequestTimer;
  int _autoRetryAttempts = 0;
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
    _cancelAutoRetry();
    _autoRetryAttempts = 0;

    final sent = await _requestDeviceListIfAllowed();
    if (sent) {
      await _waitForRequestCycleToFinish();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _cancelInitialRequest();
    _cancelAutoRetry();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) {
      return;
    }

    if (!widget.controller.isConnected) {
      _cancelInitialRequest();
      _cancelAutoRetry();
      _autoRetryAttempts = 0;
      _initialRequestSent = false;
      _nextRequestAllowedAt = null;
      return;
    }

    if (!_initialRequestSent &&
        _initialRequestTimer == null &&
        !widget.controller.requestPending &&
        !widget.controller.snapshotInProgress) {
      _initialRequestTimer = Timer(_initialRequestDelay, () async {
        _initialRequestTimer = null;
        if (!mounted ||
            !widget.controller.isConnected ||
            widget.controller.requestPending ||
            widget.controller.snapshotInProgress ||
            !_isRequestAllowedNow) {
          return;
        }

        _initialRequestSent = true;
        await _refresh();
      });
    }

    if (widget.controller.latestSnapshot != null ||
        widget.controller.devices.isNotEmpty ||
        (_requestInFlight && !_requestInFlightStalled)) {
      _cancelInitialRequest();
      _cancelAutoRetry();
      return;
    }

    if (widget.controller.lastError != 'device_list request timed out' &&
        !_requestInFlightStalled) {
      _cancelAutoRetry();
      return;
    }

    if (_autoRetryAttempts >= _maxAutoRetries) {
      return;
    }

    _scheduleRetryWhenQuiet();
  }

  bool get _isRequestAllowedNow {
    final nextAllowedAt = _nextRequestAllowedAt;
    if (nextAllowedAt == null) {
      return true;
    }
    return DateTime.now().toUtc().isAfter(nextAllowedAt);
  }

  bool get _requestInFlight =>
      widget.controller.requestPending || widget.controller.snapshotInProgress;

  bool get _requestInFlightStalled {
    if (!_requestInFlight) {
      return false;
    }
    final lastUpdate = widget.controller.lastUpdateAt;
    if (lastUpdate == null) {
      return false;
    }
    return DateTime.now().toUtc().difference(lastUpdate) > _inFlightStallTimeout;
  }

  Future<bool> _requestDeviceListIfAllowed() async {
    if (!widget.controller.isConnected ||
        (_requestInFlight && !_requestInFlightStalled) ||
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

  Future<void> _waitForRequestCycleToFinish() async {
    if (!_requestInFlight || _requestInFlightStalled) {
      return;
    }

    final completer = Completer<void>();
    late final VoidCallback listener;
    listener = () {
      if (!mounted) {
        if (!completer.isCompleted) {
          completer.complete();
        }
        return;
      }

      if (!widget.controller.isConnected ||
          !_requestInFlight ||
          _requestInFlightStalled) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    };

    widget.controller.addListener(listener);
    listener();
    try {
      await completer.future.timeout(const Duration(seconds: 12));
    } on TimeoutException {
      // Safety net: never keep the pull-to-refresh spinner indefinitely.
    } finally {
      widget.controller.removeListener(listener);
    }
  }

  void _cancelAutoRetry() {
    _autoRetryTimer?.cancel();
    _autoRetryTimer = null;
  }

  void _cancelInitialRequest() {
    _initialRequestTimer?.cancel();
    _initialRequestTimer = null;
  }

  void _scheduleRetryWhenQuiet() {
    final now = DateTime.now().toUtc();
    final lastUpdate = widget.controller.lastUpdateAt;

    var delay = Duration.zero;
    if (lastUpdate != null) {
      final quietFor = now.difference(lastUpdate);
      if (quietFor < _activityQuietWindow) {
        delay = _activityQuietWindow - quietFor;
      }
    } else {
      delay = _activityQuietWindow;
    }

    final adaptiveBackoff = _timeoutAdaptiveBackoff;
    if (adaptiveBackoff > delay) {
      delay = adaptiveBackoff;
    }

    _autoRetryTimer?.cancel();
    _autoRetryTimer = Timer(delay, () async {
      _autoRetryTimer = null;
      if (!mounted ||
          !widget.controller.isConnected ||
          widget.controller.requestPending ||
          widget.controller.snapshotInProgress ||
          widget.controller.lastError != 'device_list request timed out' ||
          !_isRequestAllowedNow) {
        return;
      }

      _autoRetryAttempts += 1;
      await _requestDeviceListIfAllowed();
    });
  }

  Duration get _timeoutAdaptiveBackoff {
    final millis = _timeoutBackoffBase.inMilliseconds +
        (_autoRetryAttempts * _timeoutBackoffStep.inMilliseconds);
    final capped = math.min(millis, _timeoutBackoffMax.inMilliseconds);
    return Duration(milliseconds: capped);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final devices = widget.controller.devices;
        final isLoading =
            widget.controller.snapshotInProgress && !_requestInFlightStalled;
        final spacingCooldownActive = !_isRequestAllowedNow;

        return Scaffold(
          appBar: AppBar(title: const Text('N2K Devices')),
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    FilledButton(
                                  onPressed: !widget.controller.isConnected ||
                                    isLoading ||
                                    widget.controller.requestPending ||
                                          spacingCooldownActive
                          ? null
                          : () => _refresh(),
                      child: const Text('Request device list'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.controller.statusLine,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Devices reported by the ESP32 gateway on the N2K bus.',
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Latest gateway payload',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        widget.controller.latestSnapshot?.rawMessage ??
                            'No gateway snapshot received yet.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Recent event lines',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      if (widget.controller.recentEvents.isEmpty)
                        const Text('No event lines received yet.')
                      else
                        ...widget.controller.recentEvents.reversed.map(
                          (event) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(event.rawLine),
                          ),
                        ),
                    ],
                  ),
                ),
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
                                Text('Waiting for N2K device list...'),
                              ],
                            )
                          : Text(() {
                              if (_autoRetryAttempts > 0 &&
                                  _autoRetryAttempts <= _maxAutoRetries) {
                                return 'Retrying device list request ($_autoRetryAttempts/$_maxAutoRetries)...';
                              }
                              if (_autoRetryTimer != null &&
                                  (widget.controller.lastError ==
                                      'device_list request timed out' ||
                                    _requestInFlightStalled)) {
                                return 'Waiting for gateway traffic to settle...';
                              }
                              return 'No N2K devices reported yet.';
                            }()),
                    ),
                  )
                else
                  ...devices.map(
                    (device) => Card(
                      child: ListTile(
                        title: Text(device.displayName),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Source address: ${device.sourceAddress}'),
                            if (device.hasLiveWindData)
                              const Text('Live wind source: yes'),
                            Text('Manufacturer: ${device.displayManufacturer}'),
                            Text('Model: ${device.displayModel}'),
                            Text('Category: ${device.displayCategory}'),
                            Text(
                              'Last seen: ${_formatLastSeen(device.lastSeen)}',
                            ),
                          ],
                        ),
                        trailing: Text(
                          device.isOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            color: device.isOnline
                                ? Colors.green.shade700
                                : Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatLastSeen(DateTime? value) {
    if (value == null) {
      return 'unknown';
    }
    return value.toLocal().toString();
  }
}
