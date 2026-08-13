import '../ble/constants.dart';
import '../ble/controllers/ble_gateway_controller.dart';
import '../ble/repositories/ble_gateway_repository.dart';
import '../ble/services/auto_connect_service.dart';
import '../ble/services/ble_gateway_transport.dart';
import '../controllers/app_setup_controller.dart';
import '../controllers/ble_controller.dart';
import '../demo/demo_mode_controller.dart';
import '../services/app_preferences_service.dart';
import '../services/night_mode_service.dart';
import '../services/node_settings_service.dart';
import '../services/temperature_history_service.dart';
import '../services/wind_angle_history_service.dart';
import '../services/wind_averages_service.dart';

class AppDependencies {
  AppDependencies({
    required this.appSetupController,
    required this.telemetryController,
    required this.bleGatewayController,
    required this.preferences,
    required this.autoConnectService,
    required this.windAverages,
    required this.temperatureHistory,
    required this.windAngleHistory,
    required this.nodeSettings,
    required this.demoMode,
    required this.nightMode,
  });

  static Future<AppDependencies> standard() async {
    final preferences = await AppPreferencesService.load();
    final nodeSettings = await NodeSettingsService.load();

    final telemetryController = BleController();
    final repository = BleGatewayRepository();
    final transport = BleGatewayTransportService(
      gatewayServiceUuid: bleGatewayServiceUuid,
      notifyCharacteristicUuid: bleNotifyCharacteristicUuid,
      binaryNotifyCharacteristicUuid: bleBinaryNotifyCharacteristicUuid,
      commandCharacteristicUuid: bleCommandCharacteristicUuid,
    );

    // Pre-populate repository from cache so the UI is useful before connecting.
    final cached = preferences.cachedN2kDevices;
    if (cached.isNotEmpty) {
      repository.seedDevices(cached);
    }

    // Auto-save the N2K device list whenever a new snapshot completes.
    repository.addListener(() {
      final devices = repository.devices;
      if (devices.isNotEmpty && !repository.snapshotInProgress) {
        preferences.saveCachedN2kDevices(devices.toList());
      }
    });

    // Wind averages service — seed from persisted samples + session counters.
    final windAverages = WindAveragesService();
    windAverages.seedFromJson(
      twsSamples: preferences.windTwsSamples,
      awsSamples: preferences.windAwsSamples,
    );
    windAverages.seedSessionFromJson(preferences.windSession);

    // Feed wind averages on every telemetry update; persist every 30 samples.
    var unsavedSamples = 0;
    telemetryController.addListener(() {
      final t = telemetryController.telemetry;
      if (t.updatedAt == null) return;
      if (t.apparentWindSpeedMs == null) return;
      windAverages.addSample(
        twsMs: t.effectiveTrueWindSpeedMs,
        awsMs: t.apparentWindSpeedMs,
        twaDeg: t.effectiveTrueWindAngleDeg,
        sogMs: t.sogMs,
        headingDeg: t.headingDeg,
        timestamp: t.updatedAt,
      );
      unsavedSamples++;
      if (unsavedSamples >= 30) {
        unsavedSamples = 0;
        preferences.saveWindSamples(
          tws: windAverages.twsToJson(),
          aws: windAverages.awsToJson(),
        );
        preferences.saveWindSession(windAverages.sessionToJson());
      }
    });

    // Temperature log + wind angle trail — app-wide so both keep logging
    // regardless of which page (if any) is currently open.
    final temperatureHistory = TemperatureHistoryService();
    temperatureHistory.seedRecordsFromJson(preferences.tempRecords);
    final windAngleHistory = WindAngleHistoryService();
    telemetryController.addListener(() {
      for (final device in telemetryController.decodedDevices) {
        if (!device.isTemperatureDevice) continue;
        final t = telemetryController.telemetryFor(device.sourceAddress);
        if (t.temperatureC == null) continue;
        final recordChanged = temperatureHistory.addSample(
          device.sourceAddress,
          t.temperatureC!,
          t.updatedAt ?? DateTime.now(),
        );
        if (recordChanged) {
          preferences.saveTempRecords(temperatureHistory.recordsToJson());
        }
      }
      final t = telemetryController.telemetry;
      windAngleHistory.addSample(
        apparentDeg: t.apparentWindAngleDeg,
        trueDeg: t.effectiveTrueWindAngleDeg,
        timestamp: t.updatedAt,
      );
    });

    // Kick off auto-connect right now rather than waiting for BleGatewayApp
    // to mount after the splash screen — dependency construction happens in
    // parallel with the splash animation, so starting the connect attempt
    // here lets that otherwise-idle time double as connect time instead of
    // only starting once the user is already looking at the home screen.
    final autoConnectService = AutoConnectService(transport: transport);
    final knownGatewayId = preferences.knownGatewayId;
    if (knownGatewayId != null) {
      autoConnectService.start(knownGatewayId);
    }

    final bleGatewayController = BleGatewayController(
      transport: transport,
      repository: repository,
      telemetryController: telemetryController,
      preferences: preferences,
    );

    return AppDependencies(
      preferences: preferences,
      appSetupController: AppSetupController(preferences: preferences),
      telemetryController: telemetryController,
      bleGatewayController: bleGatewayController,
      autoConnectService: autoConnectService,
      windAverages: windAverages,
      temperatureHistory: temperatureHistory,
      windAngleHistory: windAngleHistory,
      nodeSettings: nodeSettings,
      demoMode: DemoModeController(
        bleGatewayController: bleGatewayController,
        telemetryController: telemetryController,
        autoConnectService: autoConnectService,
        preferences: preferences,
      ),
      // Constructing this only loads persisted state (no I/O, no location
      // request) — safe to build in the headless BLE-wake isolate too.
      // NightModeService.startForeground() is what actually starts the
      // recheck loop / location refresh, and must only be called by the
      // visible app (see BleGatewayApp).
      nightMode: NightModeService(preferences: preferences),
    );
  }

  final AppPreferencesService preferences;
  final AppSetupController appSetupController;
  final BleController telemetryController;
  final BleGatewayController bleGatewayController;
  final AutoConnectService autoConnectService;
  final WindAveragesService windAverages;
  final TemperatureHistoryService temperatureHistory;
  final WindAngleHistoryService windAngleHistory;
  final NodeSettingsService nodeSettings;
  final DemoModeController demoMode;
  final NightModeService nightMode;
}