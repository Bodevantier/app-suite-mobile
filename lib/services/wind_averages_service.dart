import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// A single timestamped wind-speed sample (m/s).
class WindSample {
  const WindSample({required this.timestamp, required this.speedMs});

  final DateTime timestamp;
  final double speedMs;

  Map<String, dynamic> toJson() => {
        'ts': timestamp.millisecondsSinceEpoch,
        'v': speedMs,
      };

  factory WindSample.fromJson(Map<String, dynamic> json) => WindSample(
        timestamp:
            DateTime.fromMillisecondsSinceEpoch((json['ts'] as num).toInt()),
        speedMs: (json['v'] as num).toDouble(),
      );
}

/// Computes rolling time-window averages for True Wind Speed (TWS) and
/// Apparent Wind Speed (AWS), and VMG.
///
/// Mirrors the logic in the STM32 wind_averages.c but runs on the phone so
/// history survives boat power-cycles (data is persisted by [AppPreferencesService]).
///
/// Windows: 60 s, 5 min, 30 min.
/// Subsampling: at most one sample per second is accepted (same as the fast
/// ring on the STM32) to keep the list small.
class WindAveragesService extends ChangeNotifier {
  static const _maxAge = Duration(minutes: 31);
  static const _minInterval = Duration(seconds: 1);
  static const _minSamplesForAvg = 2;

  final List<WindSample> _tws = [];
  final List<WindSample> _aws = [];

  DateTime? _lastSampleAt;
  double? _lastVmgMs;

  // ── Averages (null = not enough data yet) ────────────────────────────────

  double? get tws60s => _windowAvg(_tws, const Duration(seconds: 60));
  double? get tws5min => _windowAvg(_tws, const Duration(minutes: 5));
  double? get tws30min => _windowAvg(_tws, const Duration(minutes: 30));

  double? get aws60s => _windowAvg(_aws, const Duration(seconds: 60));
  double? get aws5min => _windowAvg(_aws, const Duration(minutes: 5));
  double? get aws30min => _windowAvg(_aws, const Duration(minutes: 30));

  /// VMG (m/s) = SOG × cos(TWA).  Positive toward wind, negative downwind.
  /// Uses the most recently supplied SOG and TWA pair.
  double? get vmgMs => _lastVmgMs;

  /// How long we have been collecting TWS data.
  Duration get collectionSpan {
    if (_tws.length < 2) return Duration.zero;
    return _tws.last.timestamp.difference(_tws.first.timestamp);
  }

  int get twsSampleCount => _tws.length;
  int get awsSampleCount => _aws.length;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Feed a new measurement.  Call this every time the telemetry updates.
  void addSample({
    required double twsMs,
    double? awsMs,
    double? twaDeg,
    double? sogMs,
    DateTime? timestamp,
  }) {
    final now = timestamp ?? DateTime.now();

    // Subsample: skip if less than 1 s since last accepted sample.
    if (_lastSampleAt != null &&
        now.difference(_lastSampleAt!).inMilliseconds <
            _minInterval.inMilliseconds) {
      return;
    }
    _lastSampleAt = now;

    final cutoff = now.subtract(_maxAge);

    _addAndTrim(_tws, twsMs, now, cutoff);
    if (awsMs != null) {
      _addAndTrim(_aws, awsMs, now, cutoff);
    }

    // VMG = SOG × cos(TWA)
    if (sogMs != null &&
        sogMs >= 0.1 &&
        twaDeg != null) {
      _lastVmgMs = sogMs * math.cos(twaDeg * math.pi / 180);
    }

    notifyListeners();
  }

  // ── Persistence helpers ───────────────────────────────────────────────────

  List<Map<String, dynamic>> twsToJson() =>
      _tws.map((s) => s.toJson()).toList();

  List<Map<String, dynamic>> awsToJson() =>
      _aws.map((s) => s.toJson()).toList();

  /// Load samples from persisted JSON, discarding anything older than 31 min.
  void seedFromJson({
    required List<dynamic> twsSamples,
    required List<dynamic> awsSamples,
  }) {
    final cutoff = DateTime.now().subtract(_maxAge);
    _tws
      ..clear()
      ..addAll(
        twsSamples
            .whereType<Map<String, dynamic>>()
            .map(WindSample.fromJson)
            .where((s) => s.timestamp.isAfter(cutoff)),
      );
    _aws
      ..clear()
      ..addAll(
        awsSamples
            .whereType<Map<String, dynamic>>()
            .map(WindSample.fromJson)
            .where((s) => s.timestamp.isAfter(cutoff)),
      );
    if (_tws.isNotEmpty || _aws.isNotEmpty) {
      notifyListeners();
    }
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _addAndTrim(
    List<WindSample> list,
    double speedMs,
    DateTime now,
    DateTime cutoff,
  ) {
    list.add(WindSample(timestamp: now, speedMs: speedMs));
    // Remove from the front while entries are too old (list is append-only
    // so oldest entries are always at the front).
    while (list.isNotEmpty && list.first.timestamp.isBefore(cutoff)) {
      list.removeAt(0);
    }
  }

  double? _windowAvg(List<WindSample> samples, Duration window) {
    if (samples.isEmpty) return null;
    final now = DateTime.now();
    final cutoff = now.subtract(window);
    // Only compute this average if collection started at least [window] ago.
    // Otherwise a 90-second dataset would be labelled a "5-minute average".
    if (samples.first.timestamp.isAfter(cutoff)) return null;
    double sum = 0;
    int n = 0;
    for (final s in samples) {
      if (s.timestamp.isAfter(cutoff)) {
        sum += s.speedMs;
        n++;
      }
    }
    if (n < _minSamplesForAvg) return null;
    return sum / n;
  }
}
