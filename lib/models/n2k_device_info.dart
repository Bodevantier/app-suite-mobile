class N2kDeviceInfo {
  const N2kDeviceInfo({
    required this.src,
    required this.name,
    required this.model,
    required this.manufacturer,
    required this.category,
    required this.online,
    this.lastSeen,
    this.hasAddressClaim = false,
    this.hasProductInfo = false,
    this.hasConfigurationInfo = false,
    this.hasTxPgnList = false,
    this.hasRxPgnList = false,
    this.hasLiveWindData = false,
    this.hasLiveTemperatureData = false,
    this.serialNumber,
    this.softwareVersion,
    this.modelVersion,
    this.manufacturerText,
    this.installationDescription1,
    this.installationDescription2,
    this.deviceClass,
    this.deviceFunction,
    this.nameValue,
    this.supportedPgns = const <int>[],
    this.extraData = const <String, dynamic>{},
  });

  final int src;
  final String name;
  final String model;
  final String manufacturer;
  final String category;
  final bool online;
  final DateTime? lastSeen;
  final bool hasAddressClaim;
  final bool hasProductInfo;
  final bool hasConfigurationInfo;
  final bool hasTxPgnList;
  final bool hasRxPgnList;
  final bool hasLiveWindData;
  final bool hasLiveTemperatureData;
  final String? serialNumber;
  final String? softwareVersion;
  final String? modelVersion;
  final String? manufacturerText;
  final String? installationDescription1;
  final String? installationDescription2;
  final int? deviceClass;
  final int? deviceFunction;
  final String? nameValue;
  final List<int> supportedPgns;
  final Map<String, dynamic> extraData;

  int get sourceAddress => src;
  String get deviceName => name;
  bool get isOnline => online;
  String? get hardwareVersion => modelVersion;

  bool get isWindDevice => hasLiveWindData || category == 'wind';

  // Generic detection: any device advertising temperature PGNs is a temperature
  // source. Function code 160 in the environmental class also matches.
  static const _temperaturePgns = {130316, 130312};
  bool get isTemperatureDevice {
    if (hasLiveTemperatureData) return true;
    if (supportedPgns.any(_temperaturePgns.contains)) return true;
    return category == 'temperature';
  }

  // Generic detection: any device advertising position or COG/SOG PGNs is a
  // navigation source, regardless of device class (chartplotter, GPS, AIS, etc.)
  static const _navigationPgns = {129025, 129026, 129029};
  bool get isNavigationDevice {
    if (supportedPgns.any(_navigationPgns.contains)) return true;
    return category == 'navigation';
  }

  bool get isBleGatewayDevice => category == 'gateway';

  bool get hasGatewayFallbackName => _isGatewayFallbackName(name);

  String get displayName {
    if (!hasGatewayFallbackName) {
      return _displayText(name, 'Unknown device');
    }

    final installationName = _meaningfulIdentityText(installationDescription1);
    if (installationName != null) {
      return installationName;
    }

    final modelName = _meaningfulIdentityText(model);
    if (modelName != null) {
      return modelName;
    }

    return 'Unknown device';
  }

  String get identityRootCauseHint {
    if (!hasGatewayFallbackName) {
      if (hasLiveWindData) {
        return 'This node is currently the live wind-data source reported by the gateway.';
      }
      if (hasLiveTemperatureData) {
        return 'This node is currently broadcasting live temperature data.';
      }
      return 'Device name provided by gateway/device metadata.';
    }
    if (!hasProductInfo) {
      return 'Gateway did not receive Product Information from this source, so it used a generic fallback name.';
    }
    if (displayName != name) {
      return 'Gateway kept a generic source-based name internally, but Product/Configuration metadata provided a better user-visible device name.';
    }
    if (!hasAddressClaim) {
      return 'Gateway did not receive an Address Claim for this source, so identity details are incomplete.';
    }

    final manufacturerKnown = manufacturerText != null;
    final modelKnown = hasProductInfo;
    if (!manufacturerKnown && !modelKnown) {
      return 'No reliable model/manufacturer identity was reported, so gateway used a generic source-based name.';
    }
    return 'Gateway chose a generic source-based name for this node; check source metadata on the gateway side.';
  }

  String get displayModel => _displayText(model, 'Unknown model');
  String get displayManufacturer =>
      _displayText(manufacturer, 'Unknown manufacturer');
  String get displayCategory => _displayText(category, 'unknown');
  String get displaySoftwareVersion => _displayText(softwareVersion, 'unknown');
  String get displayHardwareVersion => _displayText(modelVersion, 'unknown');
  String get displaySerialNumber => _displayText(serialNumber, 'unknown');

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'src': src,
      'name': name,
      'model': model,
      'manufacturer': manufacturer,
      'category': category,
      'online': online,
      if (lastSeen != null) 'lastSeen': lastSeen!.toIso8601String(),
      'hasAddressClaim': hasAddressClaim,
      'hasProductInfo': hasProductInfo,
      'hasConfigurationInfo': hasConfigurationInfo,
      'hasTxPgnList': hasTxPgnList,
      'hasRxPgnList': hasRxPgnList,
      'hasLiveWindData': hasLiveWindData,
      if (serialNumber != null) 'serialNumber': serialNumber,
      if (softwareVersion != null) 'softwareVersion': softwareVersion,
      if (modelVersion != null) 'modelVersion': modelVersion,
      if (manufacturerText != null) 'manufacturerText': manufacturerText,
      if (installationDescription1 != null)
        'installationDescription1': installationDescription1,
      if (installationDescription2 != null)
        'installationDescription2': installationDescription2,
      if (deviceClass != null) 'deviceClass': deviceClass,
      if (deviceFunction != null) 'deviceFunction': deviceFunction,
      if (nameValue != null) 'nameValue': nameValue,
      'supportedPgns': supportedPgns,
      if (extraData.isNotEmpty) 'extraData': extraData,
    };
  }

  factory N2kDeviceInfo.fromJson(Map<String, dynamic> json) {
    final hasAddressClaim = _parseBool(json['hasAddressClaim']);
    final hasProductInfo = _parseBool(json['hasProductInfo']);
    final hasConfigurationInfo = _parseBool(json['hasConfigurationInfo']);

    return N2kDeviceInfo(
      src: _parseInt(json['src'] ?? json['sourceAddress']) ?? 0,
      name:
          _parseString(json['name'] ?? json['deviceName']) ?? 'Unknown device',
      model: _parseString(json['model']) ?? 'Unknown model',
      manufacturer:
          _parseString(json['manufacturer']) ?? 'Unknown manufacturer',
      category: _parseString(json['category']) ?? 'unknown',
      online: _parseBool(json['online'] ?? json['isOnline']),
      lastSeen: _parseDateTime(json['lastSeen']),
      hasAddressClaim: hasAddressClaim,
      hasProductInfo: hasProductInfo,
      hasConfigurationInfo: hasConfigurationInfo,
      hasTxPgnList: _parseBool(json['hasTxPgnList']),
      hasRxPgnList: _parseBool(json['hasRxPgnList']),
      hasLiveWindData: _parseBool(json['hasLiveWindData']),
      serialNumber: _parseString(json['serialNumber']),
      softwareVersion: _parseString(json['softwareVersion']),
      modelVersion: _parseString(
        json['modelVersion'] ?? json['hardwareVersion'],
      ),
      manufacturerText: _parseString(json['manufacturerText']),
      installationDescription1: _parseString(json['installationDescription1']),
      installationDescription2: _parseString(json['installationDescription2']),
      deviceClass: _parseInt(json['deviceClass']),
      deviceFunction: _parseInt(json['deviceFunction']),
      nameValue: _parseString(json['nameValue']),
      supportedPgns: _parseSupportedPgns(json['supportedPgns']),
      extraData: _parseExtraData(
        json,
        json['extraData'],
        hasAddressClaim: hasAddressClaim,
        hasProductInfo: hasProductInfo,
        hasConfigurationInfo: hasConfigurationInfo,
      ),
    );
  }

  N2kDeviceInfo copyWith({
    int? src,
    String? name,
    String? model,
    String? manufacturer,
    String? category,
    bool? online,
    DateTime? lastSeen,
    bool? hasAddressClaim,
    bool? hasProductInfo,
    bool? hasConfigurationInfo,
    bool? hasTxPgnList,
    bool? hasRxPgnList,
    bool? hasLiveWindData,
    bool? hasLiveTemperatureData,
    String? serialNumber,
    String? softwareVersion,
    String? modelVersion,
    String? manufacturerText,
    String? installationDescription1,
    String? installationDescription2,
    int? deviceClass,
    int? deviceFunction,
    String? nameValue,
    List<int>? supportedPgns,
    Map<String, dynamic>? extraData,
  }) {
    return N2kDeviceInfo(
      src: src ?? this.src,
      name: name ?? this.name,
      model: model ?? this.model,
      manufacturer: manufacturer ?? this.manufacturer,
      category: category ?? this.category,
      online: online ?? this.online,
      lastSeen: lastSeen ?? this.lastSeen,
      hasAddressClaim: hasAddressClaim ?? this.hasAddressClaim,
      hasProductInfo: hasProductInfo ?? this.hasProductInfo,
      hasConfigurationInfo: hasConfigurationInfo ?? this.hasConfigurationInfo,
      hasTxPgnList: hasTxPgnList ?? this.hasTxPgnList,
      hasRxPgnList: hasRxPgnList ?? this.hasRxPgnList,
      hasLiveWindData: hasLiveWindData ?? this.hasLiveWindData,
      hasLiveTemperatureData: hasLiveTemperatureData ?? this.hasLiveTemperatureData,
      serialNumber: serialNumber ?? this.serialNumber,
      softwareVersion: softwareVersion ?? this.softwareVersion,
      modelVersion: modelVersion ?? this.modelVersion,
      manufacturerText: manufacturerText ?? this.manufacturerText,
      installationDescription1:
          installationDescription1 ?? this.installationDescription1,
      installationDescription2:
          installationDescription2 ?? this.installationDescription2,
      deviceClass: deviceClass ?? this.deviceClass,
      deviceFunction: deviceFunction ?? this.deviceFunction,
      nameValue: nameValue ?? this.nameValue,
      supportedPgns: supportedPgns ?? this.supportedPgns,
      extraData: extraData ?? this.extraData,
    );
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static bool _parseBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '0') {
        return false;
      }
    }
    return false;
  }

  static int? _parseInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  static String? _parseString(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return null;
  }

  static List<int> _parseSupportedPgns(Object? value) {
    if (value is! List) {
      return const <int>[];
    }

    final parsed = value
        .map(_parseInt)
        .whereType<int>()
        .toList(growable: false);
    return List<int>.unmodifiable(parsed);
  }

  static Map<String, dynamic> _parseExtraData(
    Map<String, dynamic> json,
    Object? value, {
    required bool hasAddressClaim,
    required bool hasProductInfo,
    required bool hasConfigurationInfo,
  }) {
    final extraData = value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};

    for (final entry in json.entries) {
      switch (entry.key) {
        case 'src':
        case 'sourceAddress':
        case 'name':
        case 'deviceName':
        case 'model':
        case 'manufacturer':
        case 'category':
        case 'online':
        case 'isOnline':
        case 'lastSeen':
        case 'hasAddressClaim':
        case 'hasProductInfo':
        case 'hasConfigurationInfo':
        case 'hasTxPgnList':
        case 'hasRxPgnList':
        case 'hasLiveWindData':
        case 'softwareVersion':
        case 'hardwareVersion':
        case 'modelVersion':
        case 'manufacturerText':
        case 'installationDescription1':
        case 'installationDescription2':
        case 'serialNumber':
        case 'deviceClass':
        case 'deviceFunction':
        case 'nameValue':
        case 'supportedPgns':
        case 'extraData':
          continue;
        default:
          extraData.putIfAbsent(entry.key, () => entry.value);
      }
    }

    extraData.putIfAbsent('hasAddressClaim', () => hasAddressClaim);
    extraData.putIfAbsent('hasProductInfo', () => hasProductInfo);
    extraData.putIfAbsent('hasConfigurationInfo', () => hasConfigurationInfo);

    if (extraData.isEmpty) {
      return const <String, dynamic>{};
    }
    return Map<String, dynamic>.unmodifiable(extraData);
  }

  static String _displayText(String? value, String fallback) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return fallback;
    }
    return trimmed;
  }

  static bool _isGatewayFallbackName(String value) {
    final trimmed = value.trim();
    return RegExp(
      r'^N2K\s+node\s+src\s+\d+$',
      caseSensitive: false,
    ).hasMatch(trimmed);
  }

  static String? _meaningfulIdentityText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    final normalized = trimmed.toLowerCase();
    if (normalized == 'unknown' || normalized == 'unknown model') {
      return null;
    }
    return trimmed;
  }
}

List<N2kDeviceInfo> filterSetupVisibleDevices(Iterable<N2kDeviceInfo> devices) {
  return List<N2kDeviceInfo>.unmodifiable(
    devices.where((device) => !device.isBleGatewayDevice),
  );
}
