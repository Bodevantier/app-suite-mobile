import 'package:flutter/material.dart';

import '../dashboard/dashboard_icons.dart';
import '../models/dashboard_layout.dart';
import '../services/dashboard_layout_service.dart';
import '../widgets/dashboard_edit_dialog.dart';

/// Settings → Dashboards: create, edit and delete dashboards, and choose
/// how the home page switches between them. Kept off the dashboard itself
/// (see dashboard_home_page.dart) so day-to-day swiping isn't cluttered
/// with controls only needed occasionally.
///
/// "New dashboard" and tapping an existing one both hand off to
/// [DashboardHomePage] via [DashboardLayoutService.requestEdit] — they pop
/// straight back to Home with that dashboard open in tile-editing mode,
/// the same editing experience the app has always had, just reached from
/// here instead of an always-visible control on the dashboard.
class DashboardSettingsPage extends StatelessWidget {
  const DashboardSettingsPage({super.key, required this.dashboards});

  final DashboardLayoutService dashboards;

  Future<void> _createDashboard(BuildContext context) async {
    final result = await showEditDashboardDialog(context);
    if (result == null) return;
    final layout = await dashboards.addLayout(
      name: result.name,
      iconKey: result.iconKey,
      modeTag: result.modeTag,
    );
    dashboards.requestEdit(layout.id);
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _editDashboard(BuildContext context, DashboardLayout layout) {
    dashboards.requestEdit(layout.id);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboards')),
      body: AnimatedBuilder(
        animation: dashboards,
        builder: (context, _) {
          final cs = Theme.of(context).colorScheme;
          final layouts = dashboards.layouts;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _DashboardSwitchingCard(dashboards: dashboards),
              const SizedBox(height: 20),
              Text(
                'Your dashboards',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (layouts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'No dashboards yet — create one below.',
                    style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
                  ),
                )
              else
                Card(
                  elevation: 0,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < layouts.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          leading: Icon(dashboardIconFor(layouts[i].iconKey)),
                          title: Text(layouts[i].name),
                          subtitle: layouts[i].modeTag == null
                              ? null
                              : Text(dashboardModeTagLabel(layouts[i].modeTag!)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _editDashboard(context, layouts[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _createDashboard(context),
                icon: const Icon(Icons.add),
                label: const Text('New dashboard'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DashboardSwitchingCard extends StatelessWidget {
  const _DashboardSwitchingCard({required this.dashboards});

  final DashboardLayoutService dashboards;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dashboard_customize_outlined, color: cs.primary),
                const SizedBox(width: 10),
                const Text(
                  'Dashboard switching',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Choose whether the home page switches dashboards only when you '
              'swipe, or automatically based on engine RPM and speed.',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 14),
            SegmentedButton<DashboardSwitchMode>(
              segments: const [
                ButtonSegment(
                  value: DashboardSwitchMode.manual,
                  label: Text('Manual'),
                  icon: Icon(Icons.swipe),
                ),
                ButtonSegment(
                  value: DashboardSwitchMode.auto,
                  label: Text('Auto'),
                  icon: Icon(Icons.auto_mode),
                ),
              ],
              selected: {dashboards.switchMode},
              onSelectionChanged: (selection) =>
                  dashboards.setSwitchMode(selection.first),
            ),
            if (dashboards.switchMode == DashboardSwitchMode.auto) ...[
              const SizedBox(height: 10),
              Text(
                'Auto mode detects Motoring and Sailing from live telemetry. It '
                'can\'t tell Anchored apart from Docked (no shore-power sensor) — '
                'if you tag dashboards with both, whichever comes first is used.',
                style: TextStyle(fontSize: 11.5, color: cs.onSurface.withValues(alpha: 0.5)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
