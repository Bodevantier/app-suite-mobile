import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'app_preferences_service.dart';
import 'sun_calculator.dart';

/// How the app decides whether Night Mode is on.
enum NightModeSetting {
  /// Follow local sunrise/sunset, computed from the last known position.
  auto,

  /// Always on, regardless of time or position.
  on,

  /// Always off.
  off;

  static NightModeSetting fromName(String name) => NightModeSetting.values
      .firstWhere((v) => v.name == name, orElse: () => NightModeSetting.auto);
}

/// Decides whether the app should currently be showing its night palette,
/// and owns the (deliberately infrequent) location fixes that Automatic mode
/// uses to compute local sunrise/sunset — like a standalone chartplotter,
/// entirely offline.
///
/// Battery/privacy design:
///  - A position fix is only ever requested while [setting] is
///    [NightModeSetting.auto].
///  - Fixes use [LocationAccuracy.lowest] (~500m-3000m) — plenty for
///    sunrise/sunset, which barely shifts over such distances.
///  - Fixes are cached to disk and reused for up to [_maxPositionAge]
///    (6 hours) before another is requested.
///  - [startForeground] (which arms the periodic recheck and may trigger a
///    fix) must only be called by the visible app — never by the headless
///    BLE-wake isolate in main.dart, which has no UI and nothing to theme.
class NightModeService extends ChangeNotifier {
  NightModeService({required AppPreferencesService preferences})
      : _preferences = preferences {
    _setting = NightModeSetting.fromName(preferences.nightModeSetting);
    _lastLat = preferences.nightModeLastLatitude;
    _lastLon = preferences.nightModeLastLongitude;
    _lastFixAt = preferences.nightModeLastFixAt;
    _recompute();
  }

  static const Duration _maxPositionAge = Duration(hours: 6);
  static const Duration _recheckInterval = Duration(minutes: 1);
  static const Duration _fixTimeout = Duration(seconds: 20);

  final AppPreferencesService _preferences;

  NightModeSetting _setting = NightModeSetting.auto;
  double? _lastLat;
  double? _lastLon;
  DateTime? _lastFixAt;
  bool _isActive = false;
  bool _permissionDenied = false;
  bool _refreshInFlight = false;
  Timer? _ticker;

  NightModeSetting get setting => _setting;

  /// Whether the app should currently render its night palette.
  bool get isActive => _isActive;

  bool get hasPosition => _lastLat != null && _lastLon != null;

  DateTime? get lastFixAt => _lastFixAt;

  /// Set once a location request has been denied, so the Settings page can
  /// explain why Automatic mode isn't switching. Cleared on the next
  /// successful fix.
  bool get permissionDenied => _permissionDenied;

  /// Today's sunrise/sunset at the last known position, if any — shown in
  /// Settings so the user can see what Automatic mode is using.
  SunTimes? get todaySunTimes {
    final lat = _lastLat;
    final lon = _lastLon;
    if (lat == null || lon == null) return null;
    return SunCalculator.calculate(
        latitude: lat, longitude: lon, date: DateTime.now());
  }

  /// Starts the once-a-minute recheck (and, in Automatic mode, position
  /// refresh) loop. Call once from the visible app's top-level widget —
  /// never from the headless BLE-wake isolate.
  void startForeground() {
    _ticker ??= Timer.periodic(_recheckInterval, (_) => _tick());
    _tick();
  }

  void _tick() {
    _recompute();
    if (_setting == NightModeSetting.auto) {
      unawaited(_maybeRefreshPosition());
    }
  }

  /// Re-evaluates immediately rather than waiting for the next scheduled
  /// tick — call when the app resumes from the background, since a
  /// backgrounded app's timers may have been throttled by the OS.
  void recheckNow() => _tick();

  Future<void> setSetting(NightModeSetting value) async {
    if (_setting == value) return;
    _setting = value;
    unawaited(_preferences.saveNightModeSetting(value.name));
    _recompute();
    notifyListeners();
    if (value == NightModeSetting.auto) {
      // The user just opted in from the Settings page — this is exactly the
      // moment a location permission prompt is expected, so fetch now
      // rather than waiting for the next scheduled recheck.
      unawaited(_maybeRefreshPosition(force: true));
    }
  }

  Future<void> _maybeRefreshPosition({bool force = false}) async {
    if (_refreshInFlight) return;
    final age = _lastFixAt == null ? null : DateTime.now().difference(_lastFixAt!);
    if (!force && age != null && age < _maxPositionAge) return;

    _refreshInFlight = true;
    try {
      if (!await _ensurePermission()) {
        _permissionDenied = true;
        notifyListeners();
        return;
      }
      _permissionDenied = false;
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.lowest,
          timeLimit: _fixTimeout,
        ),
      );
      _lastLat = position.latitude;
      _lastLon = position.longitude;
      _lastFixAt = DateTime.now();
      unawaited(_preferences.saveNightModePosition(
        latitude: _lastLat!,
        longitude: _lastLon!,
        fixAt: _lastFixAt!,
      ));
      _recompute();
      notifyListeners();
    } catch (_) {
      // Transient GPS/permission failure — keep using the last cached fix
      // (if any) rather than blanking out Night Mode.
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  void _recompute() {
    final bool next;
    switch (_setting) {
      case NightModeSetting.on:
        next = true;
      case NightModeSetting.off:
        next = false;
      case NightModeSetting.auto:
        next = _isNightAtLastPosition();
    }
    if (next != _isActive) {
      _isActive = next;
      notifyListeners();
    }
  }

  bool _isNightAtLastPosition() {
    final lat = _lastLat;
    final lon = _lastLon;
    // No fix yet — default to the day palette rather than guessing.
    if (lat == null || lon == null) return false;
    final now = DateTime.now();
    final times = SunCalculator.calculate(latitude: lat, longitude: lon, date: now);
    if (times.alwaysDown) return true;
    if (times.alwaysUp) return false;
    final sunrise = times.sunrise;
    final sunset = times.sunset;
    if (sunrise == null || sunset == null) return false;
    return now.isBefore(sunrise) || now.isAfter(sunset);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
