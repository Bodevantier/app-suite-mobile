import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/ble_controller.dart';
import '../models/n2k_device_info.dart';
import '../services/wind_averages_service.dart';

class WindDataPage extends StatefulWidget {
  const WindDataPage({
    super.key,
    required this.telemetryController,
    this.device,
    this.hasNavigationDevice = false,
    this.windAverages,
    this.primaryActionLabel,
    this.onPrimaryAction,
  });

  final BleController telemetryController;
  final N2kDeviceInfo? device;
  final bool hasNavigationDevice;
  final WindAveragesService? windAverages;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;

  @override
  State<WindDataPage> createState() => _WindDataPageState();
}

class _WindDataPageState extends State<WindDataPage> {
  bool _showWindSpeedInKnots = false;
  final PageController _pageController = PageController();
  int _selectedPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleWindSpeedUnit() {
    setState(() {
      _showWindSpeedInKnots = !_showWindSpeedInKnots;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff5f7fb),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: const Color(0xfff5f7fb),
        title: Text(
          widget.device == null ? 'Wind Data' : 'Wind Device',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: Color(0xff000000),
          ),
        ),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([
            widget.telemetryController,
            if (widget.windAverages != null) widget.windAverages!,
          ]),
          builder: (context, _) {
            final telemetry = widget.telemetryController.telemetry;
            final windSpeed = telemetry.effectiveTrueWindSpeedMs;
            final windAngle = telemetry.effectiveTrueWindAngleDeg;
            final apparentWindSpeed = telemetry.apparentWindSpeedMs;
            final apparentWindAngle = telemetry.apparentWindAngleDeg;
            final pageCount = 1 +
                (widget.hasNavigationDevice ? 1 : 0) +
                (widget.windAverages != null ? 1 : 0);

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.device != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xffffffff),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xffdfe5ef),
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        widget.device!.displayName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Color(0xff0f172a),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      onPageChanged: (index) {
                        setState(() {
                          _selectedPage = index;
                        });
                      },
                      children: [
                        _WindModeView(
                          title: 'Apparent wind',
                          speedLabel: 'AWS',
                          speedValue: _formatWindSpeed(apparentWindSpeed),
                          angleDeg: apparentWindAngle,
                          sogMs: widget.hasNavigationDevice
                              ? telemetry.sogMs
                              : null,
                          onSpeedTap: _toggleWindSpeedUnit,
                          missingDataMessage: _apparentWindMissingMessage(
                            telemetry.apparentWindSpeedMs,
                          ),
                        ),
                        if (widget.hasNavigationDevice)
                          _WindModeView(
                            title: 'True wind',
                            speedLabel: 'TWS',
                            speedValue: _formatWindSpeed(windSpeed),
                            angleDeg: windAngle,
                            sogMs: telemetry.sogMs,
                            onSpeedTap: _toggleWindSpeedUnit,
                            missingDataMessage: _trueWindMissingMessage(
                              telemetry.effectiveTrueWindSpeedMs,
                            ),
                          ),
                        if (widget.windAverages != null)
                          _WindAveragesView(
                            averages: widget.windAverages!,
                            showKnots: _showWindSpeedInKnots,
                            onUnitTap: _toggleWindSpeedUnit,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (pageCount > 1)
                    _WindPagerIndicator(
                      activeIndex: _selectedPage,
                      count: pageCount,
                    ),
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

  String? _apparentWindMissingMessage(double? apparentWindSpeed) {
    if (apparentWindSpeed == null) return 'Waiting for wind sensor';
    return null;
  }

  String? _trueWindMissingMessage(double? effectiveTws) {
    if (effectiveTws == null) return 'Waiting for wind sensor and SOG';
    return null;
  }

  String _formatWindSpeed(double? speedMps) {
    if (speedMps == null) {
      return '--';
    }

    if (_showWindSpeedInKnots) {
      final speedKnots = speedMps * 1.94384;
      return '${speedKnots.toStringAsFixed(2)} kn';
    }

    return '${speedMps.toStringAsFixed(2)} m/s';
  }
}

class _WindModeView extends StatelessWidget {
  const _WindModeView({
    required this.title,
    required this.speedLabel,
    required this.speedValue,
    required this.angleDeg,
    this.sogMs,
    this.onSpeedTap,
    this.missingDataMessage,
  });

  final String title;
  final String speedLabel;
  final String speedValue;
  final double? angleDeg;
  final double? sogMs;
  final VoidCallback? onSpeedTap;
  final String? missingDataMessage;

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
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: Color(0xff111827),
            ),
          ),
          const SizedBox(height: 14),
          const SizedBox(height: 10),
          Expanded(
            child: missingDataMessage != null
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xffffffff),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xffdfe5ef),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.sensors_off_rounded,
                            size: 36,
                            color: Color(0xff94a3b8),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            missingDataMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xff64748b),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : _WindBoatAngleView(
                    angleDeg: angleDeg,
                    speedLabel: speedLabel,
                    speedValue: speedValue,
                    angleLabel: speedLabel == 'TWS' ? 'TWA' : 'AWA',
                    sogMs: sogMs,
                    onSpeedTap: onSpeedTap,
                  ),
          ),
        ],
      ),
    );
  }
}

