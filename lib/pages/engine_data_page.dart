import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/ble_controller.dart';
import '../models/engine_settings.dart';
import '../models/n2k_device_info.dart';
import '../services/node_settings_service.dart';
import 'node_settings_page.dart';

/// Live view for an NMEA 2000 Engine (PGN 127488) source. Shows an analogue
/// RPM gauge plus a numeric readout. The RPM-calibration parameters live on
/// the per-device settings screen (the gear icon on the home card), not here.
class EngineDataPage extends StatefulWidget {
  const EngineDataPage({
    super.key,
    required this.telemetryController,
    this.device,
    this.settingsService,
  });

  final BleController telemetryController;
  final N2kDeviceInfo? device;
  final NodeSettingsService? settingsService;

  @override
  State<EngineDataPage> createState() => _EngineDataPageState();
}

class _EngineDataPageState extends State<EngineDataPage> {
  EngineSettings _settings = const EngineSettings();
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final loaded = await EngineSettings.load();
    if (mounted) setState(() => _settings = loaded);
  }

  /// Re-reads the calibration from storage. Called when this page becomes
  /// visible again (e.g. after returning from the per-device settings screen)
  /// so the gauge picks up freshly-saved parameters.
  Future<void> _refreshSettings() async {
    if (_refreshing) return;
    _refreshing = true;
    final loaded = await EngineSettings.load();
    _refreshing = false;
    if (!mounted) return;
    if (loaded.alternatorPoles != _settings.alternatorPoles ||
        loaded.pulleyRatio != _settings.pulleyRatio ||
        loaded.maxRpm != _settings.maxRpm) {
      setState(() => _settings = loaded);
    }
  }

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

  String _title() {
    final device = widget.device;
    final svc = widget.settingsService;
    if (device != null && svc != null) {
      final override = svc.forDevice(device).customName;
      if (override != null && override.trim().isNotEmpty) return override;
    }
    return device?.displayName ?? 'Engine';
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
        title: AnimatedBuilder(
          animation: widget.settingsService ?? const _NeverNotifier(),
          builder: (context, _) => Text(
            _title(),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: Color(0xff000000),
            ),
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
          animation: widget.telemetryController,
          builder: (context, _) {
            // Cheap: pull any newly-saved calibration each rebuild.
            _refreshSettings();
            // Read this node's own telemetry so a second engine on the bus
            // cannot drive this gauge.
            final device = widget.device;
            final telemetry = device != null
                ? widget.telemetryController.telemetryFor(device.sourceAddress)
                : widget.telemetryController.telemetry;
            final calibrated = _settings.calibrate(telemetry.engineRpm);
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _RpmGauge(
                      rpm: calibrated,
                      maxRpm: _settings.maxRpm.toDouble(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CalibrationSummary(settings: _settings),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Compact strip under the gauge that reminds the user of the active
/// calibration so an obviously-wrong reading is easy to diagnose.
class _CalibrationSummary extends StatelessWidget {
  const _CalibrationSummary({required this.settings});
  final EngineSettings settings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffe2e8f0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem('Poles', '${settings.alternatorPoles}'),
          _divider(),
          _summaryItem('Pulley', '${settings.pulleyRatio.toStringAsFixed(2)}:1'),
          _divider(),
          _summaryItem('Pulses/rev', settings.pulsesPerRev.toStringAsFixed(1)),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 28,
        color: const Color(0xffe2e8f0),
      );

  Widget _summaryItem(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xff1e293b),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xff94a3b8)),
        ),
      ],
    );
  }
}

/// Analogue-style circular RPM gauge with a 270° sweep.
class _RpmGauge extends StatelessWidget {
  const _RpmGauge({required this.rpm, required this.maxRpm});

