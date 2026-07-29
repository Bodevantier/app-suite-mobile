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
  // Must be called before any other FlutterBluePlus method. Opts into iOS/
  // macOS CoreBluetooth state restoration (CBCentralManagerOptionRestore
  // IdentifierKey) so a previously-connected gateway can reconnect — and the
  // app can be woken in the background for it — after iOS suspends or kills
  // the app. No effect on Android.
  await FlutterBluePlus.setOptions(restoreState: true);
  // Start loading dependencies immediately — in parallel with the splash animation.
  runApp(_AppLoader(dependenciesFuture: AppDependencies.standard()));
}

/// Entry point Android uses to wake the app in the background — process not
/// running at all, not just backgrounded — after detecting the known
/// gateway via the system-level BLE scan registered by [BleBackgroundService]
/// (see MainActivity.kt / BleScanReceiver.kt on the native side).
///
/// Deliberately does NOT call runApp(): a widget tree with no attached view
/// has no vsync/frame pump to drive animations, and the splash screen's
/// completion depends on one — it would simply never finish, leaving the
/// app looking stuck once the user opens it. This entry point only needs to
/// establish the BLE connection; MainActivity destroys this headless engine
/// before starting its own the moment the user actually opens the app (see
/// MainActivity.kt), so there is only ever one live GATT connection.
@pragma('vm:entry-point')
void backgroundConnectMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterBluePlus.setLogLevel(LogLevel.none);
  // AppDependencies.standard() already starts AutoConnectService if a
  // gateway is known — its active Timer/StreamSubscriptions are what keep
  // this isolate alive and busy afterwards, no explicit hold needed.
  await AppDependencies.standard();
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