import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/ble_controller.dart';
import '../models/n2k_device_info.dart';

class WindDataPage extends StatefulWidget {
  const WindDataPage({
    super.key,
    required this.telemetryController,
    this.device,
    this.hasNavigationDevice = false,
    this.primaryActionLabel,
    this.onPrimaryAction,
  });

  final BleController telemetryController;
  final N2kDeviceInfo? device;
  final bool hasNavigationDevice;
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
          animation: widget.telemetryController,
          builder: (context, _) {
            final telemetry = widget.telemetryController.telemetry;
            final windSpeed = telemetry.windSpeed;
            final windAngle = telemetry.windAngleDeg;
            final apparentWindSpeed = telemetry.apparentWindSpeedMs;
            final apparentWindAngle = telemetry.apparentWindAngleDeg;

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
                          title: 'True wind',
                          speedLabel: 'TWS',
                          speedValue: _formatWindSpeed(windSpeed),
                          angleDeg: windAngle,
                          sogMs: widget.hasNavigationDevice
                              ? telemetry.sogMs
                              : null,
                          onSpeedTap: _toggleWindSpeedUnit,
                        ),
                        if (widget.hasNavigationDevice)
                          _WindModeView(
                            title: 'Apparent wind',
                            speedLabel: 'AWS',
                            speedValue: _formatWindSpeed(apparentWindSpeed),
                            angleDeg: apparentWindAngle,
                            sogMs: telemetry.sogMs,
                            onSpeedTap: _toggleWindSpeedUnit,
                            missingDataMessage: _apparentWindMissingMessage(
                              telemetry.windSpeed,
                              telemetry.sogMs,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (widget.hasNavigationDevice)
                    _WindPagerIndicator(activeIndex: _selectedPage),
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

  String? _apparentWindMissingMessage(double? windSpeed, double? sogMs) {
    if (windSpeed == null && sogMs == null) {
      return 'Waiting for wind sensor and chartplotter (SOG)';
    }
    if (windSpeed == null) return 'Waiting for wind sensor';
    if (sogMs == null) return 'Waiting for chartplotter (SOG)';
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

  Widget _pill(String label, String value, {VoidCallback? onTap}) {
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
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xff1e293b),
              ),
            ),
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
            _pill(speedLabel, speedValue, onTap: onSpeedTap),
            const SizedBox(width: 8),
            _pill(
              angleLabel,
              angleDeg == null ? '--' : '${angleDeg!.toStringAsFixed(1)}°',
            ),
          ],
        ),
        if (sogMs != null) ...[
          const SizedBox(height: 8),
          _pill('SOG', '${(sogMs! * 1.94384).toStringAsFixed(1)} kn'),
        ],
        const SizedBox(height: 8),
      ],
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

    // Find the shortest arc so the arrow never spins the long way around.
    var delta = newAngle - _displayAngle;
    while (delta > 180) {
      delta -= 360;
    }
    while (delta < -180) {
      delta += 360;
    }
    final target = _displayAngle + delta;

    _animation = Tween<double>(
      begin: _displayAngle,
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

    final angle = angleDeg * math.pi / 180 - math.pi / 2;
    final tip = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );

    canvas.drawLine(
      center,
      tip,
      Paint()
        ..color = const Color(0xff0ea5e9)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _WindGaugePainter oldDelegate) {
    return oldDelegate.angleDeg != angleDeg;
  }
}

class _WindPagerIndicator extends StatelessWidget {
  const _WindPagerIndicator({required this.activeIndex});

  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(2, (index) {
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
