import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../ble/controllers/ble_gateway_controller.dart';
import '../ble/services/auto_connect_service.dart';
import '../demo/demo_mode_controller.dart';
import '../services/app_preferences_service.dart';
import '../services/night_mode_service.dart';
import 'about_page.dart';
import 'ble_connection_page.dart';

/// App-wide settings — Night Mode, Bluetooth connection management, and an
/// entry point to About. A natural home for any future app-level (rather
/// than per-device) preferences.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.nightMode,
    required this.demoMode,
    required this.bleGatewayController,
    required this.autoConnectService,
    required this.preferences,
  });

  final NightModeService nightMode;
  final DemoModeController demoMode;
  final BleGatewayController bleGatewayController;
  final AutoConnectService autoConnectService;
  final AppPreferencesService preferences;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AnimatedBuilder(
            animation: nightMode,
            builder: (context, _) => _NightModeCard(nightMode: nightMode),
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: Listenable.merge([bleGatewayController, autoConnectService]),
            builder: (context, _) => _BluetoothCard(
              bleGatewayController: bleGatewayController,
              autoConnectService: autoConnectService,
              preferences: preferences,
              demoMode: demoMode,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              subtitle: const Text('Version, build info and Demo Mode'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AboutPage(demoMode: demoMode),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BluetoothCard extends StatelessWidget {
  const _BluetoothCard({
    required this.bleGatewayController,
    required this.autoConnectService,
    required this.preferences,
    required this.demoMode,
  });

  final BleGatewayController bleGatewayController;
  final AutoConnectService autoConnectService;
  final AppPreferencesService preferences;
  final DemoModeController demoMode;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isConnected = bleGatewayController.isConnected;
    final isConnecting = bleGatewayController.isConnecting ||
        (autoConnectService.isRunning &&
            !isConnected &&
            autoConnectService.status.isNotEmpty);

    final Color color;
    final String label;
    final String subtitle;
    if (isConnected) {
      color = Colors.green.shade600;
      label = 'Connected';
      subtitle = 'Tap to view or manage the gateway connection.';
    } else if (isConnecting) {
      color = Colors.orange.shade700;
      label = 'Connecting…';
      subtitle = autoConnectService.status.isNotEmpty
          ? autoConnectService.status
          : 'Connecting to the gateway…';
    } else {
      color = Colors.red.shade400;
      label = 'Offline';
      subtitle = 'Not connected — tap to connect.';
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(Icons.bluetooth, color: color),
        title: const Text('Bluetooth Connection'),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => BleConnectionPage(
                controller: bleGatewayController,
                autoConnectService: autoConnectService,
                preferences: preferences,
                demoModeActive: demoMode.isActive,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NightModeCard extends StatelessWidget {
  const _NightModeCard({required this.nightMode});

  final NightModeService nightMode;

  static String _time(DateTime utc) {
    final local = utc.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  String _statusLine() {
    switch (nightMode.setting) {
      case NightModeSetting.on:
        return 'Always on.';
      case NightModeSetting.off:
        return 'Always off.';
      case NightModeSetting.auto:
        if (nightMode.permissionDenied) {
          return 'Location permission denied — can\'t determine sunrise/sunset.';
        }
        if (!nightMode.hasPosition) {
          return 'Waiting for a location fix…';
        }
        final times = nightMode.todaySunTimes;
        if (times == null) {
          return 'Waiting for a location fix…';
        }
        if (times.alwaysUp) {
          return 'The sun doesn\'t set today at this location — staying in day mode.';
        }
        if (times.alwaysDown) {
          return 'The sun doesn\'t rise today at this location — staying in night mode.';
        }
        final sunrise = times.sunrise;
        final sunset = times.sunset;
        if (sunrise == null || sunset == null) {
          return 'Waiting for a location fix…';
        }
        final fixAgo = nightMode.lastFixAt == null
            ? ''
            : ' · position from ${_relativeAge(nightMode.lastFixAt!)}';
        return 'Today: sunrise ${_time(sunrise)}, sunset ${_time(sunset)}$fixAgo.';
    }
  }

  static String _relativeAge(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = nightMode.isActive;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  active ? Icons.dark_mode : Icons.dark_mode_outlined,
                  color: active ? cs.primary : cs.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Night Mode',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const Spacer(),
                if (active)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'ON',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Switches the whole app to a dim red palette that preserves your '
              'night vision, the same way a chartplotter does.',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 14),
            SegmentedButton<NightModeSetting>(
              segments: const [
                ButtonSegment(
                  value: NightModeSetting.auto,
                  label: Text('Automatic'),
                  icon: Icon(Icons.wb_twilight),
                ),
                ButtonSegment(
                  value: NightModeSetting.on,
                  label: Text('On'),
                  icon: Icon(Icons.nightlight_round),
                ),
                ButtonSegment(
                  value: NightModeSetting.off,
                  label: Text('Off'),
                  icon: Icon(Icons.wb_sunny_outlined),
                ),
              ],
              selected: {nightMode.setting},
              onSelectionChanged: (selection) =>
                  nightMode.setSetting(selection.first),
            ),
            const SizedBox(height: 12),
            Text(
              _statusLine(),
              style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: 0.75)),
            ),
            if (nightMode.setting == NightModeSetting.auto &&
                nightMode.permissionDenied) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Geolocator.openAppSettings(),
                icon: const Icon(Icons.settings_outlined, size: 16),
                label: const Text('Open app settings'),
              ),
            ],
            if (nightMode.setting == NightModeSetting.auto) ...[
              const SizedBox(height: 4),
              Text(
                'Uses your phone\'s last known position only — checked at most '
                'a few times a day to save battery, and never sent anywhere.',
                style: TextStyle(fontSize: 11.5, color: cs.onSurface.withValues(alpha: 0.5)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
