import 'package:flutter/material.dart';

import 'app/app_dependencies.dart';
import 'app/ble_gateway_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = await AppDependencies.standard();
  runApp(BleGatewayApp(dependencies: dependencies));
}