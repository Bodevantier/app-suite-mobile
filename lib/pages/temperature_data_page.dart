import 'package:flutter/material.dart';

import '../controllers/ble_controller.dart';
import '../models/n2k_device_info.dart';

class TemperatureDataPage extends StatelessWidget {
  const TemperatureDataPage({
    super.key,
    required this.telemetryController,
    this.device,
    this.primaryActionLabel,
    this.onPrimaryAction,
  });

  final BleController telemetryController;
  final N2kDeviceInfo? device;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff5f7fb),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: const Color(0xfff5f7fb),
        title: Text(
          device?.displayName ?? 'Temperature',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: Color(0xff000000),
          ),
        ),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: telemetryController,
          builder: (context, _) {
            final telemetry = telemetryController.telemetry;
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (device != null) ...[
                    _DeviceHeader(device: device!),
                    const SizedBox(height: 14),
                  ],
                  Expanded(
                    child: _TemperatureCard(
                      temperatureC: telemetry.temperatureC,
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

class _DeviceHeader extends StatelessWidget {
  const _DeviceHeader({required this.device});
  final N2kDeviceInfo device;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xffffffff),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffdfe5ef), width: 1.2),
      ),
      child: Text(
        device.displayName,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 16,
          color: Color(0xff0f172a),
        ),
      ),
    );
  }
}

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
    final fahrenheit = celsius * 9 / 5 + 32;
    final color = _tempColor(celsius);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withAlpha(20),
            color.withAlpha(40),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withAlpha(80), width: 1.2),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.thermostat_rounded,
            size: 56,
            color: color,
          ),
          const SizedBox(height: 20),
          Text(
            '${celsius.toStringAsFixed(1)} °C',
            style: TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${fahrenheit.toStringAsFixed(1)} °F',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w500,
              color: Color(0xff64748b),
            ),
          ),
          const SizedBox(height: 24),
          _StatusBadge(celsius: celsius),
        ],
      ),
    );
  }

  Color _tempColor(double celsius) {
    if (celsius < 0) return const Color(0xff3b82f6);
    if (celsius < 10) return const Color(0xff06b6d4);
    if (celsius < 20) return const Color(0xff10b981);
    if (celsius < 30) return const Color(0xfff59e0b);
    if (celsius < 40) return const Color(0xffef4444);
    return const Color(0xffdc2626);
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.celsius});
  final double celsius;

  String get _label {
    if (celsius < 0) return 'Below freezing';
    if (celsius < 10) return 'Cold';
    if (celsius < 20) return 'Cool';
    if (celsius < 30) return 'Warm';
    if (celsius < 40) return 'Hot';
    return 'Very hot';
  }

  Color get _color {
    if (celsius < 0) return const Color(0xff3b82f6);
    if (celsius < 10) return const Color(0xff06b6d4);
    if (celsius < 20) return const Color(0xff10b981);
    if (celsius < 30) return const Color(0xfff59e0b);
    if (celsius < 40) return const Color(0xffef4444);
    return const Color(0xffdc2626);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withAlpha(20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _color.withAlpha(80), width: 1.2),
      ),
      child: Text(
        _label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _color,
        ),
      ),
    );
  }
}
