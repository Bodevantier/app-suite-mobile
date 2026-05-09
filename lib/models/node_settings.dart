import '../models/n2k_device_info.dart';

/// Per-node user customization, persisted locally and applied on top of the
/// values broadcast on the NMEA 2000 bus.
///
/// All fields are optional — `null` means "no override, use the value from
/// the device". This is intentionally an app-side overlay only: the device
/// keeps broadcasting its real PGN values to the rest of the bus. To change
/// what the device itself broadcasts (e.g. tank capacity reported by PGN
/// 127505), the firmware setting must be changed.
class NodeSettings {
  const NodeSettings({
    this.customName,
    this.customFluidTypeLabel,
    this.customCapacityL,
    this.lowLevelAlarmEnabled = false,
    this.lowLevelAlarmPct = 10,
    this.notes,
  });

  /// Display name override (replaces [N2kDeviceInfo.displayName] in the UI).
  final String? customName;

  /// Free-text fluid label (e.g. "Diesel", "Fresh water aft"). Replaces the
  /// PGN-127505 fluid-type string in our app only.
  final String? customFluidTypeLabel;

  /// Tank capacity in litres. Used to compute the volume display. Falls back
  /// to the value reported by the device when null.
  final double? customCapacityL;

  /// When true, the page shows a red "low level" banner whenever the
  /// reported fluid level drops below [lowLevelAlarmPct].
  final bool lowLevelAlarmEnabled;

  /// Threshold percent (0–100) for the low-level alarm.
  final double lowLevelAlarmPct;

  /// Free-text notes attached to the device (e.g. "starboard locker").
  final String? notes;

  /// True when no field has a meaningful override.
  bool get isEmpty =>
      (customName == null || customName!.trim().isEmpty) &&
      (customFluidTypeLabel == null || customFluidTypeLabel!.trim().isEmpty) &&
      customCapacityL == null &&
      !lowLevelAlarmEnabled &&
      (notes == null || notes!.trim().isEmpty);

  NodeSettings copyWith({
    String? customName,
    bool clearCustomName = false,
    String? customFluidTypeLabel,
    bool clearCustomFluidTypeLabel = false,
    double? customCapacityL,
    bool clearCustomCapacityL = false,
    bool? lowLevelAlarmEnabled,
    double? lowLevelAlarmPct,
    String? notes,
    bool clearNotes = false,
  }) {
    return NodeSettings(
      customName: clearCustomName ? null : (customName ?? this.customName),
      customFluidTypeLabel: clearCustomFluidTypeLabel
          ? null
          : (customFluidTypeLabel ?? this.customFluidTypeLabel),
      customCapacityL: clearCustomCapacityL
          ? null
          : (customCapacityL ?? this.customCapacityL),
      lowLevelAlarmEnabled: lowLevelAlarmEnabled ?? this.lowLevelAlarmEnabled,
      lowLevelAlarmPct: lowLevelAlarmPct ?? this.lowLevelAlarmPct,
      notes: clearNotes ? null : (notes ?? this.notes),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (customName != null) 'customName': customName,
        if (customFluidTypeLabel != null)
          'customFluidTypeLabel': customFluidTypeLabel,
        if (customCapacityL != null) 'customCapacityL': customCapacityL,
        'lowLevelAlarmEnabled': lowLevelAlarmEnabled,
        'lowLevelAlarmPct': lowLevelAlarmPct,
        if (notes != null) 'notes': notes,
      };

  factory NodeSettings.fromJson(Map<String, dynamic> json) {
    double? readDouble(Object? v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    return NodeSettings(
      customName: json['customName'] as String?,
      customFluidTypeLabel: json['customFluidTypeLabel'] as String?,
      customCapacityL: readDouble(json['customCapacityL']),
      lowLevelAlarmEnabled: json['lowLevelAlarmEnabled'] == true,
      lowLevelAlarmPct: readDouble(json['lowLevelAlarmPct']) ?? 10,
      notes: json['notes'] as String?,
    );
  }

  static const NodeSettings empty = NodeSettings();
}

/// Stable identity used as the storage key for [NodeSettings].
///
/// Preference order:
///   1. NMEA 2000 NAME (64-bit, hex) — globally unique and stable across
///      power cycles and source-address re-negotiation.
///   2. `src-<n>` fallback when NAME has not yet been observed (e.g. the
///      device hasn't sent an Address Claim).
String nodeSettingsKey(N2kDeviceInfo device) {
  final n = device.nameValue;
  if (n != null && n.trim().isNotEmpty) {
    return 'name:${n.trim().toLowerCase()}';
  }
  return 'src:${device.sourceAddress}';
}
