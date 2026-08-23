import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/ble_controller.dart';
import '../models/n2k_device_info.dart';
import '../models/node_settings.dart';
import '../models/telemetry_data.dart';
import '../services/alarm_monitor_service.dart';
import '../services/node_settings_service.dart';
import '../services/temperature_history_service.dart';
import 'node_settings_page.dart';

// ── Page widget ───────────────────────────────────────────────────────────────

class TemperatureDataPage extends StatefulWidget {
  const TemperatureDataPage({
    super.key,
    required this.telemetryController,
    required this.temperatureHistory,
    this.device,
    this.settingsService,
    this.alarmMonitor,
    this.primaryActionLabel,
    this.onPrimaryAction,
  });

  final BleController telemetryController;
  final TemperatureHistoryService temperatureHistory;
  final N2kDeviceInfo? device;
  final NodeSettingsService? settingsService;
  final AlarmMonitorService? alarmMonitor;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;

  @override
  State<TemperatureDataPage> createState() => _TemperatureDataPageState();
}

class _TemperatureDataPageState extends State<TemperatureDataPage> {
  final PageController _pageController = PageController();
  int _selectedPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Telemetry scoped to this page's node when one is given, so a second
  /// temperature sensor on the bus cannot mix its readings into this view
  /// or its history chart.
  TelemetryData _telemetry() {
    final device = widget.device;
    return device != null
        ? widget.telemetryController.telemetryFor(device.sourceAddress)
        : widget.telemetryController.telemetry;
  }

  /// History is logged app-wide (see `AppDependencies.standard()`), keyed by
  /// N2K source address so a second temperature sensor's readings don't mix
  /// into this chart.
  List<TempHistorySample> _history() =>
      widget.temperatureHistory.historyFor(widget.device?.sourceAddress ?? -1);

  /// All-time low/high for this page's node, persisted across app restarts.
  TempRecord _record() =>
      widget.temperatureHistory.recordFor(widget.device?.sourceAddress ?? -1);

void _openSettings() {
    if (widget.device == null || widget.settingsService == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NodeSettingsPage(
          device: widget.device!,
          settingsService: widget.settingsService!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSettings =
        widget.device != null && widget.settingsService != null;
    return Scaffold(
      backgroundColor: const Color(0xfff5f7fb),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: const Color(0xfff5f7fb),
        title: Text(
          widget.device?.displayName ?? 'Temperature',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: Color(0xff000000),
          ),
        ),
        actions: [
          if (hasSettings)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Device settings',
              onPressed: _openSettings,
            ),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([
            widget.telemetryController,
            widget.temperatureHistory,
            if (widget.settingsService != null) widget.settingsService!,
            ?widget.alarmMonitor,
          ]),
          builder: (context, _) {
            final telemetry = _telemetry();
            final device = widget.device;
            final settings = (device != null && widget.settingsService != null)
                ? widget.settingsService!.forDevice(device)
                : NodeSettings.empty;
            final tempC = telemetry.temperatureC;
            final showHigh = device != null &&
                (widget.alarmMonitor?.isActive(device, AlarmKind.tempHigh) ??
                    false);
            final showLow = device != null &&
                (widget.alarmMonitor?.isActive(device, AlarmKind.tempLow) ??
                    false);
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showHigh) ...[               
                    _TempAlarmBanner(
                      message:
                          'High temperature — above ${settings.highTempAlarmC.round()} °C',
                      isHigh: true,
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (showLow) ...[               
                    _TempAlarmBanner(
                      message:
                          'Low temperature — below ${settings.lowTempAlarmC.round()} °C',
                      isHigh: false,
                    ),
                    const SizedBox(height: 10),
                  ],
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      onPageChanged: (index) {
                        setState(() => _selectedPage = index);
                      },
                      children: [
                        _TemperatureCard(
                          temperatureC: tempC,
                        ),
                        _TemperatureHistoryView(
                          history: _history(),
                          currentTempC: tempC,
                        ),
                        _TemperatureRecordsView(
                          record: _record(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _TempPagerIndicator(activeIndex: _selectedPage, count: 3),
                  if (widget.primaryActionLabel != null) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: widget.onPrimaryAction,
                        child: Text(widget.primaryActionLabel!),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Alarm banner ──────────────────────────────────────────────────────────────

class _TempAlarmBanner extends StatelessWidget {
  const _TempAlarmBanner({required this.message, required this.isHigh});
  final String message;
  final bool isHigh;

  @override
  Widget build(BuildContext context) {
    final bg = isHigh
        ? const Color(0xfffee2e2) // red-100
        : const Color(0xffe0f2fe); // sky-100
    final border = isHigh
        ? const Color(0xfffca5a5) // red-300
        : const Color(0xff7dd3fc); // sky-300
    final iconColor = isHigh
        ? const Color(0xffb91c1c) // red-700
        : const Color(0xff0369a1); // sky-700
    final textColor = isHigh
        ? const Color(0xff7f1d1d) // red-900
        : const Color(0xff0c4a6e); // sky-900
    final icon = isHigh
        ? Icons.thermostat_rounded
        : Icons.ac_unit_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Live card ─────────────────────────────────────────────────────────────────

class _TemperatureCard extends StatelessWidget {
  const _TemperatureCard({this.temperatureC});
  final double? temperatureC;

  @override
  Widget build(BuildContext context) {
    if (temperatureC == null) {
      return Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xfff9fbff), Color(0xffedf3ff)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xffd9e4ff), width: 1.2),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sensors_off_rounded,
                size: 36,
                color: Color(0xff94a3b8),
              ),
              SizedBox(height: 10),
              Text(
                'Waiting for temperature sensor',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xff64748b),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final celsius = temperatureC!;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xfff9fbff), Color(0xffedf3ff)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xffd9e4ff), width: 1.2),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.thermostat_rounded,
            size: 56,
            color: Color(0xff64748b),
          ),
          const SizedBox(height: 20),
          Text(
            '${celsius.toStringAsFixed(1)} °C',
            style: const TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w800,
              color: Color(0xff0f172a),
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pager indicator ───────────────────────────────────────────────────────────

class _TempPagerIndicator extends StatelessWidget {
  const _TempPagerIndicator({required this.activeIndex, required this.count});
  final int activeIndex;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(count, (index) {
        final isActive = index == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xff0ea5e9)
                : const Color(0xffcbd5e1),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

// ── History / graph page ──────────────────────────────────────────────────────

class _TemperatureHistoryView extends StatelessWidget {
  const _TemperatureHistoryView({
    required this.history,
    this.currentTempC,
  });

  final List<TempHistorySample> history;
  final double? currentTempC;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xfff9fbff), Color(0xffedf3ff)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xffd9e4ff), width: 1.2),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header row ──────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Temperature Log',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Color(0xff111827),
                ),
              ),
              const Spacer(),
              if (currentTempC != null)
                Text(
                  '${currentTempC!.toStringAsFixed(1)} °C',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xff0ea5e9),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // ── Chart ───────────────────────────────────────────────────────
          Expanded(
            child: _TempChart(history: history),
          ),
        ],
      ),
    );
  }
}

