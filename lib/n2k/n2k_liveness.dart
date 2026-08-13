import '../models/n2k_device_info.dart';

/// Maximum age of a device's last frame for it to still be considered
/// "live". Beyond this, cards/tiles grey out rather than show stale data —
/// opening a data page or trusting a dashboard tile at that point would
/// only show misleading numbers.
const Duration kDeviceOfflineAfter = Duration(seconds: 15);

bool isDeviceLive(N2kDeviceInfo device) {
  if (!device.isOnline) return false;
  final lastSeen = device.lastSeen;
  if (lastSeen == null) return false;
  return DateTime.now().difference(lastSeen) < kDeviceOfflineAfter;
}
