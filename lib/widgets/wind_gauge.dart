import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/wind_angle_history_service.dart';

/// Boat-relative wind gauge: bow at top, tick marks every 30°, soft
/// port/starboard tinting, a stylised boat silhouette, and a pointer at
/// [angleDeg] that animates along the shortest angular path whenever the
/// angle changes (handles the 0°/360° wrap-around correctly). Optionally
/// overlays a recency-weighted heatmap ring built from [history].
///
/// Sizes itself to whatever square space its parent gives it — used both by
/// the full Wind data page and by the dashboard's Wind compass tile, so the
/// two always look and animate identically.
class WindGauge extends StatefulWidget {
  const WindGauge({
    super.key,
    required this.angleDeg,
    this.history = const [],
    this.showHeatmap = false,
    this.trailHalfLifeSec = 60.0,
    this.trailSigmaDeg = 2.0,
    this.showPortStarboardLabels = true,
  });

  final double? angleDeg;
  final List<AngleSample> history;
  final bool showHeatmap;
  final double trailHalfLifeSec;
  final double trailSigmaDeg;

  /// Whether to draw the "P"/"S" port/starboard letters inside the dial.
  /// Useful on the full Wind page; redundant clutter on a small dashboard
  /// tile where the red/starboard-green tint alone already reads fine.
  final bool showPortStarboardLabels;

  @override
  State<WindGauge> createState() => _WindGaugeState();
}

