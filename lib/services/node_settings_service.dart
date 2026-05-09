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
  NodeSettings forDevice(N2kDeviceInfo device) {
    return _byKey[nodeSettingsKey(device)] ?? NodeSettings.empty;
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
