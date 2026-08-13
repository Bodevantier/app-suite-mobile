import 'package:ble_application/demo/demo_dashboard_seed.dart';
import 'package:ble_application/models/dashboard_layout.dart';
import 'package:ble_application/services/dashboard_layout_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('seeds four tagged, populated dashboards', () async {
    SharedPreferences.setMockInitialValues({});
    final dashboards = await DashboardLayoutService.load();
    dashboards.setDemoMode(true);

    await seedDefaultDemoDashboards(dashboards);

    expect(dashboards.layouts, hasLength(4));
    final tags = dashboards.layouts.map((l) => l.modeTag).toSet();
    expect(tags, {
      DashboardModeTag.sailing,
      DashboardModeTag.motoring,
      DashboardModeTag.anchored,
      DashboardModeTag.docked,
    });
    for (final layout in dashboards.layouts) {
      expect(layout.tiles, isNotEmpty, reason: '${layout.name} should have tiles');
    }
    // Sailing is added first, so it's the default landing dashboard.
    expect(dashboards.activeLayout?.modeTag, DashboardModeTag.sailing);
  });

  test('does not duplicate when the demo namespace already has dashboards', () async {
    SharedPreferences.setMockInitialValues({});
    final dashboards = await DashboardLayoutService.load();
    dashboards.setDemoMode(true);
    await dashboards.addLayout(name: 'Custom', iconKey: 'dashboard');

    await seedDefaultDemoDashboards(dashboards);

    expect(dashboards.layouts, hasLength(1));
    expect(dashboards.layouts.single.name, 'Custom');
  });

  test('never touches the real (non-demo) dashboard namespace', () async {
    SharedPreferences.setMockInitialValues({});
    final dashboards = await DashboardLayoutService.load();
    await dashboards.addLayout(name: 'My Real Dashboard', iconKey: 'dashboard');

    dashboards.setDemoMode(true);
    await seedDefaultDemoDashboards(dashboards);
    expect(dashboards.layouts, hasLength(4));

    dashboards.setDemoMode(false);
    expect(dashboards.layouts, hasLength(1));
    expect(dashboards.layouts.single.name, 'My Real Dashboard');
  });
}
