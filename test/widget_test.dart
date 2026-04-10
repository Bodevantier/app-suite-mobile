import 'package:ble_application/app/app_dependencies.dart';
import 'package:ble_application/app/ble_gateway_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('welcome flow renders', (tester) async {
    await tester.pumpWidget(
      BleGatewayApp(dependencies: AppDependencies.standard()),
    );

    expect(find.text('Set up your BLE gateway'), findsOneWidget);
    expect(find.text('Start setup'), findsOneWidget);
  });
}
