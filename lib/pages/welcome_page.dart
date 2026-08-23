import 'package:flutter/material.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({
    super.key,
    required this.onStartSetup,
    required this.onTryDemoMode,
  });

  final VoidCallback onStartSetup;

  /// Skips the gateway pairing flow entirely and drops straight into the
  /// app with simulated sensor data — for trying it out (or developing it)
  /// without real BLE hardware on hand.
  final VoidCallback onTryDemoMode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const Text(
                'Set up your BLE gateway',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              const Text(
                'The app will guide you through connecting to the ESP32, discovering N2K devices, and adding the ones you want on your dashboard.',
                style: TextStyle(fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 24),
              const Text('Flow:'),
              const SizedBox(height: 8),
              const Text('1. Connect to the BLE gateway'),
              const Text('2. Load the N2K device list'),
              const Text('3. Add devices, including the predefined wind page'),
              const Text('4. Continue to the home page'),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onStartSetup,
                  child: const Text('Start setup'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onTryDemoMode,
                  icon: const Icon(Icons.theater_comedy_outlined),
                  label: const Text('Try demo mode instead'),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'See every screen with simulated wind, tank, engine and '
                'navigation data — no gateway required.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}