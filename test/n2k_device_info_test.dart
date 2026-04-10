import 'package:ble_application/models/n2k_device_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('displayName falls back to model for generic source names', () {
    const device = N2kDeviceInfo(
      src: 23,
      name: 'N2K node src 23',
      model: 'SDolve Wind',
      manufacturer: 'XSense Marine',
      category: 'unknown',
      online: true,
      hasAddressClaim: true,
      hasProductInfo: true,
    );

    expect(device.displayName, 'SDolve Wind');
    expect(
      device.identityRootCauseHint,
      'Gateway kept a generic source-based name internally, but Product/Configuration metadata provided a better user-visible device name.',
    );
  });
}