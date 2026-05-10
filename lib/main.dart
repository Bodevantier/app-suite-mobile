import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'app/app_dependencies.dart';
import 'app/ble_gateway_app.dart';
import 'pages/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  FlutterBluePlus.setLogLevel(LogLevel.none);
  // Start loading dependencies immediately — in parallel with the splash animation.
  runApp(_AppLoader(dependenciesFuture: AppDependencies.standard()));
}

/// Shows the splash animation while dependencies load in the background.
/// Transitions to [BleGatewayApp] once both the animation is done AND
/// dependencies are ready (whichever takes longer).
class _AppLoader extends StatefulWidget {
  const _AppLoader({required this.dependenciesFuture});

  final Future<AppDependencies> dependenciesFuture;

  @override
  State<_AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<_AppLoader> {
  AppDependencies? _dependencies;
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    widget.dependenciesFuture.then((deps) {
      if (mounted) setState(() => _dependencies = deps);
    });
  }

  void _onSplashDone() => setState(() => _splashDone = true);

  @override
  Widget build(BuildContext context) {
    final deps = _dependencies;
    if (_splashDone && deps != null) {
      return BleGatewayApp(dependencies: deps);
    }
    // Keep showing the splash until both conditions are met.
    // If the animation finishes before deps load, show a plain white screen.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _splashDone
          ? const Scaffold(backgroundColor: Colors.white)
          : SplashScreen(onFinished: _onSplashDone),
    );
  }
}