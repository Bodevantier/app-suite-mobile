import 'package:ble_application/models/dashboard_layout.dart';
import 'package:ble_application/services/dashboard_layout_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a newly added layout becomes active and survives a reload', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await DashboardLayoutService.load();

    final layout = await service.addLayout(
      name: 'Motoring',
      iconKey: 'engine',
      modeTag: DashboardModeTag.motoring,
    );

    expect(service.layouts, hasLength(1));
    expect(service.activeLayoutId, layout.id);

    final reloaded = DashboardLayoutService(await SharedPreferences.getInstance());
    expect(reloaded.layouts, hasLength(1));
    expect(reloaded.layouts.single.name, 'Motoring');
    expect(reloaded.layouts.single.iconKey, 'engine');
    expect(reloaded.layouts.single.modeTag, DashboardModeTag.motoring);
    expect(reloaded.activeLayoutId, layout.id);
  });

  test('tiles round-trip through toJson/fromJson with their device key intact', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await DashboardLayoutService.load();

    final layout = await service.addLayout(name: 'Sailing', iconKey: 'sailing');
    final tile = DashboardTile(
      id: service.generateId(),
      metric: DashboardMetricType.windApparentSpeed,
      deviceKey: 'name:1122334455667788',
      deviceSrcHint: 12,
    );
    await service.updateLayout(layout.copyWith(tiles: [tile]));

    final reloaded = DashboardLayoutService(await SharedPreferences.getInstance());
    final reloadedTiles = reloaded.layouts.single.tiles;
    expect(reloadedTiles, hasLength(1));
    expect(reloadedTiles.single.metric, DashboardMetricType.windApparentSpeed);
    expect(reloadedTiles.single.deviceKey, 'name:1122334455667788');
    expect(reloadedTiles.single.deviceSrcHint, 12);
  });

  test('deleting the active layout falls back to another remaining layout', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await DashboardLayoutService.load();

    final first = await service.addLayout(name: 'Motoring', iconKey: 'engine');
    final second = await service.addLayout(name: 'Sailing', iconKey: 'sailing');
    await service.setActiveLayoutId(first.id);

    await service.deleteLayout(first.id);

    expect(service.layouts, hasLength(1));
    expect(service.activeLayoutId, second.id);
  });

  test('deleting the last layout clears the active id', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await DashboardLayoutService.load();

    final only = await service.addLayout(name: 'Motoring', iconKey: 'engine');
    await service.deleteLayout(only.id);

    expect(service.layouts, isEmpty);
    expect(service.activeLayoutId, isNull);
  });

  test('switch mode persists across a reload', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await DashboardLayoutService.load();
    expect(service.switchMode, DashboardSwitchMode.manual);

    await service.setSwitchMode(DashboardSwitchMode.auto);

    final reloaded = DashboardLayoutService(await SharedPreferences.getInstance());
    expect(reloaded.switchMode, DashboardSwitchMode.auto);
  });

  test('a corrupted stored blob is ignored rather than crashing load', () async {
    SharedPreferences.setMockInitialValues({'dashboard_layouts_v1': 'not json'});
    final service = await DashboardLayoutService.load();

    expect(service.layouts, isEmpty);
    expect(service.switchMode, DashboardSwitchMode.manual);
  });

  test('demo mode dashboards are a completely separate set from the real ones', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await DashboardLayoutService.load();

    final real = await service.addLayout(name: 'Motoring', iconKey: 'engine');
    expect(service.layouts, hasLength(1));

    service.setDemoMode(true);
    expect(service.layouts, isEmpty, reason: 'demo namespace starts empty');
    expect(service.activeLayoutId, isNull);

    final demoLayout = await service.addLayout(name: 'Demo Sailing', iconKey: 'sailing');
    expect(service.layouts, hasLength(1));
    expect(service.layouts.single.id, demoLayout.id);

    service.setDemoMode(false);
    expect(service.layouts, hasLength(1));
    expect(service.layouts.single.id, real.id, reason: 'back to the real set, untouched');

    service.setDemoMode(true);
    expect(service.layouts.single.id, demoLayout.id, reason: 'demo set also untouched');
  });

  test('each namespace persists independently across a reload', () async {
    SharedPreferences.setMockInitialValues({});
    final service = await DashboardLayoutService.load();

    await service.addLayout(name: 'Motoring', iconKey: 'engine');
    service.setDemoMode(true);
    await service.addLayout(name: 'Demo Sailing', iconKey: 'sailing');

    final prefs = await SharedPreferences.getInstance();
    final reloadedNormal = DashboardLayoutService(prefs);
    expect(reloadedNormal.layouts.single.name, 'Motoring');

    reloadedNormal.setDemoMode(true);
    expect(reloadedNormal.layouts.single.name, 'Demo Sailing');
  });
}
