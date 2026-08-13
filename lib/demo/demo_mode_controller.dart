import 'package:flutter/foundation.dart';

import '../ble/controllers/ble_gateway_controller.dart';
import '../ble/services/auto_connect_service.dart';
import '../controllers/ble_controller.dart';
import '../services/app_preferences_service.dart';
import '../services/dashboard_layout_service.dart';
import 'demo_dashboard_seed.dart';
import 'demo_data_service.dart';

/// Turns Demo Mode on/off — lets someone see every screen populated with
/// simulated wind/temperature/engine/tank/navigation data without a real
/// gateway, for showing off the app. Off by default; the user must switch it
/// on from the About page, and it never persists across an app restart.
class DemoModeController extends ChangeNotifier {
  DemoModeController({
    required this.bleGatewayController,
    required this.telemetryController,
    required this.autoConnectService,
    required this.preferences,
    required this.dashboards,
  }) : _demoData = DemoDataService(telemetryController: telemetryController);

  final BleGatewayController bleGatewayController;
  final BleController telemetryController;
  final AutoConnectService autoConnectService;
  final AppPreferencesService preferences;
  final DashboardLayoutService dashboards;
  final DemoDataService _demoData;

  bool _isActive = false;
  bool get isActive => _isActive;

  Future<void> enable() async {
    if (_isActive) return;
    if (bleGatewayController.isConnected) {
      autoConnectService.pause();
      await bleGatewayController.disconnect();
    }
    telemetryController.reset();
    bleGatewayController.setDemoMode(true);
    // Demo dashboards are a separate set from the real boat's — switch to
    // them so building/testing a layout here can't collide with (or leak
    // into) the real setup. The first time ever, populate it with a curated
    // Sailing/Motoring/Anchored/Docked showcase rather than leaving it empty.
    dashboards.setDemoMode(true);
    await seedDefaultDemoDashboards(dashboards);
    _demoData.start();
    _isActive = true;
    notifyListeners();
  }

  void disable() {
    if (!_isActive) return;
    _demoData.stop();
    bleGatewayController.setDemoMode(false);
    dashboards.setDemoMode(false);
    telemetryController.reset();
    _isActive = false;
    notifyListeners();
    // Resume the normal auto-connect behaviour the user had before demo mode.
    final knownId = preferences.knownGatewayId;
    if (knownId != null) {
      if (autoConnectService.isRunning) {
        autoConnectService.retryNow();
      } else {
        autoConnectService.start(knownId);
      }
    }
  }

  @override
  void dispose() {
    _demoData.stop();
    super.dispose();
  }
}