class _WindBoatAngleView extends StatelessWidget {
  const _WindBoatAngleView({
    required this.angleDeg,
    required this.speedLabel,
    required this.speedValue,
    required this.angleLabel,
    this.sogMs,
    this.onSpeedTap,
  });

  final double? angleDeg;
  final String speedLabel;
  final String speedValue;
  final String angleLabel;
  final double? sogMs;
  final VoidCallback? onSpeedTap;

  Widget _valueText(String value) {
    return Text(
      value,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: Color(0xff1e293b),
      ),
    );
  }

  Widget _pill(String label, Widget value, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xffffffff),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xffc7d2fe), width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x18000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xff64748b),
              ),
            ),
            const SizedBox(width: 5),
            value,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _AnimatedWindGauge(angleDeg: angleDeg)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _pill(speedLabel, _valueText(speedValue), onTap: onSpeedTap),
            const SizedBox(width: 8),
            _pill(
              angleLabel,
              _AnimatedAngleText(angleDeg: angleDeg),
            ),
          ],
        ),
        if (sogMs != null) ...[
          const SizedBox(height: 8),
          _pill('SOG', _valueText('${(sogMs! * 1.94384).toStringAsFixed(1)} kn')),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _AnimatedAngleText extends StatefulWidget {
  const _AnimatedAngleText({required this.angleDeg});

  final double? angleDeg;

  @override
  State<_AnimatedAngleText> createState() => _AnimatedAngleTextState();
}

class _AnimatedAngleTextState extends State<_AnimatedAngleText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _displayAngle = 0;

  @override
  void initState() {
    super.initState();
    _displayAngle = widget.angleDeg ?? 0;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = AlwaysStoppedAnimation(_displayAngle);
  }

  @override
  void didUpdateWidget(_AnimatedAngleText oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newAngle = widget.angleDeg;
    if (newAngle == null || newAngle == oldWidget.angleDeg) return;

    // Use the current visual position so interrupted animations don't jump.
    final current = _animation.value;
    // Shortest-arc delta in O(1): bring into (-360,360) then clamp to [-180,180].
    var delta = (newAngle - current) % 360;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    final target = current + delta;

    _animation = Tween<double>(begin: current, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _displayAngle = target;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.angleDeg == null) {
      return const Text(
        '--',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Color(0xff1e293b),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        var normalized = _animation.value % 360;
        if (normalized < 0) normalized += 360;
        // Convert NMEA 0–360° to sailing convention: 0–180° S / 0–180° P.
        // 0° = dead ahead, 180° = dead astern (no suffix needed).
        final String label;
        if (normalized <= 0.05 || normalized >= 359.95) {
          label = '0°';
        } else if ((normalized - 180).abs() <= 0.05) {
          label = '180°';
        } else if (normalized < 180) {
          label = '${normalized.toStringAsFixed(1)}° S';
        } else {
          label = '${(360.0 - normalized).toStringAsFixed(1)}° P';
        }
        return Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Color(0xff1e293b),
          ),
        );
      },
    );
  }
}

/// Stateful widget that animates the wind gauge arrow to each new angle using
/// the shortest angular path (handles the 0°/360° wrap-around correctly).
class _AnimatedWindGauge extends StatefulWidget {
  const _AnimatedWindGauge({required this.angleDeg});

