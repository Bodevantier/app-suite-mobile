import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// One timestamped scalar sample (m/s for speeds, dimensionless for vector
/// components).
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

/// Per-window summary (avg / min / max) for a single scalar series.
class WindWindowStats {
  const WindWindowStats({this.average, this.min, this.max});

  final double? average;
  final double? min;
  final double? max;

  /// Gust factor = max / average. >1 means peaks above the mean.
  double? get gustFactor {
    final a = average;
    final m = max;
    if (a == null || m == null || a <= 0) return null;
    return m / a;
  }
}

/// Vector-mean direction summary: mean direction (0–360°), steadiness
/// (0–1, mean resultant length — 1 = wind always from same direction), and
/// oscillation amplitude (max-min of TWD relative to the mean, 0–360).
class WindDirectionStats {
  const WindDirectionStats({
    this.meanDeg,
    this.steadiness,
    this.oscillationDeg,
  });

  final double? meanDeg;
  final double? steadiness;
  final double? oscillationDeg;
}

/// Records and aggregates rolling wind / boat statistics.
///
/// **Two-tier sampling** keeps memory bounded while supporting both
/// short-horizon and long-horizon windows:
///
///  * **Fast tier** — 1 sample / second, 65 min retention. Drives the
///    60 s / 5 min / 30 min / 1 h windows.
///  * **Slow tier** — 1 sample / minute, 25 h retention. Drives the
///    6 h / 24 h windows.
///
/// **Time-weighted averaging** (sample-and-hold integral, see [_stats])
/// makes results robust to bursty telemetry, dropouts, and irregular sample
/// rates. A coverage gate (≥ 60 % of the window must contain real data)
/// avoids labelling sparse data as e.g. a "30-minute average".
///
/// **Stationary boat handling** matches `TelemetryData._computedTrueWind()`:
/// VMG and circular wind direction are only sampled when SOG ≥ 0.25 m/s,
/// otherwise GPS noise dominates.
///
/// **Session counters** (tack count, distance sailed, peak gust + when)
/// accumulate from service construction (or restored from prefs).
///
/// Persistence: fast TWS/AWS queues + session counters via [twsToJson],
/// [awsToJson], [sessionToJson]; restored via [seedFromJson] /
/// [seedSessionFromJson]. Slow tier is rebuilt from scratch on restart —
/// it would nearly double persisted size for marginal benefit (24 h history
/// mostly matters within a single sail).
class WindAveragesService extends ChangeNotifier {
  // ── Config ────────────────────────────────────────────────────────────────

  static const _fastInterval = Duration(seconds: 1);
  static const _fastMaxAge = Duration(minutes: 65);
  static const _slowInterval = Duration(seconds: 60);
  static const _slowMaxAge = Duration(hours: 25);

  static const _minCoverage = 0.6;

  /// SOG below this is treated as "not moving" — VMG / TWD not sampled.
  static const _vmgSogThresholdMs = 0.25;

  /// A held sample is only extrapolated forward this long inside the
  /// time-weighted integral — prevents a frozen reading from quietly
  /// dominating long windows after a disconnection.
  static const _staleAfter = Duration(seconds: 8);

  /// A tack is only counted when the boat stays on the new side of the wind
  /// for at least this long. Filters out noise around head-to-wind.
  static const _tackHoldDuration = Duration(seconds: 5);

  // ── Storage ───────────────────────────────────────────────────────────────

  // Fast tier (1 Hz, 65 min)
  final ListQueue<WindSample> _fastTws = ListQueue();
  final ListQueue<WindSample> _fastAws = ListQueue();
  final ListQueue<WindSample> _fastSog = ListQueue();
  final ListQueue<WindSample> _fastVmg = ListQueue();
  // True Wind Direction (FROM, earth frame), unit-vector decomposition for
  // circular averaging.
  final ListQueue<WindSample> _fastTwdX = ListQueue();
  final ListQueue<WindSample> _fastTwdY = ListQueue();

  // Slow tier (1 / min, 25 h)
  final ListQueue<WindSample> _slowTws = ListQueue();
  final ListQueue<WindSample> _slowAws = ListQueue();
  final ListQueue<WindSample> _slowSog = ListQueue();
  final ListQueue<WindSample> _slowVmg = ListQueue();
  final ListQueue<WindSample> _slowTwdX = ListQueue();
  final ListQueue<WindSample> _slowTwdY = ListQueue();

