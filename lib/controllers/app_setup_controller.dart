import 'package:flutter/foundation.dart';

import '../models/n2k_device_info.dart';

class AppSetupController extends ChangeNotifier {
  final Map<int, N2kDeviceInfo> _addedDevices = <int, N2kDeviceInfo>{};
  bool _setupComplete = false;

  List<N2kDeviceInfo> get addedDevices =>
      List.unmodifiable(_addedDevices.values);
  bool get setupComplete => _setupComplete;

  bool isAdded(N2kDeviceInfo device) {
    return _addedDevices.containsKey(device.sourceAddress);
  }

  void addDevice(N2kDeviceInfo device) {
    _addedDevices[device.sourceAddress] = device;
    notifyListeners();
  }

  void removeDevice(N2kDeviceInfo device) {
    final removed = _addedDevices.remove(device.sourceAddress);
    if (removed != null) {
      notifyListeners();
    }
  }

  void completeSetup() {
    if (_setupComplete) {
      return;
    }
    _setupComplete = true;
    notifyListeners();
  }

  void resetSetup() {
    _addedDevices.clear();
    _setupComplete = false;
    notifyListeners();
  }
}