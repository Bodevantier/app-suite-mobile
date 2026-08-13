import 'package:flutter/foundation.dart';

/// One timestamped temperature reading.
class TempHistorySample {
  const TempHistorySample(this.timestamp, this.celsius);

  final DateTime timestamp;
  final double celsius;
}

/// All-time low/high for one temperature source, with when each occurred.
class TempRecord {
  const TempRecord({this.minC, this.minAt, this.maxC, this.maxAt});

  final double? minC;
  final DateTime? minAt;
  final double? maxC;
  final DateTime? maxAt;

  Map<String, dynamic> toJson() => {
        if (minC != null) 'minC': minC,
        if (minAt != null) 'minAt': minAt!.millisecondsSinceEpoch,
        if (maxC != null) 'maxC': maxC,
        if (maxAt != null) 'maxAt': maxAt!.millisecondsSinceEpoch,
      };

  factory TempRecord.fromJson(Map<String, dynamic> json) {
    DateTime? ts(dynamic v) =>
        v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    final minC = json['minC'];
    final maxC = json['maxC'];
    return TempRecord(
      minC: minC is num ? minC.toDouble() : null,
      minAt: ts(json['minAt']),
      maxC: maxC is num ? maxC.toDouble() : null,
      maxAt: ts(json['maxAt']),
    );
  }
}

/// Rolling temperature history + all-time high/low record, kept per N2K
/// source address so multiple temperature sensors on the bus (e.g. fridge
/// vs. cabin) don't mix into the same log.
///
/// Fed from [BleController] telemetry updates at app-dependency construction
/// time (see `AppDependencies.standard()`), not from any page — so history
/// keeps accumulating regardless of which page is currently open. The
/// all-time record is additionally persisted via `AppPreferencesService` so
/// it survives app restarts.
class TemperatureHistoryService extends ChangeNotifier {
  static const historyWindow = Duration(hours: 24);

  /// Chart samples are only stored when the value has moved or this much
  /// time has passed since the last stored point — bounds memory over a
  /// 24 h window regardless of how often unrelated telemetry (e.g. wind)
  /// triggers a notification. The all-time record below is unaffected by
  /// this throttle and checks every incoming sample.
  static const _minStoreInterval = Duration(seconds: 10);

  final Map<int, List<TempHistorySample>> _bySource = {};
  final Map<int, TempRecord> _records = {};
  final Map<int, DateTime> _lastStoredAt = {};
  final Map<int, double> _lastStoredValue = {};

  /// Rolling history for one source address, oldest first.
  List<TempHistorySample> historyFor(int sourceAddress) =>
      List.unmodifiable(_bySource[sourceAddress] ?? const []);

  /// All-time low/high for one source address.
  TempRecord recordFor(int sourceAddress) =>
      _records[sourceAddress] ?? const TempRecord();

  /// Feed a new reading. Returns true if this sample set a new all-time
  /// high or low, so the caller can persist the record.
  bool addSample(int sourceAddress, double celsius, DateTime timestamp) {
    final lastAt = _lastStoredAt[sourceAddress];
    final lastValue = _lastStoredValue[sourceAddress];
    final shouldStore = lastAt == null ||
        celsius != lastValue ||
        timestamp.difference(lastAt) >= _minStoreInterval;
    if (shouldStore) {
      final list = _bySource.putIfAbsent(sourceAddress, () => []);
      list.add(TempHistorySample(timestamp, celsius));
      final cutoff = timestamp.subtract(historyWindow);
      while (list.isNotEmpty && list.first.timestamp.isBefore(cutoff)) {
        list.removeAt(0);
      }
      _lastStoredAt[sourceAddress] = timestamp;
      _lastStoredValue[sourceAddress] = celsius;
    }

    var current = _records[sourceAddress] ?? const TempRecord();
    var recordChanged = false;
    if (current.minC == null || celsius < current.minC!) {
      current = TempRecord(
        minC: celsius,
        minAt: timestamp,
        maxC: current.maxC,
        maxAt: current.maxAt,
      );
      recordChanged = true;
    }
    if (current.maxC == null || celsius > current.maxC!) {
      current = TempRecord(
        minC: current.minC,
        minAt: current.minAt,
        maxC: celsius,
        maxAt: timestamp,
      );
      recordChanged = true;
    }
    if (recordChanged) {
      _records[sourceAddress] = current;
    }

    notifyListeners();
    return recordChanged;
  }

  /// Restore all-time records from persisted JSON (`{"<src>": {...}}`).
  void seedRecordsFromJson(Map<String, dynamic> json) {
    var changed = false;
    json.forEach((key, value) {
      final src = int.tryParse(key);
      if (src == null || value is! Map<String, dynamic>) return;
      _records[src] = TempRecord.fromJson(value);
      changed = true;
    });
    if (changed) notifyListeners();
  }

  Map<String, dynamic> recordsToJson() => {
        for (final entry in _records.entries)
          entry.key.toString(): entry.value.toJson(),
      };
}