  DateTime? _lastFastSampleAt;
  DateTime? _lastSlowSampleAt;
  DateTime? _lastDistanceSampleAt;

  double? _lastTws;
  double? _lastAws;
  double? _lastSog;
  double? _lastVmgInstant;

  // Session counters
  final DateTime _sessionStart = DateTime.now();
  int _tackCount = 0;
  double _distanceNm = 0;
  double? _peakTwsMs;
  DateTime? _peakTwsAt;
  double? _peakGustGustinessAtPeak;

  // Tack detection state machine
  int _windSide = 0; // 1 starboard, -1 port, 0 unknown
  int _pendingSide = 0;
  DateTime? _pendingSideSince;

  // ── Live values ───────────────────────────────────────────────────────────

  double? get currentTwsMs => _lastTws;
  double? get currentAwsMs => _lastAws;
  double? get currentSogMs => _lastSog;
  double? get currentVmgMs => _lastVmgInstant;

  /// Beaufort force (0–12) for the most recent TWS.
  int? get beaufort {
    final tws = _lastTws;
    if (tws == null) return null;
    const ranges = [0.5, 1.5, 3.3, 5.5, 7.9, 10.7, 13.8, 17.1, 20.7, 24.4, 28.4, 32.6];
    for (var i = 0; i < ranges.length; i++) {
      if (tws < ranges[i]) return i;
    }
    return 12;
  }

  String? get beaufortLabel {
    const labels = [
      'Calm', 'Light air', 'Light breeze', 'Gentle breeze', 'Moderate breeze',
      'Fresh breeze', 'Strong breeze', 'Near gale', 'Gale', 'Strong gale',
      'Storm', 'Violent storm', 'Hurricane',
    ];
    final b = beaufort;
    if (b == null) return null;
    return labels[b];
  }

  // ── Session totals ────────────────────────────────────────────────────────

  DateTime get sessionStart => _sessionStart;
  Duration get sessionDuration => DateTime.now().difference(_sessionStart);
  int get tackCount => _tackCount;
  double get distanceNm => _distanceNm;
  double? get peakTwsMs => _peakTwsMs;
  DateTime? get peakTwsAt => _peakTwsAt;
  double? get peakTwsGustinessAtPeak => _peakGustGustinessAtPeak;

  /// How long we have been collecting fast-tier TWS samples.
  Duration get collectionSpan {
    if (_fastTws.length < 2) return Duration.zero;
    return _fastTws.last.timestamp.difference(_fastTws.first.timestamp);
  }

  int get twsSampleCount => _fastTws.length;
  int get awsSampleCount => _fastAws.length;

  // ── Window summaries ──────────────────────────────────────────────────────

  bool _useFast(Duration window) => window <= _fastMaxAge;

  WindWindowStats twsStats(Duration window) =>
      _stats(_useFast(window) ? _fastTws : _slowTws, window);
  WindWindowStats awsStats(Duration window) =>
      _stats(_useFast(window) ? _fastAws : _slowAws, window);
  WindWindowStats sogStats(Duration window) =>
      _stats(_useFast(window) ? _fastSog : _slowSog, window);
  WindWindowStats vmgStats(Duration window) =>
      _stats(_useFast(window) ? _fastVmg : _slowVmg, window);

  WindDirectionStats directionStats(Duration window) {
    final useFast = _useFast(window);
    final xs = useFast ? _fastTwdX : _slowTwdX;
    final ys = useFast ? _fastTwdY : _slowTwdY;
    return _directionStats(xs, ys, window);
  }

