import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One alarm trigger or clear event, as shown in the incident log.
class IncidentLogEntry {
  const IncidentLogEntry({
    required this.time,
    required this.deviceKey,
    required this.deviceName,
    required this.alarmLabel,
    required this.isTrigger,
    required this.value,
    required this.threshold,
    required this.unit,
  });

  final DateTime time;
  final String deviceKey;
  final String deviceName;
  final String alarmLabel;

  /// True for the moment the alarm became active, false for when it cleared.
  final bool isTrigger;
  final double value;
  final double threshold;
  final String unit;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'time': time.toIso8601String(),
        'deviceKey': deviceKey,
        'deviceName': deviceName,
        'alarmLabel': alarmLabel,
        'isTrigger': isTrigger,
        'value': value,
        'threshold': threshold,
        'unit': unit,
      };

  factory IncidentLogEntry.fromJson(Map<String, dynamic> json) {
    double readDouble(Object? v) => (v is num) ? v.toDouble() : 0;
    return IncidentLogEntry(
      time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
      deviceKey: json['deviceKey'] as String? ?? '',
      deviceName: json['deviceName'] as String? ?? 'Unknown device',
      alarmLabel: json['alarmLabel'] as String? ?? 'Alarm',
      isTrigger: json['isTrigger'] == true,
      value: readDouble(json['value']),
      threshold: readDouble(json['threshold']),
      unit: json['unit'] as String? ?? '',
    );
  }
}

/// Chronological record of alarm trigger/clear events (newest first),
/// persisted locally so it survives app restarts. Capped so storage can't
/// grow unbounded over a long cruising season.
class IncidentLogService extends ChangeNotifier {
  IncidentLogService(this._prefs) {
    _load();
  }

  static const String _storageKey = 'incident_log_v1';
  static const int maxEntries = 300;

  final SharedPreferences _prefs;
  final List<IncidentLogEntry> _entries = <IncidentLogEntry>[];

  List<IncidentLogEntry> get entries => List.unmodifiable(_entries);

  static Future<IncidentLogService> load() async {
    final prefs = await SharedPreferences.getInstance();
    return IncidentLogService(prefs);
  }

  void _load() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is Map) {
          _entries.add(IncidentLogEntry.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    } catch (_) {
      // Corrupted entry — start fresh rather than crash.
    }
  }

  void record(IncidentLogEntry entry) {
    _entries.insert(0, entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> clearAll() async {
    _entries.clear();
    notifyListeners();
    await _prefs.remove(_storageKey);
  }

  Future<void> _persist() async {
    final encoded = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await _prefs.setString(_storageKey, encoded);
  }
}
