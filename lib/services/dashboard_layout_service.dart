import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dashboard_layout.dart';

/// How the visible dashboard switches: swiped manually, or automatically
/// based on [AutoModeDetector] (see lib/dashboard/auto_mode_detector.dart).
enum DashboardSwitchMode { manual, auto }

/// Persists the user's dashboards (name, icon, tag, tiles) and dashboard
/// switching preference.
///
/// Demo Mode's dashboards are stored completely separately from the real
/// ones (see [setDemoMode]) — a dashboard built around simulated devices
/// would otherwise reference device keys that never match anything real,
/// and vice versa. Toggling Demo Mode swaps which set is active; neither
/// set is visible or editable while the other is active.
///
/// Follows the same single-JSON-blob-in-SharedPreferences pattern as
/// [NodeSettingsService] (lib/services/node_settings_service.dart), just
/// with two possible storage keys instead of one.
class DashboardLayoutService extends ChangeNotifier {
  DashboardLayoutService(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;
  static const String _storageKeyNormal = 'dashboard_layouts_v1';
  static const String _storageKeyDemo = 'dashboard_layouts_demo_v1';

  // Demo Mode itself always starts off on a fresh launch (never persisted —
  // see DemoModeController), so it's fine for this to simply default to the
  // real-boat namespace at construction too.
  bool _demoMode = false;

  List<DashboardLayout> _layouts = const <DashboardLayout>[];
  String? _activeLayoutId;
  DashboardSwitchMode _switchMode = DashboardSwitchMode.manual;
  int _idCounter = 0;

  static Future<DashboardLayoutService> load() async {
    final prefs = await SharedPreferences.getInstance();
    return DashboardLayoutService(prefs);
  }

  String get _storageKey => _demoMode ? _storageKeyDemo : _storageKeyNormal;

  List<DashboardLayout> get layouts => List<DashboardLayout>.unmodifiable(_layouts);
  String? get activeLayoutId => _activeLayoutId;
  DashboardSwitchMode get switchMode => _switchMode;

  DashboardLayout? get activeLayout {
    final id = _activeLayoutId;
    if (id == null) return null;
    for (final layout in _layouts) {
      if (layout.id == id) return layout;
    }
    return null;
  }

  /// Switches between the real-boat and Demo Mode dashboard sets, reloading
  /// from whichever storage key that namespace uses. Called by
  /// [DemoModeController.enable]/[DemoModeController.disable] — not meant
  /// to be called directly from UI code.
  void setDemoMode(bool demoMode) {
    if (_demoMode == demoMode) return;
    _demoMode = demoMode;
    _load();
    notifyListeners();
  }

  void _load() {
    _layouts = const <DashboardLayout>[];
    _activeLayoutId = null;
    _switchMode = DashboardSwitchMode.manual;

    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final layoutsRaw = decoded['layouts'];
      if (layoutsRaw is List) {
        _layouts = layoutsRaw
            .whereType<Map>()
            .map((m) => DashboardLayout.fromJson(Map<String, dynamic>.from(m)))
            .whereType<DashboardLayout>()
            .toList(growable: false);
      }

      final activeId = decoded['activeLayoutId'];
      if (activeId is String) _activeLayoutId = activeId;

      final switchModeName = decoded['switchMode'];
      if (switchModeName is String) {
        for (final mode in DashboardSwitchMode.values) {
          if (mode.name == switchModeName) {
            _switchMode = mode;
            break;
          }
        }
      }
    } catch (_) {
      // Corrupted entry — start fresh rather than crash.
    }
  }

  Future<void> _persist() async {
    final encoded = jsonEncode(<String, dynamic>{
      'layouts': _layouts.map((l) => l.toJson()).toList(),
      if (_activeLayoutId != null) 'activeLayoutId': _activeLayoutId,
      'switchMode': _switchMode.name,
    });
    await _prefs.setString(_storageKey, encoded);
  }

  /// Locally-unique id for a new layout/tile. Layouts never leave this
  /// device, so global uniqueness isn't needed.
  String generateId() {
    _idCounter++;
    return '${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  Future<DashboardLayout> addLayout({
    required String name,
    required String iconKey,
    DashboardModeTag? modeTag,
  }) async {
    final layout = DashboardLayout(
      id: generateId(),
      name: name,
      iconKey: iconKey,
      modeTag: modeTag,
    );
    _layouts = List<DashboardLayout>.unmodifiable(<DashboardLayout>[
      ..._layouts,
      layout,
    ]);
    _activeLayoutId ??= layout.id;
    notifyListeners();
    await _persist();
    return layout;
  }

  Future<void> updateLayout(DashboardLayout updated) async {
    final index = _layouts.indexWhere((l) => l.id == updated.id);
    if (index == -1) return;
    final next = List<DashboardLayout>.of(_layouts);
    next[index] = updated;
    _layouts = List<DashboardLayout>.unmodifiable(next);
    notifyListeners();
    await _persist();
  }

  Future<void> deleteLayout(String id) async {
    final next = _layouts.where((l) => l.id != id).toList(growable: false);
    if (next.length == _layouts.length) return;
    _layouts = List<DashboardLayout>.unmodifiable(next);
    if (_activeLayoutId == id) {
      _activeLayoutId = next.isEmpty ? null : next.first.id;
    }
    notifyListeners();
    await _persist();
  }

  Future<void> setActiveLayoutId(String? id) async {
    if (_activeLayoutId == id) return;
    _activeLayoutId = id;
    notifyListeners();
    await _persist();
  }

  Future<void> setSwitchMode(DashboardSwitchMode mode) async {
    if (_switchMode == mode) return;
    _switchMode = mode;
    notifyListeners();
    await _persist();
  }

  Future<void> clearAll() async {
    _layouts = const <DashboardLayout>[];
    _activeLayoutId = null;
    _switchMode = DashboardSwitchMode.manual;
    notifyListeners();
    await _prefs.remove(_storageKey);
  }
}