  // Backwards-compatible shorthands for existing UI.
  double? get tws60s => twsStats(const Duration(seconds: 60)).average;
  double? get tws5min => twsStats(const Duration(minutes: 5)).average;
  double? get tws30min => twsStats(const Duration(minutes: 30)).average;
  double? get aws60s => awsStats(const Duration(seconds: 60)).average;
  double? get aws5min => awsStats(const Duration(minutes: 5)).average;
  double? get aws30min => awsStats(const Duration(minutes: 30)).average;
  double? get vmgMs => _lastVmgInstant;
  double? get vmg60s => vmgStats(const Duration(seconds: 60)).average;
  double? get vmg5min => vmgStats(const Duration(minutes: 5)).average;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Feed a new measurement. All numeric arguments are optional; pass the
  /// subset of telemetry currently valid. [headingDeg] (true heading) is
  /// required for true wind *direction* statistics — without it the
  /// direction-stats methods return nulls.
  void addSample({
    double? twsMs,
    double? awsMs,
    double? twaDeg,
    double? sogMs,
    double? headingDeg,
    DateTime? timestamp,
  }) {
    final now = timestamp ?? DateTime.now();

    // Continuous (every-call) accumulators. These must NOT be subsampled
    // because they drive cumulative session counters.
    _accumulateDistance(now, sogMs);
    _updateTackState(now, twaDeg);
    _updatePeakGust(now, twsMs);

    // Live mirrors (used by current* getters and by Beaufort).
    if (twsMs != null) _lastTws = twsMs;
    if (awsMs != null) _lastAws = awsMs;
    if (sogMs != null) _lastSog = sogMs;
    if (sogMs != null && sogMs >= _vmgSogThresholdMs && twaDeg != null) {
      _lastVmgInstant = sogMs * math.cos(twaDeg * math.pi / 180);
    } else {
      _lastVmgInstant = null;
    }

    if (_lastFastSampleAt == null ||
        now.difference(_lastFastSampleAt!) >= _fastInterval) {
      _lastFastSampleAt = now;
      _appendTier(
        fast: true,
        now: now,
        twsMs: twsMs,
        awsMs: awsMs,
        twaDeg: twaDeg,
        sogMs: sogMs,
        headingDeg: headingDeg,
      );
    }
    if (_lastSlowSampleAt == null ||
        now.difference(_lastSlowSampleAt!) >= _slowInterval) {
      _lastSlowSampleAt = now;
      _appendTier(
        fast: false,
        now: now,
        twsMs: twsMs,
        awsMs: awsMs,
        twaDeg: twaDeg,
        sogMs: sogMs,
        headingDeg: headingDeg,
      );
    }

    notifyListeners();
  }

