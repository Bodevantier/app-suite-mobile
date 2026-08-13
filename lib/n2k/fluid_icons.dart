import 'package:flutter/material.dart';

/// Icon for a fluid/tank reading based on the fluid type reported by PGN
/// 127505 (see N2kTelemetryDecoder._fluidTypeLabels) — a plain water drop
/// for every tank is misleading for a diesel or waste tank, so the icon
/// follows what's actually in the tank instead of being fixed per metric.
IconData iconForFluidType(String? fluidType) {
  switch (fluidType) {
    case 'Fuel':
    case 'Fuel gasoline':
      return Icons.local_gas_station;
    case 'Water':
      return Icons.water_drop;
    case 'Oil':
      return Icons.oil_barrel;
    case 'Black water':
      return Icons.delete_outline;
    case 'Gray water':
      return Icons.water_damage_outlined;
    case 'Live well':
      return Icons.set_meal_outlined;
    default:
      return Icons.water_drop;
  }
}

/// Accent color for a fluid/tank reading, keyed the same way as
/// [iconForFluidType]. Shared with the fluid level detail page (see
/// FluidLevelDataPage._colorForFluid) so a tank reads the same color
/// everywhere in the app — fuel amber, water blue, waste dark, etc.
Color colorForFluidType(String? fluidType) {
  switch (fluidType?.toLowerCase()) {
    case 'fuel':
    case 'fuel gasoline':
      return const Color(0xffd97706); // amber
    case 'water':
      return const Color(0xff2563eb); // blue
    case 'gray water':
      return const Color(0xff64748b);
    case 'black water':
      return const Color(0xff1f2937);
    case 'live well':
      return const Color(0xff0891b2);
    case 'oil':
      return const Color(0xff854d0e);
    default:
      return const Color(0xff2563eb);
  }
}
