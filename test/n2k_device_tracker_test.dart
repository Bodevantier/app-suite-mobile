import 'package:ble_application/n2k/models/n2k_frame.dart';
import 'package:ble_application/n2k/n2k_device_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tracks address claim and live wind source from binary frames', () {
    final tracker = N2kDeviceTracker();

    tracker.consumeFrames(<N2kFrame>[
      const N2kFrame(
        canId: 0x18eeff23,
        dlc: 8,
        flags: 0x05,
        data: <int>[0x45, 0x23, 0x01, 0x80, 0x82, 0xaa, 0x10, 0xc4],
      ),
      const N2kFrame(
        canId: 0x09fd0223,
        dlc: 8,
        flags: 0x05,
        data: <int>[0x00, 0x20, 0x03, 0x34, 0x12, 0x02, 0, 0],
      ),
    ]);

    final device = tracker.devices.single;
    expect(device.sourceAddress, 35);
    expect(device.hasAddressClaim, isTrue);
    expect(device.hasLiveWindData, isTrue);
    expect(device.displayManufacturer, 'Manufacturer code 1024');
    expect(device.displayCategory, 'unknown');
    expect(device.extraData['deviceFunction'], 170);
    expect(device.extraData['deviceClass'], 8);
    expect(device.extraData['nameValue'], 'c410aa8280012345');
  });
}