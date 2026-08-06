import 'package:ble_application/models/n2k_device_info.dart';
import 'package:ble_application/models/node_settings.dart';
import 'package:ble_application/services/node_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

N2kDeviceInfo _device({
  int src = 45,
  String? nameValue,
}) {
  return N2kDeviceInfo(
    src: src,
    name: 'Test Device',
    model: 'Model X',
    manufacturer: 'Acme',
    category: 'unknown',
    online: true,
    nameValue: nameValue,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a custom name saved before the NAME resolves is not lost once it does',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = await NodeSettingsService.load();

      // Device first appears without a resolved NMEA 2000 NAME — settings
      // are saved under the `src:<n>` fallback key.
      final unresolved = _device(nameValue: null);
      await service.saveForDevice(
        unresolved,
        const NodeSettings(customName: 'Galley Fridge'),
      );
      expect(service.forDevice(unresolved).customName, 'Galley Fridge');

      // The device's AddressClaim now resolves, so nodeSettingsKey() switches
      // to the stable `name:<hex>` key. The previously saved custom name must
      // still be found (self-healed from the old fallback key), not silently
      // dropped.
      final resolved = _device(nameValue: '1122334455667788');
      expect(service.forDevice(resolved).customName, 'Galley Fridge');

      // Migration should persist so a fresh service instance (simulating an
      // app restart) still finds it under the new key.
      final reloaded = NodeSettingsService(await SharedPreferences.getInstance());
      expect(reloaded.forDevice(resolved).customName, 'Galley Fridge');
    },
  );

  test('saving under the resolved NAME key drops the stale src fallback entry',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = await NodeSettingsService.load();

    final unresolved = _device(nameValue: null);
    await service.saveForDevice(
      unresolved,
      const NodeSettings(customName: 'Old Name'),
    );

    final resolved = _device(nameValue: 'aabbccddeeff0011');
    await service.saveForDevice(
      resolved,
      const NodeSettings(customName: 'New Name'),
    );

    // No leftover entry under the src fallback key that could later
    // re-surface (e.g. for a different device that reuses this src).
    final otherDeviceSameSrc = _device(nameValue: null);
    expect(service.forDevice(otherDeviceSameSrc).customName, isNull);
    expect(service.forDevice(resolved).customName, 'New Name');
  });
}
