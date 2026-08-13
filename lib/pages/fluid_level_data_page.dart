import 'package:flutter/material.dart';

import '../controllers/ble_controller.dart';
import '../models/n2k_device_info.dart';
import '../models/node_settings.dart';
import '../n2k/fluid_icons.dart';
import '../services/node_settings_service.dart';
import 'node_settings_page.dart';

/// Live view for an NMEA 2000 Fluid Level (PGN 127505) source — water,
/// fuel, waste, oil, etc. Displays percentage, fluid type, tank instance
/// and capacity (when reported), plus an animated tank-fill visualisation.
class FluidLevelDataPage extends StatelessWidget {
  const FluidLevelDataPage({
    super.key,
    required this.telemetryController,
    this.device,
    this.settingsService,
    this.primaryActionLabel,
    this.onPrimaryAction,
  });

  final BleController telemetryController;
  final N2kDeviceInfo? device;
  final NodeSettingsService? settingsService;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;

  void _openSettings(BuildContext context) {
    if (device == null || settingsService == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NodeSettingsPage(
          device: device!,
          settingsService: settingsService!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsListenable = settingsService;
    final hasSettings = device != null && settingsService != null;
    return Scaffold(
      backgroundColor: const Color(0xfff5f7fb),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: const Color(0xfff5f7fb),
        title: AnimatedBuilder(
          animation: settingsListenable ?? const _NeverNotifier(),
          builder: (context, _) {
            final overrideName = device != null && settingsService != null
                ? settingsService!.forDevice(device!).customName
                : null;
            final title = (overrideName != null && overrideName.trim().isNotEmpty)
                ? overrideName
                : (device?.displayName ?? 'Fluid Level');
            return Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: Color(0xff000000),
              ),
            );
          },
        ),
        actions: [
          if (hasSettings)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Device settings',
              onPressed: () => _openSettings(context),
            ),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([
            telemetryController,
            ?settingsListenable,
          ]),
          builder: (context, _) {
            // With several tank sensors on the bus, the boat-wide telemetry
            // holds whichever tank transmitted last. This page is opened for
            // one node, so read only that node's own telemetry.
            final telemetry = device != null
                ? telemetryController.telemetryFor(device!.sourceAddress)
                : telemetryController.telemetry;
            final settings = (device != null && settingsService != null)
                ? settingsService!.forDevice(device!)
                : NodeSettings.empty;
            final levelPct = telemetry.fluidLevelPct;
            final fluidType = telemetry.fluidType;
            final capacityL = telemetry.fluidCapacityL;
            final showAlarm = settings.lowLevelAlarmEnabled &&
                levelPct != null &&
                levelPct <= settings.lowLevelAlarmPct;
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showAlarm) ...[
                    _LowLevelBanner(thresholdPct: settings.lowLevelAlarmPct),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
                    child: _FluidLevelCard(
                      levelPct: levelPct,
                      fluidType: settings.customFluidTypeLabel ?? fluidType,
                      capacityL: settings.customCapacityL ?? capacityL,
                    ),
                  ),
                  if (primaryActionLabel != null) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onPrimaryAction,
                        child: Text(primaryActionLabel!),
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

class _LowLevelBanner extends StatelessWidget {
  const _LowLevelBanner({required this.thresholdPct});
  final double thresholdPct;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xfffee2e2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xfffca5a5), width: 1.2),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xffb91c1c),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Low level — below ${thresholdPct.round()} % threshold',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xff7f1d1d),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Trivial Listenable that never fires — used to keep AnimatedBuilder happy
/// when no settings service is provided.
class _NeverNotifier extends Listenable {
  const _NeverNotifier();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

class _FluidLevelCard extends StatelessWidget {
  const _FluidLevelCard({
    this.levelPct,
    this.fluidType,
    this.capacityL,
  });

  final double? levelPct;
  final String? fluidType;
  final double? capacityL;