  final double? angleDeg;

  @override
  State<_AnimatedWindGauge> createState() => _AnimatedWindGaugeState();
}

class _AnimatedWindGaugeState extends State<_AnimatedWindGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _displayAngle = 0;

  @override
  void initState() {
    super.initState();
    _displayAngle = widget.angleDeg ?? 0;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = AlwaysStoppedAnimation(_displayAngle);
  }

  @override
  void didUpdateWidget(_AnimatedWindGauge old) {
    super.didUpdateWidget(old);
    final newAngle = widget.angleDeg;
    if (newAngle == null || newAngle == old.angleDeg) return;

    // Use the current visual position so interrupted animations don't jump.
    final current = _animation.value;
    // Shortest-arc delta in O(1): bring into (-360,360) then clamp to [-180,180].
    var delta = (newAngle - current) % 360;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    final target = current + delta;

    _animation = Tween<double>(
      begin: current,
      end: target,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _displayAngle = target;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final size = math.min(constraints.maxWidth, constraints.maxHeight);
            return Center(
              child: CustomPaint(
                size: Size(size, size),
                painter: _WindGaugePainter(angleDeg: _animation.value),
              ),
            );
          },
        );
      },
    );
  }
}

class _WindGaugePainter extends CustomPainter {
  const _WindGaugePainter({required this.angleDeg});

  final double? angleDeg;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);
    final outerRadius = size.shortestSide * 0.44;

    _drawTicks(canvas, center, outerRadius);
    _drawPSLabels(canvas, center, outerRadius);
    _drawWindArrow(canvas, center, outerRadius * 0.82, angleDeg);
    _drawBoat(canvas, center, size.shortestSide * 0.30);
  }

  void _drawTicks(Canvas canvas, Offset center, double radius) {
    for (var index = 0; index < 12; index += 1) {
      final boatDeg = index * 30.0;
      final angle = boatDeg * math.pi / 180 - math.pi / 2;
      final isMajor = index % 3 == 0;
      final length = isMajor ? 14.0 : 8.0;

      canvas.drawLine(
        Offset(
          center.dx + (radius - length) * math.cos(angle),
          center.dy + (radius - length) * math.sin(angle),
        ),
        Offset(
          center.dx + radius * math.cos(angle),
          center.dy + radius * math.sin(angle),
        ),
        Paint()
          ..color = const Color(0xff94a3b8)
          ..strokeWidth = isMajor ? 2.5 : 1.5,
      );
    }
  }

  void _drawPSLabels(Canvas canvas, Offset center, double radius) {
    void drawLabel(String text, double dx, double dy) {
      final span = TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Color(0xff94a3b8),
        ),
      );
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(dx - tp.width / 2, dy - tp.height / 2));
    }
    // 'S' at starboard (right, 90°), 'P' at port (left, 270°)
    // Placed inside the gauge at 78 % of outer radius so they never clip.
    final r = radius * 0.78;
    drawLabel('S', center.dx + r, center.dy);
    drawLabel('P', center.dx - r, center.dy);
  }

  void _drawBoat(Canvas canvas, Offset center, double size) {
    final path = Path()
      ..moveTo(center.dx, center.dy - size)
      ..lineTo(center.dx - size * 0.35, center.dy + size * 0.6)
      ..lineTo(center.dx, center.dy + size * 0.35)
      ..lineTo(center.dx + size * 0.35, center.dy + size * 0.6)
      ..close();

    canvas.drawPath(path, Paint()..color = const Color(0xff0f172a));
  }

  void _drawWindArrow(
    Canvas canvas,
    Offset center,
    double radius,
    double? angleDeg,
  ) {
    if (angleDeg == null) {
      return;
    }

    const arrowColor = Color(0xff0ea5e9);
    final angle = angleDeg * math.pi / 180 - math.pi / 2;
    final tip = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );

    // Shaft
    canvas.drawLine(
      center,
      tip,
      Paint()
        ..color = arrowColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.butt,
    );

    // Filled arrowhead triangle at the tip
    const headLen = 14.0;
    const headHalf = 6.0;
    final base = Offset(
      tip.dx - headLen * math.cos(angle),
      tip.dy - headLen * math.sin(angle),
    );
    final left = Offset(
      base.dx + headHalf * math.sin(angle),
      base.dy - headHalf * math.cos(angle),
    );
    final right = Offset(
      base.dx - headHalf * math.sin(angle),
      base.dy + headHalf * math.cos(angle),
    );
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close(),
      Paint()
        ..color = arrowColor
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _WindGaugePainter oldDelegate) {
    return oldDelegate.angleDeg != angleDeg;
  }
}