// ── Records page ─────────────────────────────────────────────────────────────

class _TemperatureRecordsView extends StatelessWidget {
  const _TemperatureRecordsView({required this.record});

  final TempRecord record;

  @override
  Widget build(BuildContext context) {
    final hasData = record.minC != null && record.maxC != null;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xfff9fbff), Color(0xffedf3ff)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xffd9e4ff), width: 1.2),
      ),
      padding: const EdgeInsets.all(16),
      child: hasData
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'All-Time Records',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: Color(0xff111827),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: _RecordStatCard(
                    label: 'All-time high',
                    celsius: record.maxC!,
                    at: record.maxAt,
                    icon: Icons.thermostat_rounded,
                    accent: const Color(0xffb91c1c), // red-700
                    gradient: const [Color(0xfffff5f5), Color(0xfffee2e2)],
                    borderColor: const Color(0xfffca5a5), // red-300
                  ),
                ),
                const SizedBox(height: 12),
                _RecordRangeBadge(rangeC: record.maxC! - record.minC!),
                const SizedBox(height: 12),
                Expanded(
                  child: _RecordStatCard(
                    label: 'All-time low',
                    celsius: record.minC!,
                    at: record.minAt,
                    icon: Icons.ac_unit_rounded,
                    accent: const Color(0xff0369a1), // sky-700
                    gradient: const [Color(0xfff0f9ff), Color(0xffe0f2fe)],
                    borderColor: const Color(0xff7dd3fc), // sky-300
                  ),
                ),
              ],
            )
          : const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.query_stats_rounded,
                    size: 36,
                    color: Color(0xff94a3b8),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'No records yet',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xff64748b),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Keep the app running to start tracking\nall-time highs and lows.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xff94a3b8),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _RecordStatCard extends StatelessWidget {
  const _RecordStatCard({
    required this.label,
    required this.celsius,
    required this.at,
    required this.icon,
    required this.accent,
    required this.gradient,
    required this.borderColor,
  });

  final String label;
  final double celsius;
  final DateTime? at;
  final IconData icon;
  final Color accent;
  final List<Color> gradient;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 17, color: accent),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${celsius.toStringAsFixed(1)} °C',
            style: const TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w800,
              color: Color(0xff0f172a),
              letterSpacing: -1,
            ),
          ),
          if (at != null) ...[
            const SizedBox(height: 6),
            Text(
              '${_formatRecordAge(at!)} · ${_formatFullRecordDate(at!)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xff64748b),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecordRangeBadge extends StatelessWidget {
  const _RecordRangeBadge({required this.rangeC});
  final double rangeC;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xffffffff),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xffdfe5ef), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.swap_vert_rounded,
              size: 14,
              color: Color(0xff64748b),
            ),
            const SizedBox(width: 6),
            Text(
              '${rangeC.toStringAsFixed(1)} °C range',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xff475569),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Short relative label for when an all-time record was set — matches the