  @override
  Widget build(BuildContext context) {
    if (levelPct == null) {
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
                'Waiting for tank-level sensor',
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

    final pct = levelPct!.clamp(0.0, 100.0);
    final liquidColor = colorForFluidType(fluidType);
    // Approximate volume (L) when capacity is known.
    final volumeL = (capacityL != null) ? (capacityL! * pct / 100.0) : null;

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
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (fluidType != null) ...[
            Text(
              fluidType!,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xff334155),
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 4),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 0.55,
                child: _AnimatedTank(
                  levelPct: pct,
                  liquidColor: liquidColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${pct.round()} %',
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w800,
              color: Color(0xff0f172a),
              letterSpacing: -1,
            ),
          ),
          if (volumeL != null) ...[
            const SizedBox(height: 4),
            Text(
              '${volumeL.round()} / ${capacityL!.round()} L',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xff475569),
              ),
            ),
          ] else if (capacityL != null) ...[
            const SizedBox(height: 4),
            Text(
              'Capacity ${capacityL!.round()} L',
              style: const TextStyle(
                fontSize: 14,
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

/// Stylised tank with an animated fill level. The fill height is animated
/// smoothly when [levelPct] changes so brief noise does not look jumpy.
class _AnimatedTank extends StatelessWidget {
  const _AnimatedTank({required this.levelPct, required this.liquidColor});

  final double levelPct;
  final Color liquidColor;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: levelPct, end: levelPct),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return CustomPaint(
          painter: _TankPainter(
            levelPct: value,
            liquidColor: liquidColor,
          ),
        );
      },
    );
  }
}

class _TankPainter extends CustomPainter {
  _TankPainter({required this.levelPct, required this.liquidColor});

  final double levelPct;
  final Color liquidColor;

  @override
  void paint(Canvas canvas, Size size) {
    const wallStroke = 4.0;
    final outer = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        wallStroke / 2,
        wallStroke / 2,
        size.width - wallStroke,
        size.height - wallStroke,
      ),
      const Radius.circular(20),
    );

    // Liquid fill clipped to inner area.
    final inner = Rect.fromLTWH(
      wallStroke,
      wallStroke,
      size.width - wallStroke * 2,
      size.height - wallStroke * 2,
    );
    final fillHeight = inner.height * (levelPct / 100.0);
    final fillRect = Rect.fromLTWH(
      inner.left,
      inner.bottom - fillHeight,
      inner.width,
      fillHeight,
    );

    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(inner, const Radius.circular(16)),
    );

    // Background subtle gradient.
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xfff1f5f9), Color(0xffe2e8f0)],
      ).createShader(inner);
    canvas.drawRect(inner, bgPaint);

    if (fillHeight > 0) {
      final liquidPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            liquidColor.withValues(alpha: 0.85),
            liquidColor,
          ],
        ).createShader(fillRect);
      canvas.drawRect(fillRect, liquidPaint);

      // Surface highlight line.
      final surfacePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..strokeWidth = 1.2;
      canvas.drawLine(
        Offset(fillRect.left, fillRect.top),
        Offset(fillRect.right, fillRect.top),
        surfacePaint,
      );
    }

    // Tick marks at 25 / 50 / 75 %.
    final tickPaint = Paint()
      ..color = const Color(0xff94a3b8).withValues(alpha: 0.55)
      ..strokeWidth = 1;
    final tickTextStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: const Color(0xff64748b).withValues(alpha: 0.85),
    );
    for (final p in const [25, 50, 75]) {
      final y = inner.bottom - inner.height * (p / 100.0);
      canvas.drawLine(
        Offset(inner.left, y),
        Offset(inner.left + 8, y),
        tickPaint,
      );
      canvas.drawLine(
        Offset(inner.right - 8, y),
        Offset(inner.right, y),
        tickPaint,
      );
      final tp = TextPainter(
        text: TextSpan(text: '$p%', style: tickTextStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(inner.right - 12 - tp.width, y - tp.height - 2),
      );
    }

    canvas.restore();

    // Tank wall.
    final wallPaint = Paint()
      ..color = const Color(0xff94a3b8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = wallStroke;
    canvas.drawRRect(outer, wallPaint);
  }

  @override
  bool shouldRepaint(covariant _TankPainter old) {
    return old.levelPct != levelPct || old.liquidColor != liquidColor;
  }
}
