import 'package:flutter/material.dart';

import 'app/app_dependencies.dart';
import 'app/ble_gateway_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(BleGatewayApp(dependencies: AppDependencies.standard()));
}