/// age-formatting convention already used on the chart's X-axis (see
/// `_TempChartPainter`).
String _formatRecordAge(DateTime at) {
  final age = DateTime.now().difference(at);
  if (age.inSeconds < 60) return 'just now';
  if (age.inMinutes < 60) return '${age.inMinutes}m ago';
  if (age.inHours < 24) return '${age.inHours}h ago';
  return '${age.inDays}d ago';
}

/// Full calendar date + time for a record, e.g. "3 Jan 2026, 14:32".
String _formatFullRecordDate(DateTime at) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h = at.hour.toString().padLeft(2, '0');
  final m = at.minute.toString().padLeft(2, '0');
  return '${at.day} ${months[at.month - 1]} ${at.year}, $h:$m';
}

// ── Chart widget ──────────────────────────────────────────────────────────────

class _TempChart extends StatefulWidget {
  const _TempChart({required this.history});

  final List<TempHistorySample> history;

  @override
  State<_TempChart> createState() => _TempChartState();
}

class _TempChartState extends State<_TempChart> {
  // null = auto (always show all data, minimum 60 s).
  // Set to a specific second count when the user pinches to zoom in.
  double? _zoomedWindowSeconds;
  double _windowAtScaleStart = 60.0;

  @override
  Widget build(BuildContext context) {
    if (widget.history.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart_rounded, size: 36, color: Color(0xff94a3b8)),
            SizedBox(height: 10),
            Text(
              'Collecting temperature data…',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xff64748b),
              ),
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final totalSpan =
        now.difference(widget.history.first.timestamp).inSeconds.toDouble();

    // Always show at least 60 s so the chart doesn't feel reactive during
    // the first minute. After that it expands naturally.
    final autoWindow = math.max(60.0, totalSpan);

    // Current window in seconds. Zoom can only shrink it down to 30 s.
    final windowSec =
        (_zoomedWindowSeconds ?? autoWindow).clamp(30.0, autoWindow);
    final isZoomed =
        _zoomedWindowSeconds != null && windowSec < autoWindow - 1;

    final start =
        now.subtract(Duration(milliseconds: (windowSec * 1000).round()));
    final visible =
        widget.history.where((s) => s.timestamp.isAfter(start)).toList();

    return GestureDetector(
      // Pinch-to-zoom: spreading fingers zooms in (smaller window).
      onScaleStart: (_) {
        _windowAtScaleStart = _zoomedWindowSeconds ?? autoWindow;
      },
      onScaleUpdate: (details) {
        if (details.scale == 1.0) return; // ignore pure pan
        final newWindow = (_windowAtScaleStart / details.scale)
            .clamp(30.0, autoWindow);
        setState(() => _zoomedWindowSeconds = newWindow);
      },
      // Double-tap resets zoom.
      onDoubleTap: () => setState(() => _zoomedWindowSeconds = null),
      child: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _TempChartPainter(
                  samples: visible,
                  now: now,
                  start: start,
                ),
              );
            },
          ),
          // Small reset-zoom badge shown only while zoomed in.
          if (isZoomed)
            Positioned(
              bottom: 32,
              right: 4,
              child: GestureDetector(
                onTap: () => setState(() => _zoomedWindowSeconds = null),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xff0ea5e9).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xff0ea5e9),
                      width: 1,
                    ),
                  ),
                  child: const Text(
                    'Reset zoom',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xff0ea5e9),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Custom painter ────────────────────────────────────────────────────────────

class _TempChartPainter extends CustomPainter {
  const _TempChartPainter({
    required this.samples,
    required this.now,
    required this.start,
  });

  final List<TempHistorySample> samples;
  final DateTime now;
  final DateTime start;

