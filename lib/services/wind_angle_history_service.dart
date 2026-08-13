import 'package:flutter/foundation.dart';

/// One timestamped wind-angle reading (degrees).
class AngleSample {
  const AngleSample(this.timestamp, this.angleDeg);

  final DateTime timestamp;
  final double angleDeg;
}

/// Rolling apparent/true wind-angle history for the wind trail/heatmap.
///
/// Fed from [BleController] telemetry updates at app-dependency construction
/// time (see `AppDependencies.standard()`), not from any page — so the trail
/// keeps accumulating regardless of which page is currently open. Retains a
/// fixed superset window; callers query down to whatever window they
/// currently want to display (matches the user-configurable 1-15 min trail
/// window in Wind Settings).
class WindAngleHistoryService extends ChangeNotifier {
  // Slightly above the largest selectable trail window (15 min).
  static const _retention = Duration(minutes: 16);

  final List<AngleSample> _apparent = [];
  final List<AngleSample> _true = [];

  List<AngleSample> apparentHistory(Duration window) =>
      _within(_apparent, window);

  List<AngleSample> trueHistory(Duration window) => _within(_true, window);

  void addSample({double? apparentDeg, double? trueDeg, DateTime? timestamp}) {
    final now = timestamp ?? DateTime.now();
    if (apparentDeg != null) _apparent.add(AngleSample(now, apparentDeg));
    if (trueDeg != null) _true.add(AngleSample(now, trueDeg));
    final cutoff = now.subtract(_retention);
    _trim(_apparent, cutoff);
    _trim(_true, cutoff);
    notifyListeners();
  }

  void clear() {
    _apparent.clear();
    _true.clear();
    notifyListeners();
  }

  static List<AngleSample> _within(List<AngleSample> list, Duration window) {
    final cutoff = DateTime.now().subtract(window);
    return List.unmodifiable(
      list.where((s) => s.timestamp.isAfter(cutoff)),
    );
  }

  static void _trim(List<AngleSample> list, DateTime cutoff) {
    while (list.isNotEmpty && list.first.timestamp.isBefore(cutoff)) {
      list.removeAt(0);
    }
  }
}
