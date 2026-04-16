import 'package:ble_application/app/app_dependencies.dart';
import 'package:ble_application/app/ble_gateway_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('welcome flow renders', (tester) async {
    final dependencies = await AppDependencies.standard();
    await tester.pumpWidget(
      BleGatewayApp(dependencies: dependencies),
    );

    expect(find.text('Set up your BLE gateway'), findsOneWidget);
    expect(find.text('Start setup'), findsOneWidget);
  });
}
