import '../models/dashboard_layout.dart';
import '../models/n2k_device_info.dart';
import '../models/node_settings.dart';

/// Resolves a [DashboardTile]'s stored device identity against the devices
/// currently visible on the bus.
///
/// Matches by the stable `nodeSettingsKey()` identity first (NMEA 2000 NAME
/// once resolved, else `src:<n>`), falling back to the tile's last-known
/// source address if the key isn't found — e.g. the NAME hadn't resolved
/// yet when the tile was added and the source address has since changed.
N2kDeviceInfo? resolveTileDevice(
  DashboardTile tile,
  List<N2kDeviceInfo> devices,
) {
  for (final device in devices) {
    if (nodeSettingsKey(device) == tile.deviceKey) return device;
  }
  final hint = tile.deviceSrcHint;
  if (hint != null) {
    for (final device in devices) {
      if (device.src == hint) return device;
    }
  }
  return null;
}
