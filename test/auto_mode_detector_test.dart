import 'package:ble_application/controllers/ble_controller.dart';
import 'package:ble_application/dashboard/auto_mode_detector.dart';
import 'package:ble_application/demo/n2k_wire_format.dart';
import 'package:flutter_test/flutter_test.dart';

/// Feeds a single-frame PGN straight into [controller], the same way
/// Demo Mode does (see lib/demo/n2k_wire_format.dart) — this is real N2K
/// wire format, not a mock, so the device tracker and telemetry decoder
/// behave exactly as they would with a real gateway.
void _feed(
  BleController controller, {
  required int pgn,
  required int source,
  required List<int> data,
}) {
  final bytes = packFrameBatch([
    singleFrame(pgn: pgn, source: source, data: data),
  ]);
  controller.onBinaryPacket(bytes);
}

void _feedEngineRpm(BleController controller, {required int source, required double rpm}) {
  final rpmRaw = (rpm * 4).round();
  _feed(
    controller,
    pgn: 127488,
    source: source,
    data: [0, ...le16(rpmRaw), 0xff, 0xff, 0x00, 0xff, 0xff],
  );
}

void _feedSog(BleController controller, {required int source, required double sogMs}) {
  final sogRaw = (sogMs * 100).round();
  _feed(
    controller,
    pgn: 129026,
    source: source,
    data: [0, 0x00, ...le16(0), ...le16(sogRaw), 0xff, 0xff],
  );
}

/// Polls [detector] enough times with a consistent classification for its
/// debounce window to elapse (see AutoModeDetector's stablePolls).
void _pollUntilStable(AutoModeDetector detector, {int times = 3}) {
  for (var i = 0; i < times; i++) {
    detector.debugPoll();
  }
}

void main() {
  test('classifies Motoring once an engine reports RPM above the running threshold', () {
    final controller = BleController();
    final detector = AutoModeDetector(telemetryController: controller);
    addTearDown(detector.dispose);

    _feedEngineRpm(controller, source: 5, rpm: 800);
    _pollUntilStable(detector);

    expect(detector.detectedState, DashboardAutoState.motoring);
  });

  test('classifies Sailing when moving with no engine running', () {
    final controller = BleController();
    final detector = AutoModeDetector(telemetryController: controller);
    addTearDown(detector.dispose);

    _feedSog(controller, source: 9, sogMs: 3.0); // ~5.8 kn
    _pollUntilStable(detector);

    expect(detector.detectedState, DashboardAutoState.sailing);
  });

  test('classifies Stationary when speed is near zero and no engine running', () {
    final controller = BleController();
    final detector = AutoModeDetector(telemetryController: controller);
    addTearDown(detector.dispose);

    _feedSog(controller, source: 9, sogMs: 0.05);
    _pollUntilStable(detector);

    expect(detector.detectedState, DashboardAutoState.stationary);
  });

  test('an engine running overrides being underway — Motoring wins over Sailing', () {
    final controller = BleController();
    final detector = AutoModeDetector(telemetryController: controller);
    addTearDown(detector.dispose);

    _feedSog(controller, source: 9, sogMs: 4.0);
    _feedEngineRpm(controller, source: 5, rpm: 1200);
    _pollUntilStable(detector);

    expect(detector.detectedState, DashboardAutoState.motoring);
  });

  test('stays undetected with no speed source at all', () {
    final controller = BleController();
    final detector = AutoModeDetector(telemetryController: controller);
    addTearDown(detector.dispose);

    _pollUntilStable(detector);

    expect(detector.detectedState, isNull);
  });

  test('a single poll is not enough to change state — requires stability', () {
    final controller = BleController();
    final detector = AutoModeDetector(telemetryController: controller);
    addTearDown(detector.dispose);

    _feedEngineRpm(controller, source: 5, rpm: 800);
    detector.debugPoll();

    expect(detector.detectedState, isNull);
  });
}
