import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A small dot that pulses smoothly to show "I'm alive" activity.
///
/// The pulse intensity (brightness, glow, amplitude) decays smoothly as time
/// since [lastEventAt] grows. When fully stale the dot turns into a dim, still
/// circle in [inactiveColor]. When a new event arrives (i.e. [lastEventAt]
/// advances) the dot lights up again — the transition is implicit and smooth
/// because it is driven by elapsed time, not by discrete state changes.
///
/// A `null` [lastEventAt] is treated as "no activity yet" → fully stale.
class LiveActivityIndicator extends StatefulWidget {
  const LiveActivityIndicator({
    super.key,
    required this.lastEventAt,
    this.staleAfter = const Duration(seconds: 8),
    this.size = 9,
    this.activeColor = const Color(0xFF22C55E), // green-500
    this.inactiveColor = const Color(0xFF9CA3AF), // gray-400
    this.pulsePeriod = const Duration(milliseconds: 2200),
  });

  /// Timestamp of the most recent data event for this entity.
  final DateTime? lastEventAt;

  /// After this much time without new events, the dot is fully stale.
  final Duration staleAfter;

  /// Diameter of the dot in logical pixels.
  final double size;

  /// Color when activity is fresh.
  final Color activeColor;

  /// Color when activity is fully stale.
  final Color inactiveColor;

  /// Period of one full pulse cycle when activity is fresh.
  final Duration pulsePeriod;

  @override
  State<LiveActivityIndicator> createState() => _LiveActivityIndicatorState();
}

class _LiveActivityIndicatorState extends State<LiveActivityIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.pulsePeriod,
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant LiveActivityIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsePeriod != oldWidget.pulsePeriod) {
      _controller.duration = widget.pulsePeriod;
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Returns 0..1: 1 means just-received, 0 means fully stale.
  double _freshness() {
    final last = widget.lastEventAt;
    if (last == null) return 0;
    final elapsedMs =
        DateTime.now().difference(last).inMilliseconds.toDouble();
    final staleMs = widget.staleAfter.inMilliseconds.toDouble();
    if (elapsedMs <= 0) return 1;
    if (elapsedMs >= staleMs) return 0;
    // Smoothly ease the decay so the falloff feels gentle rather than linear.
    final linear = 1.0 - (elapsedMs / staleMs);
    return Curves.easeOut.transform(linear);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final freshness = _freshness();
        // Smooth sine pulse, normalised to 0..1.
        final pulse = (math.sin(_controller.value * 2 * math.pi) + 1) / 2;
        // Very gentle brightness modulation — the dot stays mostly steady,
        // only "breathing" subtly when activity is fresh.
        final modulated = 0.78 + 0.22 * pulse * freshness;

        final color = Color.lerp(
          widget.inactiveColor.withValues(alpha: 0.45),
          widget.activeColor,
          freshness,
        )!;

        // Soft halo, no hard glow.
        final glowColor = widget.activeColor.withValues(
          alpha: 0.18 * freshness,
        );
        final glowBlur = widget.size * 0.9 * freshness;

        // Almost no size change — keeps it calm in the periphery.
        final scale = 0.96 + 0.06 * pulse * freshness;

        return SizedBox(
          width: widget.size * 1.8,
          height: widget.size * 1.8,
          child: Center(
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: modulated),
                  boxShadow: freshness <= 0.05
                      ? null
                      : <BoxShadow>[
                          BoxShadow(
                            color: glowColor,
                            blurRadius: glowBlur,
                            spreadRadius: 0,
                          ),
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
