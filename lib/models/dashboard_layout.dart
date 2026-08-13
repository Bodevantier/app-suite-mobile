/// Identifies which live data field a dashboard tile displays.
///
/// Persisted by name (see [DashboardTile.toJson]) — do not rename or reuse
/// existing values; add new ones at the end.
enum DashboardMetricType {
  engineRpm,
  temperatureC,
  fluidLevelPct,
  batteryVoltage,
  windApparentSpeed,
  windApparentAngle,
  windTrueSpeed,
  windTrueAngle,
  heading,
  speedOverGround,
  courseOverGround,
  position,
}

/// Optional tag on a [DashboardLayout], used only by auto-detect switching
/// (see `AutoModeDetector`) to pick which dashboard matches the boat's
/// current state.
enum DashboardModeTag { sailing, motoring, anchored, docked }

/// How a [DashboardTile] is rendered.
///
/// [metric] is a plain single-value tile (the common case). [windCompass]
/// is a larger tile showing wind angle relative to the boat plus a speed
/// reading — it still uses [DashboardTile.metric] to mean "which speed is
/// currently shown" (windApparentSpeed or windTrueSpeed), toggled by
/// tapping the tile body; the corresponding angle is derived from that.
enum DashboardTileKind { metric, windCompass }

DashboardMetricType? _metricFromName(String name) {
  for (final m in DashboardMetricType.values) {
    if (m.name == name) return m;
  }
  return null;
}

DashboardModeTag? _modeTagFromName(String? name) {
  if (name == null) return null;
  for (final t in DashboardModeTag.values) {
    if (t.name == name) return t;
  }
  return null;
}

DashboardTileKind _tileKindFromName(String? name) {
  if (name == null) return DashboardTileKind.metric;
  for (final k in DashboardTileKind.values) {
    if (k.name == name) return k;
  }
  return DashboardTileKind.metric;
}

/// One tile on a dashboard: a metric bound to a specific N2K device.
///
/// [deviceKey] uses the same stable-identity scheme as `nodeSettingsKey()`
/// (lib/models/node_settings.dart) — `name:<hex>` once the device's NMEA
/// 2000 NAME has resolved, else `src:<n>` — so a tile keeps pointing at
/// "that engine" / "that tank" across reconnects, the same way per-device
/// settings already do.
class DashboardTile {
  const DashboardTile({
    required this.id,
    required this.metric,
    required this.deviceKey,
    this.deviceSrcHint,
    this.unitIndex = 0,
    this.kind = DashboardTileKind.metric,
  });

  final String id;
  final DashboardMetricType metric;
  final String deviceKey;

  /// Last known source address for [deviceKey]. Used only as a fallback
  /// match if the NAME never resolved and the source address later changes.
  final int? deviceSrcHint;

  /// Index into the metric's `DashboardMetricSpec.units` list — which unit
  /// (e.g. kn vs m/s) this tile currently displays. Cycled by tapping the
  /// tile's icon; clamped to a valid index by the catalog if the list ever
  /// shrinks.
  final int unitIndex;

  final DashboardTileKind kind;

  DashboardTile copyWith({
    int? deviceSrcHint,
    String? deviceKey,
    int? unitIndex,
    DashboardMetricType? metric,
    DashboardTileKind? kind,
  }) {
    return DashboardTile(
      id: id,
      metric: metric ?? this.metric,
      deviceKey: deviceKey ?? this.deviceKey,
      deviceSrcHint: deviceSrcHint ?? this.deviceSrcHint,
      unitIndex: unitIndex ?? this.unitIndex,
      kind: kind ?? this.kind,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'metric': metric.name,
        'deviceKey': deviceKey,
        if (deviceSrcHint != null) 'deviceSrcHint': deviceSrcHint,
        if (unitIndex != 0) 'unitIndex': unitIndex,
        if (kind != DashboardTileKind.metric) 'kind': kind.name,
      };

  static DashboardTile? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final metricName = json['metric'];
    final deviceKey = json['deviceKey'];
    if (id is! String || metricName is! String || deviceKey is! String) {
      return null;
    }
    final metric = _metricFromName(metricName);
    if (metric == null) return null;
    final hint = json['deviceSrcHint'];
    final unitIndex = json['unitIndex'];
    return DashboardTile(
      id: id,
      metric: metric,
      deviceKey: deviceKey,
      deviceSrcHint: hint is num ? hint.toInt() : null,
      unitIndex: unitIndex is num ? unitIndex.toInt() : 0,
      kind: _tileKindFromName(json['kind'] as String?),
    );
  }
}

/// A user-defined dashboard: a name, an icon, an optional auto-detect tag,
/// and the ordered list of tiles it displays.
class DashboardLayout {
  const DashboardLayout({
    required this.id,
    required this.name,
    required this.iconKey,
    this.modeTag,
    this.tiles = const <DashboardTile>[],
  });

  final String id;
  final String name;

  /// Key into the curated icon lookup (UI layer) — kept as a plain string
  /// here so this model stays free of Flutter imports, like the other
  /// models in this directory.
  final String iconKey;
  final DashboardModeTag? modeTag;
  final List<DashboardTile> tiles;

  DashboardLayout copyWith({
    String? name,
    String? iconKey,
    bool clearModeTag = false,
    DashboardModeTag? modeTag,
    List<DashboardTile>? tiles,
  }) {
    return DashboardLayout(
      id: id,
      name: name ?? this.name,
      iconKey: iconKey ?? this.iconKey,
      modeTag: clearModeTag ? null : (modeTag ?? this.modeTag),
      tiles: tiles ?? this.tiles,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'iconKey': iconKey,
        if (modeTag != null) 'modeTag': modeTag!.name,
        'tiles': tiles.map((t) => t.toJson()).toList(),
      };

  static DashboardLayout? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final iconKey = json['iconKey'];
    if (id is! String || name is! String || iconKey is! String) {
      return null;
    }

    final tilesRaw = json['tiles'];
    final tiles = <DashboardTile>[];
    if (tilesRaw is List) {
      for (final entry in tilesRaw) {
        if (entry is Map) {
          final tile = DashboardTile.fromJson(Map<String, dynamic>.from(entry));
          if (tile != null) tiles.add(tile);
        }
      }
    }

    return DashboardLayout(
      id: id,
      name: name,
      iconKey: iconKey,
      modeTag: _modeTagFromName(json['modeTag'] as String?),
      tiles: List<DashboardTile>.unmodifiable(tiles),
    );
  }
}
