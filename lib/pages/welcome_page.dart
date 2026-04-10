import 'package:flutter/material.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, required this.onStartSetup});

  final VoidCallback onStartSetup;

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
            ],
          ),
        ),
      ),
    );
  }
}