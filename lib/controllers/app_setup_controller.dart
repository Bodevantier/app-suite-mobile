import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/n2k_device_info.dart';
import '../services/app_preferences_service.dart';

class AppSetupController extends ChangeNotifier {
  AppSetupController({AppPreferencesService? preferences})
      : _preferences = preferences {
    if (preferences != null) {
      _loadFromPreferences(preferences);
    }
  }

  final AppPreferencesService? _preferences;
  final Map<int, N2kDeviceInfo> _addedDevices = <int, N2kDeviceInfo>{};
  bool _setupComplete = false;

  List<N2kDeviceInfo> get addedDevices =>
      List.unmodifiable(_addedDevices.values);
  bool get setupComplete => _setupComplete;

  void _loadFromPreferences(AppPreferencesService prefs) {
    _setupComplete = prefs.setupComplete;
    for (final device in prefs.addedDevices) {
      _addedDevices[device.sourceAddress] = device;
    }
  }

  bool isAdded(N2kDeviceInfo device) {
    return _addedDevices.containsKey(device.sourceAddress);
  }

  void addDevice(N2kDeviceInfo device) {
    _addedDevices[device.sourceAddress] = device;
    unawaited(_preferences?.saveAddedDevices(_addedDevices.values.toList()));
    notifyListeners();
  }

  void removeDevice(N2kDeviceInfo device) {
    final removed = _addedDevices.remove(device.sourceAddress);
    if (removed != null) {
      unawaited(_preferences?.saveAddedDevices(_addedDevices.values.toList()));
      notifyListeners();
    }
  }

  void completeSetup() {
    if (_setupComplete) {
      return;
    }
    _setupComplete = true;
    unawaited(_preferences?.saveSetupComplete(true));
    notifyListeners();
  }

  void resetSetup() {
    _addedDevices.clear();
    _setupComplete = false;
    unawaited(_preferences?.clearAll());
    notifyListeners();
  }
}