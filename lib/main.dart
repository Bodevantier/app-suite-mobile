import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'app/app_dependencies.dart';
import 'app/ble_gateway_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterBluePlus.setLogLevel(LogLevel.none);
  final dependencies = await AppDependencies.standard();
  runApp(BleGatewayApp(dependencies: dependencies));
}