  static const _leftPad = 44.0;
  static const _rightPad = 12.0;
  static const _topPad = 10.0;
  static const _bottomPad = 28.0;
  static const _accentColor = Color(0xff0ea5e9); // sky-500

  @override
  void paint(Canvas canvas, Size size) {
    final chartLeft = _leftPad;
    final chartRight = size.width - _rightPad;
    final chartTop = _topPad;
    final chartBottom = size.height - _bottomPad;
    final chartW = chartRight - chartLeft;
    final chartH = chartBottom - chartTop;

    if (chartW <= 0 || chartH <= 0 || samples.isEmpty) return;

    // ── Determine Y range with 1°C padding ─────────────────────────────
    double minC = samples.map((s) => s.celsius).reduce(math.min);
    double maxC = samples.map((s) => s.celsius).reduce(math.max);
    if ((maxC - minC) < 1.0) {
      final mid = (maxC + minC) / 2;
      minC = mid - 0.5;
      maxC = mid + 0.5;
    } else {
      minC -= 0.5;
      maxC += 0.5;
    }

    // ── Helpers ────────────────────────────────────────────────────────
    double xOf(DateTime t) {
      final span = now.difference(start).inMicroseconds;
      if (span == 0) return chartLeft;
      final offset = t.difference(start).inMicroseconds;
      return chartLeft + (offset / span) * chartW;
    }

    double yOf(double c) {
      return chartBottom - ((c - minC) / (maxC - minC)) * chartH;
    }

    // ── Grid lines + Y-axis labels ──────────────────────────────────────
    final gridPaint = Paint()
      ..color = const Color(0xffdde3ef)
      ..strokeWidth = 0.8;

    final labelStyle = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      color: const Color(0xff94a3b8),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    const gridLines = 4;
    for (var i = 0; i <= gridLines; i++) {
      final t = minC + (maxC - minC) * i / gridLines;
      final y = yOf(t);
      canvas.drawLine(
        Offset(chartLeft, y),
        Offset(chartRight, y),
        gridPaint,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${t.toStringAsFixed(1)}°',
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(chartLeft - tp.width - 4, y - tp.height / 2));
    }

    // ── X-axis time labels ──────────────────────────────────────────────
    const xTicks = 4;
    final totalSec = now.difference(start).inSeconds;
    for (var i = 0; i <= xTicks; i++) {
      final t = start.add(Duration(seconds: (totalSec * i / xTicks).round()));
      final x = xOf(t);
      final age = now.difference(t).inSeconds;
      final String label;
      if (age < 5) {
        label = 'now';
      } else if (age < 60) {
        label = '${age}s ago';
      } else if (age < 3600) {
        label = '${age ~/ 60}m ago';
      } else {
        final h = age ~/ 3600;
        final m = (age % 3600) ~/ 60;
        label = m > 0 ? '${h}h ${m}m' : '${h}h ago';
      }
      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      // Clamp so end labels don't overflow the chart edges.
      final dx = (x - tp.width / 2).clamp(chartLeft, chartRight - tp.width);
      tp.paint(canvas, Offset(dx, chartBottom + 6));
    }

    // ── Filled area under curve ─────────────────────────────────────────
    final fillPath = Path();
    fillPath.moveTo(xOf(samples.first.timestamp), chartBottom);
    for (final s in samples) {
      fillPath.lineTo(xOf(s.timestamp), yOf(s.celsius));
    }
    fillPath.lineTo(xOf(samples.last.timestamp), chartBottom);
    fillPath.close();

    final fillRect = Rect.fromLTWH(chartLeft, chartTop, chartW, chartH);
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _accentColor.withValues(alpha: 0.28),
            _accentColor.withValues(alpha: 0.03),
          ],
        ).createShader(fillRect),
    );

    // ── Line ────────────────────────────────────────────────────────────
    final linePath = Path();
    linePath.moveTo(xOf(samples.first.timestamp), yOf(samples.first.celsius));
    for (var i = 1; i < samples.length; i++) {
      linePath.lineTo(xOf(samples[i].timestamp), yOf(samples[i].celsius));
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = _accentColor
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // ── Last-value dot ──────────────────────────────────────────────────
    final last = samples.last;
    final dotX = xOf(last.timestamp);
    final dotY = yOf(last.celsius);
    canvas.drawCircle(
      Offset(dotX, dotY),
      5,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(dotX, dotY),
      3.5,
      Paint()..color = _accentColor,
    );
  }

  @override
  bool shouldRepaint(covariant _TempChartPainter old) =>
      old.samples.length != samples.length ||
      old.now != now ||
      (samples.isNotEmpty &&
          old.samples.isNotEmpty &&
          old.samples.last.celsius != samples.last.celsius);
}
