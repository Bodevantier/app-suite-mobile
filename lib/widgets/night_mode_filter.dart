import 'package:flutter/material.dart';

import '../services/night_mode_service.dart';

/// Applies a marine-instrument-style "red night mode" over [child]: the
/// whole app is inverted (light backgrounds become dark) and desaturated
/// down to the red channel only (no green, no blue), the same trick
/// chartplotters and aviation panels use to preserve night-adapted (rod)
/// vision. Because it works as a pixel filter over the already-built UI, it
/// applies uniformly to every screen — including ones that hardcode a light
/// palette — with no per-page changes.
class NightModeFilter extends StatelessWidget {
  const NightModeFilter({
    super.key,
    required this.nightMode,
    required this.child,
  });

  final NightModeService nightMode;
  final Widget child;

  // 4x5 matrix, rows are R'/G'/B'/A' = row · [R, G, B, A, 1] (0-255 space).
  // R' = 255 - luminance(R,G,B): inverts brightness so a light UI becomes a
  // dark one. G' and B' are pinned to 0 so nothing but red is ever emitted.
  static const ColorFilter _redInvert = ColorFilter.matrix(<double>[
    -0.299, -0.587, -0.114, 0, 255,
    0, 0, 0, 0, 0,
    0, 0, 0, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: nightMode,
      builder: (context, _) {
        if (!nightMode.isActive) return child;
        return ColorFiltered(colorFilter: _redInvert, child: child);
      },
    );
  }
}
