import '../ble/constants.dart';
import '../ble/controllers/ble_gateway_controller.dart';
import '../ble/repositories/ble_gateway_repository.dart';
import '../ble/services/ble_gateway_transport.dart';
import '../controllers/app_setup_controller.dart';
import '../controllers/ble_controller.dart';

class AppDependencies {
  AppDependencies({
    required this.appSetupController,
    required this.telemetryController,
    required this.bleGatewayController,
  });

  factory AppDependencies.standard() {
    final telemetryController = BleController();
    final repository = BleGatewayRepository();
    final transport = BleGatewayTransportService(
      gatewayServiceUuid: bleGatewayServiceUuid,
      notifyCharacteristicUuid: bleNotifyCharacteristicUuid,
      binaryNotifyCharacteristicUuid: bleBinaryNotifyCharacteristicUuid,
      commandCharacteristicUuid: bleCommandCharacteristicUuid,
    );

    return AppDependencies(
      appSetupController: AppSetupController(),
      telemetryController: telemetryController,
      bleGatewayController: BleGatewayController(
        transport: transport,
        repository: repository,
        telemetryController: telemetryController,
      ),
    );
  }

  final AppSetupController appSetupController;
  final BleController telemetryController;
  final BleGatewayController bleGatewayController;
}