class _WindPagerIndicator extends StatelessWidget {
  const _WindPagerIndicator({
    required this.activeIndex,
    this.count = 2,
  });

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
            color: isActive ? const Color(0xff0ea5e9) : const Color(0xffcbd5e1),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

// ── Wind Averages page ───────────────────────────────────────────────────────

class _WindAveragesView extends StatelessWidget {
  const _WindAveragesView({
    required this.averages,
    required this.showKnots,
    this.onUnitTap,
  });

  final WindAveragesService averages;
  final bool showKnots;
  final VoidCallback? onUnitTap;

  String _fmt(double? mps) {
    if (mps == null) return '--';
    if (showKnots) return '${(mps * 1.94384).toStringAsFixed(1)} kn';
    return '${mps.toStringAsFixed(1)} m/s';
  }

  String _fmtVmg(double? mps) {
    if (mps == null) return '--';
    final kn = mps * 1.94384;
    return '${kn >= 0 ? '+' : ''}${kn.toStringAsFixed(1)} kn';
  }

  String _spanLabel(Duration span) {
    if (span.inSeconds < 60) return '${span.inSeconds}s of data';
    if (span.inMinutes < 60) return '${span.inMinutes} min of data';
    return '${span.inHours}h ${span.inMinutes % 60}min of data';
  }

  @override
  Widget build(BuildContext context) {
    final span = averages.collectionSpan;
    final unitLabel = showKnots ? 'kn' : 'm/s';

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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Averages',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Color(0xff111827),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onUnitTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xffffffff),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xffc7d2fe)),
                  ),
                  child: Text(
                    unitLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xff3b82f6),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            span.inSeconds < 2 ? 'Collecting data...' : _spanLabel(span),
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xff94a3b8),
            ),
          ),
          const SizedBox(height: 20),

          // Header row
          _tableRow(
            label: '',
            a: '60 s',
            b: '5 min',
            c: '30 min',
            isHeader: true,
          ),
          const SizedBox(height: 8),

          _tableRow(
            label: 'TWS',
            a: _fmt(averages.tws60s),
            b: _fmt(averages.tws5min),
            c: _fmt(averages.tws30min),
          ),
          const Divider(height: 16, color: Color(0xffe2e8f0)),

          _tableRow(
            label: 'AWS',
            a: _fmt(averages.aws60s),
            b: _fmt(averages.aws5min),
            c: _fmt(averages.aws30min),
          ),

          const Spacer(),

          // VMG row
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xffffffff),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xffdfe5ef)),
            ),
            child: Row(
              children: [
                const Text(
                  'VMG',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xff64748b),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '(SOG × cos TWA)',
                  style: TextStyle(fontSize: 12, color: Color(0xffadb5bd)),
                ),
                const Spacer(),
                Text(
                  _fmtVmg(averages.vmgMs),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: averages.vmgMs == null
                        ? const Color(0xff94a3b8)
                        : averages.vmgMs! >= 0
                            ? const Color(0xff16a34a)
                            : const Color(0xffdc2626),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableRow({
    required String label,
    required String a,
    required String b,
    required String c,
    bool isHeader = false,
  }) {
    final style = isHeader
        ? const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xff94a3b8),
          )
        : const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xff1e293b),
          );
    final labelStyle = isHeader
        ? const TextStyle(fontSize: 12, color: Color(0xff94a3b8))
        : const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xff64748b),
          );

    return Row(
      children: [
        SizedBox(width: 44, child: Text(label, style: labelStyle)),
        Expanded(child: Center(child: Text(a, style: style))),
        Expanded(child: Center(child: Text(b, style: style))),
        Expanded(child: Center(child: Text(c, style: style))),
      ],
    );
  }
}
