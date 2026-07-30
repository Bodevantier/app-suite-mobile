import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/n2k_device_info.dart';

/// Persists app configuration to local storage.
///
/// Keys:
///   - [_keySetupComplete]      — whether the initial setup wizard has been done
///   - [_keyAddedDevices]       — JSON list of N2K devices the user has added
///   - [_keyKnownGatewayId]     — BLE device ID of the previously connected gateway
///   - [_keyKnownGatewayName]   — last advertised/platform name seen for that gateway
///   - [_keyCachedN2kDevices]   — JSON list of the last N2K device snapshot
///   - [_keyWindTwsSamples]     — JSON list of TWS ring-buffer samples (last 31 min)
///   - [_keyWindAwsSamples]     — JSON list of AWS ring-buffer samples (last 31 min)
class AppPreferencesService {
  AppPreferencesService(this._prefs);

  final SharedPreferences _prefs;

  static const _keySetupComplete = 'setup_complete';
  static const _keyAddedDevices = 'added_devices';
  static const _keyKnownGatewayId = 'known_gateway_id';
  static const _keyKnownGatewayName = 'known_gateway_name';
  static const _keyCachedN2kDevices = 'cached_n2k_devices';
  static const _keyForgottenN2kSources = 'forgotten_n2k_sources';
  static const _keyWindTwsSamples = 'wind_tws_samples';
  static const _keyWindAwsSamples = 'wind_aws_samples';
  static const _keyWindSession = 'wind_session';

  // ── factory ──────────────────────────────────────────────────────────────

  static Future<AppPreferencesService> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppPreferencesService(prefs);
  }

  // ── setup state ──────────────────────────────────────────────────────────

  bool get setupComplete => _prefs.getBool(_keySetupComplete) ?? false;

  Future<void> saveSetupComplete(bool value) =>
      _prefs.setBool(_keySetupComplete, value);

  // ── added devices ─────────────────────────────────────────────────────────

  List<N2kDeviceInfo> get addedDevices {
    final raw = _prefs.getString(_keyAddedDevices);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(N2kDeviceInfo.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAddedDevices(List<N2kDeviceInfo> devices) async {
    final encoded = jsonEncode(devices.map((d) => d.toJson()).toList());
    await _prefs.setString(_keyAddedDevices, encoded);
  }

  // ── known BLE gateway ─────────────────────────────────────────────────────

  String? get knownGatewayId => _prefs.getString(_keyKnownGatewayId);

  Future<void> saveKnownGatewayId(String? deviceId) async {
    if (deviceId == null) {
      await _prefs.remove(_keyKnownGatewayId);
    } else {
      await _prefs.setString(_keyKnownGatewayId, deviceId);
    }
  }

  /// Last advertised/platform name seen for the known gateway. Used so a
  /// direct reconnect (no scan step) can still show a real device name
  /// instead of a guessed generic label.
  String? get knownGatewayName => _prefs.getString(_keyKnownGatewayName);

  Future<void> saveKnownGatewayName(String? name) async {
    if (name == null || name.isEmpty) {
      await _prefs.remove(_keyKnownGatewayName);
    } else {
      await _prefs.setString(_keyKnownGatewayName, name);
    }
  }

  // ── cached N2K device list ────────────────────────────────────────────────

  List<N2kDeviceInfo> get cachedN2kDevices {
    final raw = _prefs.getString(_keyCachedN2kDevices);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(N2kDeviceInfo.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveCachedN2kDevices(List<N2kDeviceInfo> devices) async {
    final encoded = jsonEncode(devices.map((d) => d.toJson()).toList());
    await _prefs.setString(_keyCachedN2kDevices, encoded);
  }

  // ── forgotten N2K sources (swiped-away offline devices) ──────────────────
  // Persisted as a JSON object {"<src>": "<ISO-8601 UTC>"}. The timestamp is
  // the moment of dismissal — used by the controller to auto-revive a src
  // only when a CAN frame newer than that instant arrives on the wire.

  Map<int, DateTime> get forgottenN2kSources {
    final raw = _prefs.getString(_keyForgottenN2kSources);
    if (raw == null) return const <int, DateTime>{};
    try {
      final decoded = jsonDecode(raw);
      // Backwards-compat: older builds stored a plain List<int>. Treat those
      // entries as forgotten "since epoch" so any new CAN frame revives them.
      if (decoded is List) {
        return {
          for (final e in decoded.whereType<num>())
            e.toInt(): DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        };
      }
      if (decoded is Map) {
        final out = <int, DateTime>{};
        decoded.forEach((k, v) {
          final src = int.tryParse(k.toString());
          final ts = v is String ? DateTime.tryParse(v) : null;
          if (src != null && ts != null) out[src] = ts.toUtc();
        });
        return out;
      }
    } catch (_) {}
    return const <int, DateTime>{};
  }

  Future<void> saveForgottenN2kSources(Map<int, DateTime> sources) async {
    final encoded = jsonEncode({
      for (final entry in sources.entries)
        entry.key.toString(): entry.value.toUtc().toIso8601String(),
    });
    await _prefs.setString(_keyForgottenN2kSources, encoded);
  }

  // ── wind sample ring buffers ──────────────────────────────────────────────

  List<dynamic> get windTwsSamples {
    final raw = _prefs.getString(_keyWindTwsSamples);
    if (raw == null) return const [];
    try {
      return jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return const [];
    }
  }

  List<dynamic> get windAwsSamples {
    final raw = _prefs.getString(_keyWindAwsSamples);
    if (raw == null) return const [];
    try {
      return jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveWindSamples({
    required List<Map<String, dynamic>> tws,
    required List<Map<String, dynamic>> aws,
  }) async {
    await Future.wait([
      _prefs.setString(_keyWindTwsSamples, jsonEncode(tws)),
      _prefs.setString(_keyWindAwsSamples, jsonEncode(aws)),
    ]);
  }

  Map<String, dynamic>? get windSession {
    final raw = _prefs.getString(_keyWindSession);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveWindSession(Map<String, dynamic> session) async {
    await _prefs.setString(_keyWindSession, jsonEncode(session));
  }

  // ── clear ─────────────────────────────────────────────────────────────────

  Future<void> clearAll() async {
    await _prefs.remove(_keySetupComplete);
    await _prefs.remove(_keyAddedDevices);
    await _prefs.remove(_keyKnownGatewayId);
    await _prefs.remove(_keyKnownGatewayName);
    await _prefs.remove(_keyCachedN2kDevices);
    await _prefs.remove(_keyForgottenN2kSources);
    await _prefs.remove(_keyWindTwsSamples);
    await _prefs.remove(_keyWindAwsSamples);
    await _prefs.remove(_keyWindSession);
  }
}
