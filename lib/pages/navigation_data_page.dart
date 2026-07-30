import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/ble_controller.dart';
import '../models/n2k_device_info.dart';
import '../services/node_settings_service.dart';
import 'node_settings_page.dart';

class NavigationDataPage extends StatelessWidget {
  const NavigationDataPage({
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
    final hasSettings = device != null && settingsService != null;
    final overrideName = hasSettings
        ? settingsService!.forDevice(device!).customName
        : null;
    final title = (overrideName != null && overrideName.trim().isNotEmpty)
        ? overrideName
        : (device?.displayName ?? 'Navigation');
    return Scaffold(
      backgroundColor: const Color(0xfff5f7fb),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: const Color(0xfff5f7fb),
        title: Text(
          title,
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
              onPressed: () => _openSettings(context),
            ),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: telemetryController,
          builder: (context, _) {
            final telemetry = telemetryController.telemetry;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // COG/SOG compass card
                  _CompassCard(
                    cogDeg: telemetry.cogDeg,
                    sogMs: telemetry.sogMs,
                  ),
                  const SizedBox(height: 14),
                  // Position card
                  _PositionCard(
                    latitude: telemetry.latitude,
                    longitude: telemetry.longitude,
                  ),
                  const SizedBox(height: 14),
                  // GPS signal quality card
                  _GpsSignalCard(
                    hdop: telemetry.hdop,
                    vdop: telemetry.vdop,
                    magneticVariationDeg: telemetry.magneticVariationDeg,
                    gnssAltitudeM: telemetry.gnssAltitudeM,
                    gnssSatellites: telemetry.gnssSatellites,
                    gnssFixType: telemetry.gnssFixType,
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

class _CompassCard extends StatelessWidget {
  const _CompassCard({this.cogDeg, this.sogMs});
  final double? cogDeg;
  final double? sogMs;

  @override
  Widget build(BuildContext context) {
    final cogText = cogDeg != null ? '${cogDeg!.toStringAsFixed(1)}°' : '--';
    final sogKnots = sogMs != null ? sogMs! * 1.94384 : null;
    final sogText = sogKnots != null ? '${sogKnots.toStringAsFixed(1)} kn' : '--';

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
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _CompassRose(cogDeg: cogDeg),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _DataCell(label: 'COG', value: cogText),
              _DataCell(label: 'SOG', value: sogText),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompassRose extends StatelessWidget {
  const _CompassRose({this.cogDeg});
  final double? cogDeg;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 160,
      child: CustomPaint(
        painter: _CompassPainter(cogDeg: cogDeg),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  const _CompassPainter({this.cogDeg});
  final double? cogDeg;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Background circle
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xffe8eef8)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xff8ca6e0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Cardinal direction labels
    const labels = ['N', 'E', 'S', 'W'];
    const angles = [0.0, 90.0, 180.0, 270.0];
    const labelPaints = [
      Color(0xffe63939), // N = red
      Color(0xff374151),
      Color(0xff374151),
      Color(0xff374151),
    ];
    for (var i = 0; i < labels.length; i++) {
      final rad = (angles[i] - 90) * math.pi / 180;
      final labelRadius = radius * 0.72;
      final pos = Offset(
        center.dx + labelRadius * math.cos(rad),
        center.dy + labelRadius * math.sin(rad),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: labelPaints[i],
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        pos - Offset(tp.width / 2, tp.height / 2),
      );
    }

    // Tick marks
    for (var i = 0; i < 36; i++) {
      final rad = (i * 10.0 - 90) * math.pi / 180;
      final isMajor = i % 9 == 0;
      final innerR = radius * (isMajor ? 0.82 : 0.88);
      final outerR = radius * 0.95;
      canvas.drawLine(
        Offset(center.dx + innerR * math.cos(rad),
               center.dy + innerR * math.sin(rad)),
        Offset(center.dx + outerR * math.cos(rad),
               center.dy + outerR * math.sin(rad)),
        Paint()
          ..color = const Color(0xff8ca6e0)
          ..strokeWidth = isMajor ? 2 : 1,
      );
    }

    // COG arrow
    if (cogDeg != null) {
      final cogRad = (cogDeg! - 90) * math.pi / 180;
      final arrowLength = radius * 0.60;
      final tipX = center.dx + arrowLength * math.cos(cogRad);
      final tipY = center.dy + arrowLength * math.sin(cogRad);

      final arrowPaint = Paint()
        ..color = const Color(0xff1d4ed8)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(center, Offset(tipX, tipY), arrowPaint);

      // Arrowhead
      const headLen = 12.0;
      const headAngle = 0.45; // ~26°
      canvas.drawLine(
        Offset(tipX, tipY),
        Offset(
          tipX - headLen * math.cos(cogRad - headAngle),
          tipY - headLen * math.sin(cogRad - headAngle),
        ),
        arrowPaint,
      );
      canvas.drawLine(
        Offset(tipX, tipY),
        Offset(
          tipX - headLen * math.cos(cogRad + headAngle),
          tipY - headLen * math.sin(cogRad + headAngle),
        ),
        arrowPaint,
      );

      // Small tail
      const tailLen = 15.0;
      canvas.drawLine(
        center,
        Offset(
          center.dx - tailLen * math.cos(cogRad),
          center.dy - tailLen * math.sin(cogRad),
        ),
        Paint()
          ..color = const Color(0xff93c5fd)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    } else {
      // No data indicator
      final tp = TextPainter(
        text: const TextSpan(
          text: '?',
          style: TextStyle(color: Color(0xffadb5bd), fontSize: 36),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_CompassPainter old) => old.cogDeg != cogDeg;
}

class _PositionCard extends StatelessWidget {
  const _PositionCard({this.latitude, this.longitude});
  final double? latitude;
  final double? longitude;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xffffffff),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffdfe5ef), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Position',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: Color(0xff374151),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 18, color: Color(0xff6b7280)),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PositionRow(label: 'Latitude', value: _formatLat(latitude)),
                    const SizedBox(height: 6),
                    _PositionRow(label: 'Longitude', value: _formatLon(longitude)),
                  ],
                ),
              ),
            ],
          ),
          if (latitude != null && longitude != null) ...[
            const SizedBox(height: 10),
            SelectableText(
              '${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xff9ca3af),
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatLat(double? lat) {
    if (lat == null) return '--';
    final dir = lat >= 0 ? 'N' : 'S';
    final abs = lat.abs();
    final deg = abs.floor();
    final min = (abs - deg) * 60;
    return '$deg° ${min.toStringAsFixed(3)}\' $dir';
  }

  String _formatLon(double? lon) {
    if (lon == null) return '--';
    final dir = lon >= 0 ? 'E' : 'W';
    final abs = lon.abs();
    final deg = abs.floor();
    final min = (abs - deg) * 60;
    return '$deg° ${min.toStringAsFixed(3)}\' $dir';
  }
}

class _PositionRow extends StatelessWidget {
  const _PositionRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xff6b7280),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xff111827),
          ),
        ),
      ],
    );
  }
}

