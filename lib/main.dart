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
/// Transitions to [BleGatewayApp] once both the splash's brief minimum
/// display time AND dependencies are ready (whichever takes longer — in
/// practice almost always the splash, since dependency loading is just fast
/// local-storage reads). The BLE reconnect itself is not awaited here — it
/// keeps running after the transition, surfaced live on the Home page.
///
/// The swap itself is a crossfade rather than an instant cut — jumping
/// straight from the branded splash to the home page felt jarring.
class _AppLoader extends StatefulWidget {
  const _AppLoader({required this.dependenciesFuture});

  final Future<AppDependencies> dependenciesFuture;

  @override
  State<_AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<_AppLoader> {
  static const Duration _transitionDuration = Duration(milliseconds: 400);

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
    final ready = _splashDone && deps != null;
    return AnimatedSwitcher(
      duration: _transitionDuration,
      child: ready
          ? BleGatewayApp(key: const ValueKey('home'), dependencies: deps)
          // Keep showing the splash until both conditions are met. If the
          // splash's minimum display time elapses before deps load (rare —
          // deps are just local-storage reads), show a spinner rather than a
          // blank screen so there's never a moment with no feedback at all.
          : MaterialApp(
              key: ValueKey(_splashDone ? 'loading' : 'splash'),
              debugShowCheckedModeBanner: false,
              home: _splashDone
                  ? const Scaffold(
                      backgroundColor: Colors.white,
                      body: Center(child: CircularProgressIndicator()),
                    )
                  : SplashScreen(onFinished: _onSplashDone),
            ),
    );
  }
}