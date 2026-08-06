import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/n2k_device_info.dart';
import '../models/node_settings.dart';

/// Persists per-node user customization (display name, capacity override,
/// low-level alarm, etc.) keyed by NMEA 2000 NAME (or src-fallback).
///
/// All settings live in a single SharedPreferences entry encoded as JSON.
class NodeSettingsService extends ChangeNotifier {
  NodeSettingsService(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;
  static const String _storageKey = 'node_settings_v1';

  final Map<String, NodeSettings> _byKey = <String, NodeSettings>{};

  static Future<NodeSettingsService> load() async {
    final prefs = await SharedPreferences.getInstance();
    return NodeSettingsService(prefs);
  }

  void _load() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((key, value) {
        if (key is String && value is Map) {
          _byKey[key] = NodeSettings.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      });
    } catch (_) {
      // Corrupted entry — start fresh rather than crash.
    }
  }

  /// Returns settings for [device] or [NodeSettings.empty] when none exist.
  ///
  /// [nodeSettingsKey] switches from the `src:<n>` fallback to the stable
  /// `name:<hex>` key the moment a device's NMEA 2000 NAME resolves. If
  /// settings were saved while still on the fallback key, look there too so
  /// they aren't orphaned by that one-time transition — and self-heal by
  /// migrating the entry to the stable key so future lookups don't need to
  /// fall back at all.
  ///
  /// Note: this is called directly from widget `build()`/`AnimatedBuilder`
  /// callbacks that listen to this same service, so the migration below must
  /// NOT call [notifyListeners] — doing so would trigger a rebuild while one
  /// is already in progress. The caller already gets the correct value from
  /// this call; other listeners self-heal the same way on their next build.
  NodeSettings forDevice(N2kDeviceInfo device) {
    final key = nodeSettingsKey(device);
    final existing = _byKey[key];
    if (existing != null) return existing;

    final fallbackKey = 'src:${device.sourceAddress}';
    if (key != fallbackKey) {
      final legacy = _byKey[fallbackKey];
      if (legacy != null) {
        _byKey[key] = legacy;
        _byKey.remove(fallbackKey);
        unawaited(_persist());
        return legacy;
      }
    }
    return NodeSettings.empty;
  }

  /// Save (or clear) settings for [device]. When [settings] is empty the
  /// stored entry is removed so the storage object stays small.
  Future<void> saveForDevice(
    N2kDeviceInfo device,
    NodeSettings settings,
  ) async {
    final key = nodeSettingsKey(device);
    if (settings.isEmpty) {
      _byKey.remove(key);
    } else {
      _byKey[key] = settings;
    }
    // Drop any leftover entry under the src-address fallback key now that
    // we're saving under the stable NAME-based key, so it can't linger as
    // an orphaned duplicate that forDevice() would otherwise migrate later.
    final fallbackKey = 'src:${device.sourceAddress}';
    if (key != fallbackKey) {
      _byKey.remove(fallbackKey);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final encoded = jsonEncode({
      for (final entry in _byKey.entries) entry.key: entry.value.toJson(),
    });
    await _prefs.setString(_storageKey, encoded);
  }

  Future<void> clearAll() async {
    _byKey.clear();
    notifyListeners();
    await _prefs.remove(_storageKey);
  }
}
