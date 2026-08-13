import 'package:flutter/material.dart';

import '../demo/demo_mode_controller.dart';

/// Lets the user simulate a fully connected boat — every sensor, every
/// screen — without a real gateway nearby. Off by default and never
/// persisted: it always starts off on a fresh launch.
///
/// Shown on both the Settings page (the fast path while testing/demoing)
/// and the About page (where the rest of the app's diagnostic info lives).
class DemoModeCard extends StatelessWidget {
  const DemoModeCard({super.key, required this.demoMode});

  final DemoModeController demoMode;

  Future<void> _onChanged(bool value) async {
    if (value) {
      await demoMode.enable();
    } else {
      demoMode.disable();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: demoMode,
      builder: (context, _) {
        final active = demoMode.isActive;
        final cs = Theme.of(context).colorScheme;
        return Card(
          elevation: 0,
          color: active ? cs.primaryContainer.withValues(alpha: 0.35) : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: active
                  ? cs.primary.withValues(alpha: 0.4)
                  : cs.outline.withValues(alpha: 0.2),
            ),
          ),
          child: SwitchListTile(
            value: active,
            onChanged: _onChanged,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            secondary: Icon(
              Icons.theater_comedy_outlined,
              color: active ? cs.primary : cs.onSurface.withValues(alpha: 0.6),
            ),
            title: const Text(
              'Demo Mode',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              active
                  ? 'Showing simulated wind, temperature, tank and engine data — turn off to use a real gateway.'
                  : 'See every screen with simulated sensors — no gateway required.',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7)),
            ),
          ),
        );
      },
    );
  }
}