class _DataCell extends StatelessWidget {
  const _DataCell({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xff6b7280),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Color(0xff111827),
          ),
        ),
      ],
    );
  }
}

// ── GPS Signal card ──────────────────────────────────────────────────────────

class _GpsSignalCard extends StatelessWidget {
  const _GpsSignalCard({
    this.hdop,
    this.vdop,
    this.magneticVariationDeg,
    this.gnssAltitudeM,
    this.gnssSatellites,
    this.gnssFixType,
  });

  final double? hdop;
  final double? vdop;
  final double? magneticVariationDeg;
  final double? gnssAltitudeM;
  final int? gnssSatellites;
  final String? gnssFixType;

  String _dop(double? v) => v != null ? v.toStringAsFixed(2) : '--';

  String _alt(double? v) => v != null ? '${v.toStringAsFixed(1)} m' : '--';

  String _variation(double? v) {
    if (v == null) return '--';
    final sign = v >= 0 ? '+' : '';
    final dir = v >= 0 ? 'E' : 'W';
    return '$sign${v.toStringAsFixed(1)}° $dir';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xffffffff),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffdfe5ef), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.satellite_alt_outlined,
                  size: 18, color: Color(0xff6b7280)),
              const SizedBox(width: 6),
              const Text(
                'GPS Signal',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Color(0xff374151),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _GpsRow(
                  label: 'Fix',
                  value: gnssFixType ?? '--',
                ),
              ),
              Expanded(
                child: _GpsRow(
                  label: 'Satellites',
                  value: gnssSatellites != null ? '$gnssSatellites' : '--',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _GpsRow(label: 'HDOP', value: _dop(hdop))),
              Expanded(child: _GpsRow(label: 'VDOP', value: _dop(vdop))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _GpsRow(label: 'Altitude', value: _alt(gnssAltitudeM))),
              Expanded(
                child: _GpsRow(
                  label: 'Variation',
                  value: _variation(magneticVariationDeg),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GpsRow extends StatelessWidget {
  const _GpsRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xff6b7280),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xff111827),
          ),
        ),
      ],
    );
  }
}