class _WindGaugeState extends State<WindGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _displayAngle = 0;

  // Cached heatmap gradient — recomputed only when history grows or the
  // heatmap is toggled on. Never runs inside the animation loop.
  List<Color> _heatmapColors = const [];
  List<double> _heatmapStops = const [];
  // Track the last history length we built the cache for. Because the parent
  // passes the same mutable list object every build, we cannot rely on
  // old.history.length vs widget.history.length (they're the same object).
  int _cachedHistoryLength = -1;

  /// Bins, smooths, and colour-maps [widget.history] into gradient stop lists
  /// stored in [_heatmapColors] / [_heatmapStops]. The painter reads these
  /// directly and does zero computation of its own.
  void _rebuildHeatmap() {
    if (!widget.showHeatmap || widget.history.isEmpty) {
      _heatmapColors = const [];
      _heatmapStops = const [];
      return;
    }

    const binCount = 720; // 0.5° per bin for an ultra-smooth ring
    const binSizeDeg = 360.0 / binCount;
    final raw = List<double>.filled(binCount, 0);

    final now = DateTime.now();
    // Exponential recency weighting — half-life is user-configurable.
    final halfLifeSec = widget.trailHalfLifeSec;
    final lambda = math.ln2 / halfLifeSec;
    for (final s in widget.history) {
      final ageSec = now.difference(s.timestamp).inMilliseconds / 1000.0;
      if (ageSec < 0) continue;
      final w = math.exp(-lambda * ageSec);
      var deg = s.angleDeg % 360;
      if (deg < 0) deg += 360;
      final bin = (deg / binSizeDeg).floor() % binCount;
      raw[bin] += w;
    }

    // Circular Gaussian smoothing — sigma is user-configurable (degrees × 2 = bins at 0.5°/bin).
    final sigma = widget.trailSigmaDeg * 2.0;
    final kernelRadius = (sigma * 3).ceil();
    final kernel = List<double>.generate(
      kernelRadius * 2 + 1,
      (i) {
        final x = i - kernelRadius;
        return math.exp(-(x * x) / (2 * sigma * sigma));
      },
    );
    final kernelSum = kernel.fold<double>(0, (a, b) => a + b);
    final smoothed = List<double>.filled(binCount, 0);
    double maxW = 0;
    for (var i = 0; i < binCount; i++) {
      double acc = 0;
      for (var k = 0; k < kernel.length; k++) {
        final idx = (i + k - kernelRadius) % binCount;
        final wrapped = idx < 0 ? idx + binCount : idx;
        acc += raw[wrapped] * kernel[k];
      }
      smoothed[i] = acc / kernelSum;
      if (smoothed[i] > maxW) maxW = smoothed[i];
    }
    if (maxW <= 0) {
      _heatmapColors = const [];
      _heatmapStops = const [];
      return;
    }

    // Smooth 3-stop colour ramp: transparent background → soft teal → warm
    // amber. Gentle gamma (0.75) and linear alpha keep the transition gradual
    // so the "cloud" blends rather than showing sharp colour bands.
    const bgColor = Color(0xfff5f7fb);
    Color colorFor(double intensity) {
      // Gamma < 1 lifts mid-range visibility without crushing the low end.
      final t = math.pow(intensity.clamp(0.0, 1.0), 0.75).toDouble();
      final Color base;
      if (t < 0.5) {
        base = Color.lerp(
          bgColor,
          const Color(0xff14b8a6), // teal-500
          t / 0.5,
        )!;
      } else {
        base = Color.lerp(
          const Color(0xff14b8a6), // teal-500
          const Color(0xfff59e0b), // amber-500
          (t - 0.5) / 0.5,
        )!;
      }
      // Linear alpha: low-intensity areas are faint but not invisible.
      return base.withValues(alpha: t.clamp(0.0, 1.0));
    }

    final colors = <Color>[];
    final stops = <double>[];
    for (var i = 0; i < binCount; i++) {
      colors.add(colorFor(smoothed[i] / maxW));
      stops.add((i + 0.5) / binCount);
    }
    // Seamless wrap: prepend last colour at 0.0, append first at 1.0.
    colors.insert(0, colors.last);
    stops.insert(0, 0.0);
    colors.add(colors[1]);
    stops.add(1.0);

    _heatmapColors = colors;
    _heatmapStops = stops;
  }

  @override
  void initState() {
    super.initState();
    _displayAngle = widget.angleDeg ?? 0;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = AlwaysStoppedAnimation(_displayAngle);
    _rebuildHeatmap();
    _cachedHistoryLength = widget.history.length;
  }

  @override
  void didUpdateWidget(WindGauge old) {
    super.didUpdateWidget(old);
    // Rebuild heatmap cache only when history grows or the toggle changes —
    // not on every animation frame. Use _cachedHistoryLength (not
    // old.history.length) because the parent reuses the same list object.
    if (widget.history.length != _cachedHistoryLength ||
        widget.showHeatmap != old.showHeatmap ||
        widget.trailHalfLifeSec != old.trailHalfLifeSec ||
        widget.trailSigmaDeg != old.trailSigmaDeg) {
      _rebuildHeatmap();
      _cachedHistoryLength = widget.history.length;
    }

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
                painter: _WindGaugePainter(
                  angleDeg: _animation.value,
                  heatmapColors: _heatmapColors,
                  heatmapStops: _heatmapStops,
                  showPortStarboardLabels: widget.showPortStarboardLabels,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _WindGaugePainter extends CustomPainter {
  const _WindGaugePainter({
    required this.angleDeg,
    this.heatmapColors = const [],
    this.heatmapStops = const [],
    this.showPortStarboardLabels = true,
  });

  final double? angleDeg;
  /// Pre-built gradient colours from [_WindGaugeState._rebuildHeatmap].
  final List<Color> heatmapColors;
  final List<double> heatmapStops;
  final bool showPortStarboardLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);
    final outerRadius = size.shortestSide * 0.44;

    if (heatmapColors.isNotEmpty) {
      _drawHeatmap(canvas, center, outerRadius, size.shortestSide);
    }
    _drawPortStarboardWash(canvas, center, outerRadius);
    _drawTicks(canvas, center, outerRadius);
    if (showPortStarboardLabels) {
      _drawPSLabels(canvas, center, outerRadius);
    }
    _drawWindArrow(canvas, center, outerRadius * 0.82, angleDeg);
    final boatRadius = size.shortestSide * 0.30;
    _drawBoat(canvas, center.translate(0, boatRadius * 0.19), boatRadius);
  }

  /// Draws the pre-built heatmap ring. All heavy computation (binning,
  /// Gaussian smoothing, colour mapping) is done once in
  /// [_WindGaugeState._rebuildHeatmap] and cached there; this method
  /// only issues a single GPU draw call.
  ///
  /// The ring's offset/thickness scale with [shortestSide] rather than
  /// being fixed pixels — on a small dashboard tile, fixed offsets pushed
  /// the ring past the canvas edge and it came out clipped/smeared.
  void _drawHeatmap(
    Canvas canvas,
    Offset center,
    double outerRadius,
    double shortestSide,
  ) {
    final ringInner = outerRadius + shortestSide * 0.01;
    final ringOuter = outerRadius + shortestSide * 0.05;
    final midRadius = (ringInner + ringOuter) / 2;
    final ringRect = Rect.fromCircle(center: center, radius: midRadius);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringOuter - ringInner
      ..strokeCap = StrokeCap.butt
      ..shader = SweepGradient(
        // SweepGradient starts at 3 o'clock; rotate to 12 o'clock (bow).
        transform: const GradientRotation(-math.pi / 2),
        colors: heatmapColors,
        stops: heatmapStops,
      ).createShader(ringRect);

    canvas.drawCircle(center, midRadius, paint);
  }

  /// Soft port/starboard tinting inside the gauge: red on the port (left)
  /// half, green on the starboard (right) half, smoothly fading to fully
  /// transparent across the bow–stern centre line so it reads as a hint
  /// rather than a hard split.
  void _drawPortStarboardWash(
    Canvas canvas,
    Offset center,
    double outerRadius,
  ) {
    final rect = Rect.fromCircle(center: center, radius: outerRadius);
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: const [
          Color(0x33ef4444), // red-500 @ ~20% on far port
          Color(0x14ef4444),
          Color(0x00ffffff), // fully transparent at the centre line
          Color(0x1422c55e),
          Color(0x3322c55e), // green-500 @ ~20% on far starboard
        ],
        stops: const [0.0, 0.30, 0.50, 0.70, 1.0],
      ).createShader(rect);
    canvas.drawCircle(center, outerRadius, paint);
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
    // Stylised yacht silhouette: a sharp bow tapering to a rounded transom,
    // with a thin centre keel line, a deck highlight, and a soft drop shadow
    // so it reads as 3-D rather than a flat triangle.
    final bowY = center.dy - size;
    final sternY = center.dy + size * 0.62;
    final beam = size * 0.36;
    final shoulderY = center.dy - size * 0.05;

    // Curvy hull outline using cubic beziers — sweeps from bow down to the
    // port shoulder, back up to the starboard shoulder, then a flat transom.
    final hull = Path()
      ..moveTo(center.dx, bowY)
      // Port side (left)
      ..cubicTo(
        center.dx - beam * 0.55, bowY + size * 0.35,
        center.dx - beam, shoulderY,
        center.dx - beam * 0.85, sternY,
      )
      // Transom (slight curve)
      ..quadraticBezierTo(
        center.dx, sternY + size * 0.08,
        center.dx + beam * 0.85, sternY,
      )
      // Starboard side (right)
      ..cubicTo(
        center.dx + beam, shoulderY,
        center.dx + beam * 0.55, bowY + size * 0.35,
        center.dx, bowY,
      )
      ..close();

    // Shadow underneath, offset down a hair.
    canvas.save();
    canvas.translate(0, size * 0.04);
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0x1f000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.restore();

    // Hull fill: subtle vertical gradient from light slate to mid slate —
    // keeps the silhouette legible without dominating the gauge.
    final hullRect = Rect.fromLTRB(
      center.dx - beam,
      bowY,
      center.dx + beam,
      sternY + size * 0.1,
    );
    canvas.drawPath(
      hull,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xffe2e8f0), Color(0xff94a3b8)],
        ).createShader(hullRect),
    );

    // Hull outline
    canvas.drawPath(
      hull,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xff475569),
    );
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

    // Wind pointer matches the boat outline colour with a soft halo.
    const lineColor = Color(0xff475569);

    // Glow halo — a wide, blurred, low-alpha line under the main shaft.
    canvas.drawLine(
      center,
      tip,
      Paint()
        ..color = lineColor.withValues(alpha: 0.35)
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Solid black shaft.
    canvas.drawLine(
      center,
      tip,
      Paint()
        ..color = lineColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // Bow tip cap removed for a cleaner pointer.
  }

  @override
  bool shouldRepaint(covariant _WindGaugePainter oldDelegate) {
    return oldDelegate.angleDeg != angleDeg ||
        // Heatmap list is rebuilt as a new object by _rebuildHeatmap;
        // identity check is O(1) and fires only when history actually changes.
        !identical(oldDelegate.heatmapColors, heatmapColors);
  }
}
