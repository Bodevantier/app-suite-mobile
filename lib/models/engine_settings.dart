import 'package:shared_preferences/shared_preferences.dart';

/// Persisted RPM-calibration settings for an engine (PGN 127488) source.
///
/// The sensor reports RPM derived from the alternator **W-terminal** pulse
/// frequency. The number of electrical pulses per *engine* revolution depends
/// on the alternator's pole count and the engine→alternator pulley ratio:
///
/// ```
/// pulsesPerRev = (alternatorPoles / 2) * pulleyRatio
/// ```
///
/// The firmware ships with a fixed assumption ([sensorAssumedPulsesPerRev]),
/// so to show the correct engine RPM the app rescales the broadcast value:
///
/// ```
/// correctedRpm = rawRpm * (sensorAssumedPulsesPerRev / pulsesPerRev)
/// ```
///
/// With the defaults (6 poles, 2.0:1) `pulsesPerRev == 6`, which matches the
/// firmware assumption exactly — so out of the box the displayed RPM equals
/// the value the sensor broadcasts until the user enters their engine's data.
class EngineSettings {
  const EngineSettings({
    this.alternatorPoles = 6,
    this.pulleyRatio = 2.0,
    this.maxRpm = 6000,
  });

  /// Number of magnetic poles in the alternator (typically 6–16, always even).
  final int alternatorPoles;

  /// Engine pulley diameter ÷ alternator pulley diameter. The alternator spins
  /// faster than the engine, so this is normally > 1 (e.g. 2.0 means the
  /// alternator turns twice for every engine revolution).
  final double pulleyRatio;

  /// Full-scale value of the RPM gauge (the end of the dial).
  final int maxRpm;

  /// Pulses-per-engine-revolution the firmware assumes when it computes the
  /// RPM it broadcasts. Must match `RPM_PULSES_PER_REV` in the sensor firmware.
  static const double sensorAssumedPulsesPerRev = 6.0;

  /// Electrical pulses produced per engine revolution for this configuration.
  double get pulsesPerRev => (alternatorPoles / 2.0) * pulleyRatio;

  /// Multiplier applied to the broadcast RPM to obtain true engine RPM.
  double get correctionFactor {
    final ppr = pulsesPerRev;
    if (ppr <= 0) return 1.0;
    return sensorAssumedPulsesPerRev / ppr;
  }

  /// Applies the calibration to a raw broadcast RPM value.
  double? calibrate(double? rawRpm) =>
      rawRpm == null ? null : rawRpm * correctionFactor;

  static const _kPoles = 'engine_alternator_poles';
  static const _kRatio = 'engine_pulley_ratio';
  static const _kMaxRpm = 'engine_max_rpm';

  static Future<EngineSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return EngineSettings(
      alternatorPoles: prefs.getInt(_kPoles) ?? 6,
      pulleyRatio: prefs.getDouble(_kRatio) ?? 2.0,
      maxRpm: prefs.getInt(_kMaxRpm) ?? 6000,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPoles, alternatorPoles);
    await prefs.setDouble(_kRatio, pulleyRatio);
    await prefs.setInt(_kMaxRpm, maxRpm);
  }

  EngineSettings copyWith({
    int? alternatorPoles,
    double? pulleyRatio,
    int? maxRpm,
  }) {
    return EngineSettings(
      alternatorPoles: alternatorPoles ?? this.alternatorPoles,
      pulleyRatio: pulleyRatio ?? this.pulleyRatio,
      maxRpm: maxRpm ?? this.maxRpm,
    );
  }
}
