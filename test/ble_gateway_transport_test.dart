import 'package:ble_application/ble/services/ble_gateway_transport.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';

ScanResult _makeScanResult({
  String id = 'aa:bb:cc:dd:ee:ff',
  String name = '',
  List<Guid> serviceUuids = const [],
  int rssi = -60,
}) {
  return ScanResult(
    device: BluetoothDevice.fromId(id),
    advertisementData: AdvertisementData(
      advName: name,
      txPowerLevel: null,
      appearance: null,
      connectable: true,
      manufacturerData: {},
      serviceData: {},
      serviceUuids: serviceUuids,
    ),
    rssi: rssi,
    timeStamp: DateTime.now(),
  );
}

void main() {
  test('recognizes transient Android BLE 133 failures', () {
    expect(
      isTransientBleConnectError(
        'FlutterBluePlusException: startConnect, android_specific_error, 133, GATT_ERROR',
      ),
      isTrue,
    );
    expect(isTransientBleConnectError('Gatt error status=133'), isTrue);
  });

  test('does not mark unrelated connection failures as transient', () {
    expect(
      isTransientBleConnectError('Command characteristic not available.'),
      isFalse,
    );
    expect(isTransientBleConnectError('Bluetooth adapter poweredOff'), isFalse);
  });

  test('recognizes gateway candidates by advertised service uuid', () {
    final result = _makeScanResult(
      id: 'aa:bb:cc:dd:ee:ff',
      name: 'Nearby device',
      serviceUuids: [Guid('9db8892d-6702-118c-bc44-81ea76f3fe10')],
    );

    expect(
      isBleGatewayCandidate(
        result,
        serviceUuid: '9db8892d-6702-118c-bc44-81ea76f3fe10',
      ),
      isTrue,
    );
  });

  test('recognizes gateway candidates by name fallback', () {
    final result = _makeScanResult(
      id: '11:22:33:44:55:66',
      name: 'SDolve N2K BLE',
    );

    expect(
      isBleGatewayCandidate(
        result,
        serviceUuid: '9db8892d-6702-118c-bc44-81ea76f3fe10',
      ),
      isTrue,
    );
  });

  test('rejects unrelated peripherals', () {
    final result = _makeScanResult(
      id: '22:33:44:55:66:77',
      name: 'Headphones',
      serviceUuids: [Guid('180f')],
    );

    expect(
      isBleGatewayCandidate(
        result,
        serviceUuid: '9db8892d-6702-118c-bc44-81ea76f3fe10',
      ),
      isFalse,
    );
  });
}