  /// Reset session-cumulative counters. Buffered samples are preserved.
  void resetSessionCounters() {
    _tackCount = 0;
    _distanceNm = 0;
    _peakTwsMs = null;
    _peakTwsAt = null;
    _peakGustGustinessAtPeak = null;
    notifyListeners();
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  List<Map<String, dynamic>> twsToJson() =>
      _fastTws.map((s) => s.toJson()).toList();

  List<Map<String, dynamic>> awsToJson() =>
      _fastAws.map((s) => s.toJson()).toList();

  Map<String, dynamic> sessionToJson() => {
        'tacks': _tackCount,
        'distNm': _distanceNm,
        if (_peakTwsMs != null) 'peakTws': _peakTwsMs,
        if (_peakTwsAt != null)
          'peakTwsAt': _peakTwsAt!.millisecondsSinceEpoch,
      };

  void seedFromJson({
    required List<dynamic> twsSamples,
    required List<dynamic> awsSamples,
  }) {
    final cutoff = DateTime.now().subtract(_fastMaxAge);
    _seedQueue(_fastTws, twsSamples, cutoff);
    _seedQueue(_fastAws, awsSamples, cutoff);
    if (_fastTws.isNotEmpty) _lastTws = _fastTws.last.speedMs;
    if (_fastAws.isNotEmpty) _lastAws = _fastAws.last.speedMs;
    if (_fastTws.isNotEmpty || _fastAws.isNotEmpty) notifyListeners();
  }

  void seedSessionFromJson(Map<String, dynamic>? json) {
    if (json == null) return;
    _tackCount = (json['tacks'] as num?)?.toInt() ?? 0;
    _distanceNm = (json['distNm'] as num?)?.toDouble() ?? 0;
    final peak = json['peakTws'];
    if (peak is num) _peakTwsMs = peak.toDouble();
    final peakAt = json['peakTwsAt'];
    if (peakAt is num) {
      _peakTwsAt = DateTime.fromMillisecondsSinceEpoch(peakAt.toInt());
    }
    notifyListeners();
  }

  // ── Internal: continuous accumulation ─────────────────────────────────────

  void _accumulateDistance(DateTime now, double? sogMs) {
    // Trapezoidal SOG integral. Skip the first call (no prior dt) and any
    // gap > 30 s (likely a dropout, not real travel).
    if (sogMs == null || sogMs < _vmgSogThresholdMs) {
      _lastDistanceSampleAt = now;
      return;
    }
    final prior = _lastDistanceSampleAt;
    final priorSog = _lastSog;
    _lastDistanceSampleAt = now;
    if (prior == null || priorSog == null) return;
    final dtSec = now.difference(prior).inMicroseconds / 1e6;
    if (dtSec <= 0 || dtSec > 30) return;
    final avgSog = (priorSog + sogMs) / 2;
    _distanceNm += (avgSog * dtSec) / 1852.0;
  }

  void _updateTackState(DateTime now, double? twaDeg) {
    if (twaDeg == null) return;
    var twa = twaDeg % 360;
    if (twa < 0) twa += 360;

    // Side of wind in boat frame; exclude the 0° / 180° axes (head-to-wind
    // and dead downwind shouldn't trigger a side change).
    final int side;
    if (twa > 1 && twa < 179) {
      side = 1; // starboard
    } else if (twa > 181 && twa < 359) {
      side = -1; // port
    } else {
      return;
    }

    if (_windSide == 0) {
      _windSide = side;
      _pendingSide = 0;
      return;
    }

    if (side == _windSide) {
      _pendingSide = 0;
      _pendingSideSince = null;
      return;
    }

    if (_pendingSide != side) {
      _pendingSide = side;
      _pendingSideSince = now;
      return;
    }
    final since = _pendingSideSince;
    if (since != null && now.difference(since) >= _tackHoldDuration) {
      _windSide = side;
      _pendingSide = 0;
      _pendingSideSince = null;
      _tackCount++;
    }
  }

  void _updatePeakGust(DateTime now, double? twsMs) {
    if (twsMs == null) return;
    if (_peakTwsMs == null || twsMs > _peakTwsMs!) {
      _peakTwsMs = twsMs;
      _peakTwsAt = now;
      // NOAA-style gustiness ratio: gust / 5-min mean.
      final mean5 = twsStats(const Duration(minutes: 5)).average;
      if (mean5 != null && mean5 > 0) {
        _peakGustGustinessAtPeak = twsMs / mean5;
      }
    }
  }

  // ── Internal: tier append ─────────────────────────────────────────────────

  void _appendTier({
    required bool fast,
    required DateTime now,
    double? twsMs,
    double? awsMs,
    double? twaDeg,
    double? sogMs,
    double? headingDeg,
  }) {
    final cutoff = now.subtract(fast ? _fastMaxAge : _slowMaxAge);
    final tws = fast ? _fastTws : _slowTws;
    final aws = fast ? _fastAws : _slowAws;
    final sog = fast ? _fastSog : _slowSog;
    final vmg = fast ? _fastVmg : _slowVmg;
    final twdX = fast ? _fastTwdX : _slowTwdX;
    final twdY = fast ? _fastTwdY : _slowTwdY;

    if (twsMs != null) _addAndTrim(tws, twsMs, now, cutoff);
    if (awsMs != null) _addAndTrim(aws, awsMs, now, cutoff);
    if (sogMs != null) _addAndTrim(sog, sogMs, now, cutoff);
    if (sogMs != null && sogMs >= _vmgSogThresholdMs && twaDeg != null) {
      _addAndTrim(vmg, sogMs * math.cos(twaDeg * math.pi / 180), now, cutoff);
    }
    // True Wind Direction (FROM): heading + TWA.  Boat must have steerage
    // for the direction to be meaningful.
    if (headingDeg != null &&
        twaDeg != null &&
        sogMs != null &&
        sogMs >= _vmgSogThresholdMs) {
      var twd = (headingDeg + twaDeg) % 360;
      if (twd < 0) twd += 360;
      final rad = twd * math.pi / 180;
      _addAndTrim(twdX, math.sin(rad), now, cutoff);
      _addAndTrim(twdY, math.cos(rad), now, cutoff);
    }
  }

  void _seedQueue(
    ListQueue<WindSample> queue,
    List<dynamic> raw,
    DateTime cutoff,
  ) {
    queue.clear();
    final samples = raw
        .whereType<Map<String, dynamic>>()
        .map(WindSample.fromJson)
        .where((s) => s.timestamp.isAfter(cutoff))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    queue.addAll(samples);
  }

  void _addAndTrim(
    ListQueue<WindSample> queue,
    double value,
    DateTime now,
    DateTime cutoff,
  ) {
    queue.addLast(WindSample(timestamp: now, speedMs: value));
    while (queue.isNotEmpty && queue.first.timestamp.isBefore(cutoff)) {
      queue.removeFirst();
    }
  }

  // ── Internal: window math ─────────────────────────────────────────────────

  /// Time-weighted (sample-and-hold) avg / min / max over [window].
  WindWindowStats _stats(ListQueue<WindSample> queue, Duration window) {
    if (queue.isEmpty) return const WindWindowStats();

    final now = DateTime.now();
    final windowStart = now.subtract(window);
    final windowMicros = window.inMicroseconds.toDouble();

    final samples = queue.toList(growable: false);

    double area = 0;
    double coverageMicros = 0;
    double? minV;
    double? maxV;

    for (var i = 0; i < samples.length; i++) {
      final segStart = samples[i].timestamp;
      final DateTime segEnd;
      if (i + 1 < samples.length) {
        segEnd = samples[i + 1].timestamp;
      } else {
        final maxHold = segStart.add(_staleAfter);
        segEnd = maxHold.isBefore(now) ? maxHold : now;
      }

      final clipStart = segStart.isBefore(windowStart) ? windowStart : segStart;
      final clipEnd = segEnd.isAfter(now) ? now : segEnd;
      if (!clipEnd.isAfter(clipStart)) continue;

      final dt = clipEnd.difference(clipStart).inMicroseconds.toDouble();
      area += samples[i].speedMs * dt;
      coverageMicros += dt;

      // Min/max include any sample that contributed time within the window —
      // matches what users expect from "highest gust in last 5 min".
      final v = samples[i].speedMs;
      if (minV == null || v < minV) minV = v;
      if (maxV == null || v > maxV) maxV = v;
    }

    if (coverageMicros < windowMicros * _minCoverage || coverageMicros <= 0) {
      return const WindWindowStats();
    }
    return WindWindowStats(
      average: area / coverageMicros,
      min: minV,
      max: maxV,
    );
  }

  /// Vector mean of unit-vector components over [window]. Returns the mean
  /// direction (0–360°), the mean resultant length (0–1, "steadiness"), and
  /// the angular oscillation amplitude (max-min relative to the mean).
  WindDirectionStats _directionStats(
    ListQueue<WindSample> xs,
    ListQueue<WindSample> ys,
    Duration window,
  ) {
    if (xs.isEmpty || ys.isEmpty) return const WindDirectionStats();
    final now = DateTime.now();
    final windowStart = now.subtract(window);
    final windowMicros = window.inMicroseconds.toDouble();

    final xList = xs.toList(growable: false);
    final yList = ys.toList(growable: false);
    final n = math.min(xList.length, yList.length);

    double sumX = 0;
    double sumY = 0;
    double coverageMicros = 0;
    final degsInWindow = <double>[];

    for (var i = 0; i < n; i++) {
      final segStart = xList[i].timestamp;
      final DateTime segEnd;
      if (i + 1 < n) {
        segEnd = xList[i + 1].timestamp;
      } else {
        final maxHold = segStart.add(_staleAfter);
        segEnd = maxHold.isBefore(now) ? maxHold : now;
      }
      final clipStart = segStart.isBefore(windowStart) ? windowStart : segStart;
      final clipEnd = segEnd.isAfter(now) ? now : segEnd;
      if (!clipEnd.isAfter(clipStart)) continue;
      final dt = clipEnd.difference(clipStart).inMicroseconds.toDouble();

      sumX += xList[i].speedMs * dt;
      sumY += yList[i].speedMs * dt;
      coverageMicros += dt;

      var deg = math.atan2(xList[i].speedMs, yList[i].speedMs) * 180 / math.pi;
      if (deg < 0) deg += 360;
      degsInWindow.add(deg);
    }

    if (coverageMicros < windowMicros * _minCoverage || coverageMicros <= 0) {
      return const WindDirectionStats();
    }
    final mx = sumX / coverageMicros;
    final my = sumY / coverageMicros;
    var meanDeg = math.atan2(mx, my) * 180 / math.pi;
    if (meanDeg < 0) meanDeg += 360;
    final steadiness = math.sqrt(mx * mx + my * my).clamp(0.0, 1.0);

    double? lo;
    double? hi;
    for (final d in degsInWindow) {
      var off = (d - meanDeg) % 360;
      if (off > 180) off -= 360;
      if (off < -180) off += 360;
      if (lo == null || off < lo) lo = off;
      if (hi == null || off > hi) hi = off;
    }
    final osc = (hi != null && lo != null) ? (hi - lo) : null;

    return WindDirectionStats(
      meanDeg: meanDeg,
      steadiness: steadiness,
      oscillationDeg: osc,
    );
  }
}

