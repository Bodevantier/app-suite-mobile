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