  final double? rpm;
  final double maxRpm;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: CustomPaint(
              painter: _RpmGaugePainter(
                rpm: rpm?.clamp(0, maxRpm).toDouble(),
                maxRpm: maxRpm,
              ),
              // Readout sits in the lower-centre gap of the 270° dial — the
              // one sector the needle never points to — so it can never be
              // covered by the needle or its hub.
              child: Align(
                alignment: const Alignment(0, 0.62),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      rpm == null ? '----' : rpm!.round().toString(),
                      style: TextStyle(
                        fontSize: side * 0.16,
                        fontWeight: FontWeight.w800,
                        color: rpm == null
                            ? const Color(0xff94a3b8)
                            : const Color(0xff0f172a),
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'RPM',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: Color(0xff64748b),
                      ),
                    ),
                    if (rpm == null) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Waiting for engine data',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xff94a3b8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RpmGaugePainter extends CustomPainter {
  _RpmGaugePainter({required this.rpm, required this.maxRpm});

  final double? rpm;
  final double maxRpm;

  // 270° sweep starting bottom-left (135°) going clockwise to bottom-right.
  static const double _startAngle = math.pi * 0.75; // 135°
  static const double _sweepAngle = math.pi * 1.5; // 270°

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 16;
    final strokeWidth = size.width * 0.08;

    // Track.
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xffe2e8f0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      _sweepAngle,
      false,
      trackPaint,
    );

    // Value arc.
    if (rpm != null && maxRpm > 0) {
      final fraction = (rpm! / maxRpm).clamp(0.0, 1.0);
      final redline = 0.83; // ~5000 of 6000
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: _startAngle,
          endAngle: _startAngle + _sweepAngle,
          colors: fraction >= redline
              ? const [Color(0xff0ea5e9), Color(0xffef4444)]
              : const [Color(0xff22c55e), Color(0xff0ea5e9)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        _startAngle,
        _sweepAngle * fraction,
        false,
        arcPaint,
      );
    }

    // Major ticks + labels every 1000 RPM.
    final tickCount = (maxRpm / 1000).round();
    final tickPaint = Paint()
      ..color = const Color(0xff94a3b8)
      ..strokeWidth = 2;
    final textStyle = const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: Color(0xff64748b),
    );
    for (var i = 0; i <= tickCount; i++) {
      final frac = i / tickCount;
      final angle = _startAngle + _sweepAngle * frac;
      final outer = Offset(
        center.dx + (radius - strokeWidth) * math.cos(angle),
        center.dy + (radius - strokeWidth) * math.sin(angle),
      );
      final inner = Offset(
        center.dx + (radius - strokeWidth - 10) * math.cos(angle),
        center.dy + (radius - strokeWidth - 10) * math.sin(angle),
      );
      canvas.drawLine(inner, outer, tickPaint);

      final tp = TextPainter(
        text: TextSpan(text: '$i', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelRadius = radius - strokeWidth - 26;
      final labelPos = Offset(
        center.dx + labelRadius * math.cos(angle) - tp.width / 2,
        center.dy + labelRadius * math.sin(angle) - tp.height / 2,
      );
      tp.paint(canvas, labelPos);
    }

    // Needle.
    if (rpm != null && maxRpm > 0) {
      final fraction = (rpm! / maxRpm).clamp(0.0, 1.0);
      final angle = _startAngle + _sweepAngle * fraction;
      final needlePaint = Paint()
        ..color = const Color(0xff0f172a)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      final tip = Offset(
        center.dx + (radius - strokeWidth - 4) * math.cos(angle),
        center.dy + (radius - strokeWidth - 4) * math.sin(angle),
      );
      final tail = Offset(
        center.dx - 14 * math.cos(angle),
        center.dy - 14 * math.sin(angle),
      );
      canvas.drawLine(tail, tip, needlePaint);
      canvas.drawCircle(center, 7, Paint()..color = const Color(0xff0f172a));
      canvas.drawCircle(center, 3, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _RpmGaugePainter old) =>
      old.rpm != rpm || old.maxRpm != maxRpm;
}

/// Listenable that never fires — keeps AnimatedBuilder happy when no settings
/// service is supplied.
class _NeverNotifier extends Listenable {
  const _NeverNotifier();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}
