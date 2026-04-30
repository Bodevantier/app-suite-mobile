import '../ble/constants.dart';
import '../ble/controllers/ble_gateway_controller.dart';
import '../ble/repositories/ble_gateway_repository.dart';
import '../ble/services/auto_connect_service.dart';
import '../ble/services/ble_gateway_transport.dart';
import '../controllers/app_setup_controller.dart';
import '../controllers/ble_controller.dart';
import '../services/app_preferences_service.dart';
import '../services/wind_averages_service.dart';

class AppDependencies {
  AppDependencies({
    required this.appSetupController,
    required this.telemetryController,
    required this.bleGatewayController,
    required this.preferences,
    required this.autoConnectService,
    required this.windAverages,
  });

  static Future<AppDependencies> standard() async {
    final preferences = await AppPreferencesService.load();

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

    return AppDependencies(
      preferences: preferences,
      appSetupController: AppSetupController(preferences: preferences),
      telemetryController: telemetryController,
      bleGatewayController: BleGatewayController(
        transport: transport,
        repository: repository,
        telemetryController: telemetryController,
        preferences: preferences,
      ),
      autoConnectService: AutoConnectService(transport: transport),
      windAverages: windAverages,
    );
  }

  final AppPreferencesService preferences;
  final AppSetupController appSetupController;
  final BleController telemetryController;
  final BleGatewayController bleGatewayController;
  final AutoConnectService autoConnectService;
  final WindAveragesService windAverages;
}