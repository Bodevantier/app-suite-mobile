import 'package:flutter/material.dart';

import '../models/dashboard_layout.dart';

/// Curated icon choices for a dashboard layout, keyed by a stable string
/// stored in `DashboardLayout.iconKey` — kept as a string there (rather than
/// a raw `IconData`) so the persisted model stays free of Flutter imports,
/// like the other files in lib/models/.
const Map<String, IconData> dashboardIconChoices = <String, IconData>{
  'dashboard': Icons.dashboard_outlined,
  'sailing': Icons.sailing_outlined,
  'directions_boat': Icons.directions_boat_outlined,
  'anchor': Icons.anchor,
  'engine': Icons.speed,
  'home': Icons.home_outlined,
  'wind': Icons.air,
  'navigation': Icons.navigation_outlined,
};

const String defaultDashboardIconKey = 'dashboard';

IconData dashboardIconFor(String iconKey) =>
    dashboardIconChoices[iconKey] ??
    dashboardIconChoices[defaultDashboardIconKey]!;

String dashboardModeTagLabel(DashboardModeTag tag) => switch (tag) {
      DashboardModeTag.sailing => 'Sailing',
      DashboardModeTag.motoring => 'Motoring',
      DashboardModeTag.anchored => 'Anchored',
      DashboardModeTag.docked => 'Docked',
    };
