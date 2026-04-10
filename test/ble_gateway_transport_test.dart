import 'package:ble_application/ble/services/ble_gateway_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  test('recognizes transient Android BLE 133 failures', () {
    expect(
      isTransientBleConnectError(
        'UniversalBleException: Code: UniversalBleErrorCode.unknownError, Message: Unknown Error 133',
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
    final device = BleDevice(
      deviceId: 'aa:bb:cc:dd:ee:ff',
      name: 'Nearby device',
      services: const <String>['9db8892d-6702-118c-bc44-81ea76f3fe10'],
    );

    expect(
      isBleGatewayCandidate(
        device,
        serviceUuid: '9db8892d-6702-118c-bc44-81ea76f3fe10',
      ),
      isTrue,
    );
  });

  test('recognizes gateway candidates by name fallback', () {
    final device = BleDevice(
      deviceId: '11:22:33:44:55:66',
      name: 'SDolve N2K BLE',
    );

    expect(
      isBleGatewayCandidate(
        device,
        serviceUuid: '9db8892d-6702-118c-bc44-81ea76f3fe10',
      ),
      isTrue,
    );
  });

  test('rejects unrelated peripherals', () {
    final device = BleDevice(
      deviceId: '22:33:44:55:66:77',
      name: 'Headphones',
      services: const <String>['180f'],
    );

    expect(
      isBleGatewayCandidate(
        device,
        serviceUuid: '9db8892d-6702-118c-bc44-81ea76f3fe10',
      ),
      isFalse,
    );
  });
}
