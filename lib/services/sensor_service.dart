import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Realtime Database schema
//
// devices/{deviceId}/
//   fan/                         { auto_mode, is_running, updated_at }
//   events/{timestamp_id}/       Category 1 – one entry per litter box visit
//     timestamp                  int (epoch ms or s) or ISO-8601 string
//     dwellTimeSeconds           number
//     depositMassGrams           number
//     peakAmmoniaPpm             number
//     peakOdorIndexPct           number
//     estimatedOutputType        0 = None/Straining, 1 = Urine, 2 = Feces, 3 = Both
//     fanPurgeDurationSeconds    number
//     catWeightGrams             number
//   daily_summary/{YYYY-MM-DD}/  Category 2 – one aggregate per day
//     date                       "YYYY-MM-DD"
//     totalVisits                int
//     totalStrainingMinutes      number
//     totalUrineOutputGrams      number
//     totalFecesOutputGrams      number
//     averageCatWeightKg         number
//     medianPeakAmmoniaPpm       number
//     medianPeakOdorPct          number
//     hourlyVisitDistribution    int[24]
// ---------------------------------------------------------------------------

/// Dwell time above which a visit is treated as straining (3 minutes).
const double kStrainingDwellSeconds = 180.0;

/// Sensor classification of what a visit produced.
enum OutputType {
  none(0), // None / dry straining
  urine(1),
  feces(2),
  both(3);

  const OutputType(this.code);
  final int code;

  static OutputType parse(dynamic raw) {
    if (raw is num) {
      final i = raw.toInt();
      return OutputType.values.firstWhere(
        (t) => t.code == i,
        orElse: () => OutputType.none,
      );
    }
    if (raw is String) {
      final asInt = int.tryParse(raw.trim());
      if (asInt != null) return parse(asInt);
      switch (raw.trim().toLowerCase()) {
        case 'urine':
          return OutputType.urine;
        case 'feces':
        case 'faeces':
          return OutputType.feces;
        case 'both':
          return OutputType.both;
      }
    }
    return OutputType.none;
  }
}

/// Category 1: a single litter box visit stored at
/// `devices/{deviceId}/events/{timestamp_id}`.
class LitterEvent {
  final String id;
  final DateTime timestamp;
  final double dwellTimeSeconds;
  final double depositMassGrams;
  final double peakAmmoniaPpm;
  final double peakOdorIndexPct;
  final OutputType estimatedOutputType;
  final double fanPurgeDurationSeconds;
  final double catWeightGrams;

  const LitterEvent({
    required this.id,
    required this.timestamp,
    required this.dwellTimeSeconds,
    this.depositMassGrams = 0.0,
    this.peakAmmoniaPpm = 0.0,
    this.peakOdorIndexPct = 0.0,
    this.estimatedOutputType = OutputType.none,
    this.fanPurgeDurationSeconds = 0.0,
    this.catWeightGrams = 0.0,
  });

  /// Visit lasted more than 3 minutes or produced no output.
  bool get isStraining =>
      dwellTimeSeconds > kStrainingDwellSeconds ||
      estimatedOutputType == OutputType.none;

  /// Grams attributed to urine. "Both" visits are split evenly.
  double get urineGrams => switch (estimatedOutputType) {
        OutputType.urine => depositMassGrams,
        OutputType.both => depositMassGrams / 2,
        _ => 0.0,
      };

  /// Grams attributed to feces. "Both" visits are split evenly.
  double get fecesGrams => switch (estimatedOutputType) {
        OutputType.feces => depositMassGrams,
        OutputType.both => depositMassGrams / 2,
        _ => 0.0,
      };

  static LitterEvent? fromMap(String id, Map<dynamic, dynamic> map) {
    final ts = _parseTimestamp(map['timestamp']) ?? _parseTimestamp(id);
    if (ts == null) return null;
    return LitterEvent(
      id: id,
      timestamp: ts,
      dwellTimeSeconds: _num(map['dwellTimeSeconds']),
      depositMassGrams: _num(map['depositMassGrams']),
      peakAmmoniaPpm: _num(map['peakAmmoniaPpm']),
      peakOdorIndexPct: _num(map['peakOdorIndexPct']),
      estimatedOutputType: OutputType.parse(map['estimatedOutputType']),
      fanPurgeDurationSeconds: _num(map['fanPurgeDurationSeconds']),
      catWeightGrams: _num(map['catWeightGrams']),
    );
  }

  Map<String, Object> toJson() => {
        'timestamp': timestamp.millisecondsSinceEpoch,
        'dwellTimeSeconds': dwellTimeSeconds,
        'depositMassGrams': depositMassGrams,
        'peakAmmoniaPpm': peakAmmoniaPpm,
        'peakOdorIndexPct': peakOdorIndexPct,
        'estimatedOutputType': estimatedOutputType.code,
        'fanPurgeDurationSeconds': fanPurgeDurationSeconds,
        'catWeightGrams': catWeightGrams,
      };

  /// Converts to the chart-facing [VisitRecord] used by Daily Analytics.
  VisitRecord toVisitRecord() {
    final local = timestamp.toLocal();
    final secs = dwellTimeSeconds.round();
    return VisitRecord(
      id: id,
      hourX: local.hour + local.minute / 60.0,
      timeLabel:
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
      durationSeconds: secs,
      durationMinutes: double.parse((dwellTimeSeconds / 60.0).toStringAsFixed(2)),
      ammoniaPpm: peakAmmoniaPpm,
      odorIndex: peakOdorIndexPct,
      depositGrams: depositMassGrams,
      catWeightGrams: catWeightGrams,
      outputType: estimatedOutputType,
      fanPurgeSeconds: fanPurgeDurationSeconds,
      status: isStraining ? 'straining' : 'normal',
    );
  }
}

/// Category 2: daily aggregate stored at
/// `devices/{deviceId}/daily_summary/{YYYY-MM-DD}`.
class DailySummary {
  final String date; // YYYY-MM-DD
  final int totalVisits;
  final double totalStrainingMinutes;
  final double totalUrineOutputGrams;
  final double totalFecesOutputGrams;
  final double averageCatWeightKg;
  final double medianPeakAmmoniaPpm;
  final double medianPeakOdorPct;
  final List<int> hourlyVisitDistribution; // length 24

  const DailySummary({
    required this.date,
    required this.totalVisits,
    required this.totalStrainingMinutes,
    required this.totalUrineOutputGrams,
    required this.totalFecesOutputGrams,
    required this.averageCatWeightKg,
    required this.medianPeakAmmoniaPpm,
    required this.medianPeakOdorPct,
    required this.hourlyVisitDistribution,
  });

  DateTime get day => DateTime.parse(date);

  static DailySummary? fromMap(String key, Map<dynamic, dynamic> map) {
    final date = (map['date'] as String?) ?? key;
    if (DateTime.tryParse(date) == null) return null;

    List<int> hourly = List<int>.filled(24, 0);
    final rawHourly = map['hourlyVisitDistribution'];
    if (rawHourly is List) {
      for (int h = 0; h < 24 && h < rawHourly.length; h++) {
        hourly[h] = (rawHourly[h] as num?)?.toInt() ?? 0;
      }
    } else if (rawHourly is Map) {
      // RTDB may return sparse arrays as maps of index -> value.
      rawHourly.forEach((k, v) {
        final h = int.tryParse(k.toString());
        if (h != null && h >= 0 && h < 24) hourly[h] = (v as num?)?.toInt() ?? 0;
      });
    }

    return DailySummary(
      date: date,
      totalVisits: _num(map['totalVisits']).toInt(),
      totalStrainingMinutes: _num(map['totalStrainingMinutes']),
      totalUrineOutputGrams: _num(map['totalUrineOutputGrams']),
      totalFecesOutputGrams: _num(map['totalFecesOutputGrams']),
      averageCatWeightKg: _num(map['averageCatWeightKg']),
      medianPeakAmmoniaPpm: _num(map['medianPeakAmmoniaPpm']),
      medianPeakOdorPct: _num(map['medianPeakOdorPct']),
      hourlyVisitDistribution: hourly,
    );
  }

  /// Builds a summary from raw events of a single day. Used for the current
  /// day (whose summary is only pushed at midnight) and for backfilling.
  factory DailySummary.fromEvents(String date, List<LitterEvent> events) {
    final hourly = List<int>.filled(24, 0);
    for (final e in events) {
      hourly[e.timestamp.toLocal().hour]++;
    }
    final strainingSec = events
        .where((e) => e.isStraining)
        .fold<double>(0, (s, e) => s + e.dwellTimeSeconds);
    final weights = events
        .where((e) => e.catWeightGrams > 0)
        .map((e) => e.catWeightGrams / 1000.0)
        .toList();

    return DailySummary(
      date: date,
      totalVisits: events.length,
      totalStrainingMinutes: _round(strainingSec / 60.0, 2),
      totalUrineOutputGrams:
          _round(events.fold<double>(0, (s, e) => s + e.urineGrams), 1),
      totalFecesOutputGrams:
          _round(events.fold<double>(0, (s, e) => s + e.fecesGrams), 1),
      averageCatWeightKg: _round(_median(weights), 3),
      medianPeakAmmoniaPpm:
          _round(_median(events.map((e) => e.peakAmmoniaPpm).toList()), 1),
      medianPeakOdorPct:
          _round(_median(events.map((e) => e.peakOdorIndexPct).toList()), 1),
      hourlyVisitDistribution: hourly,
    );
  }

  Map<String, Object> toJson() => {
        'date': date,
        'totalVisits': totalVisits,
        'totalStrainingMinutes': totalStrainingMinutes,
        'totalUrineOutputGrams': totalUrineOutputGrams,
        'totalFecesOutputGrams': totalFecesOutputGrams,
        'averageCatWeightKg': averageCatWeightKg,
        'medianPeakAmmoniaPpm': medianPeakAmmoniaPpm,
        'medianPeakOdorPct': medianPeakOdorPct,
        'hourlyVisitDistribution': hourlyVisitDistribution,
      };
}

// ---------------------------------------------------------------------------
// Chart-facing view models (consumed by the analytics & home screens)
// ---------------------------------------------------------------------------

class VisitRecord {
  final String id;
  final double hourX; // 0.0 (00:00) to 23.99 (23:59)
  final String timeLabel; // "HH:mm"
  final double durationMinutes;
  final int durationSeconds;
  final double ammoniaPpm; // Peak NH3 ppm
  final double odorIndex; // Peak odor 0 - 100 %
  final double depositGrams; // Load cell delta (ΔWeight in grams)
  final double catWeightGrams;
  final OutputType outputType;
  final double fanPurgeSeconds;
  final String status;

  const VisitRecord({
    required this.id,
    required this.hourX,
    required this.timeLabel,
    required this.durationMinutes,
    required this.durationSeconds,
    this.ammoniaPpm = 0.0,
    this.odorIndex = 0.0,
    this.depositGrams = 0.0,
    this.catWeightGrams = 0.0,
    this.outputType = OutputType.none,
    this.fanPurgeSeconds = 0.0,
    this.status = 'normal',
  });
}

class WeeklyDayRecord {
  final int dayIndex; // 0 = Mon .. 6 = Sun
  final String dayLabel; // "Mon" .. "Sun"
  final double urineGrams; // totalUrineOutputGrams
  final double fecesGrams; // totalFecesOutputGrams
  final int totalVisits; // totalVisits
  final int strainingVisits; // Derived from events (when available)
  final double totalDwellMinutes; // totalStrainingMinutes
  final int fanPurgeSeconds; // Avg fanPurgeDurationSeconds of that day's events

  const WeeklyDayRecord({
    required this.dayIndex,
    required this.dayLabel,
    required this.urineGrams,
    required this.fecesGrams,
    required this.totalVisits,
    this.strainingVisits = 0,
    this.totalDwellMinutes = 0.0,
    this.fanPurgeSeconds = 0,
  });

  double get totalGrams => urineGrams + fecesGrams;
  double get fanPurgeMinutes => fanPurgeSeconds / 60.0;
}

class MonthlyDayRecord {
  final int dayOfMonth; // 1 .. 31
  final double weightKg; // averageCatWeightKg
  final double movingAvg7dKg; // 7-day moving average (kg), derived
  final List<int> hourlyVisits; // hourlyVisitDistribution
  final double medianAmmoniaPpm; // medianPeakAmmoniaPpm
  final double medianOdorIndex; // medianPeakOdorPct

  const MonthlyDayRecord({
    required this.dayOfMonth,
    required this.weightKg,
    required this.movingAvg7dKg,
    this.hourlyVisits = const [],
    this.medianAmmoniaPpm = 0.0,
    this.medianOdorIndex = 0.0,
  });
}

// ---------------------------------------------------------------------------

class SensorService {
  static const String databaseUrl =
      'https://purrclean-124-default-rtdb.asia-southeast1.firebasedatabase.app';

  /// Max raw events pulled to the client (~2 months at 8–10 visits/day).
  static const int _eventWindow = 600;

  /// Max daily summaries pulled to the client (covers current month + week).
  static const int _summaryWindow = 62;

  static const List<String> _weekdayLabels = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  late final DatabaseReference _dbRef;

  SensorService() {
    final FirebaseApp app = Firebase.app();
    final FirebaseDatabase db = FirebaseDatabase.instanceFor(
      app: app,
      databaseURL: databaseUrl,
    );
    _dbRef = db.ref();
  }

  // ---------------------------------------------------------------- Streams

  /// devices/{deviceId}/fan
  Stream<DatabaseEvent> getFanStream(String deviceId) {
    return _dbRef.child('devices/$deviceId/fan').onValue;
  }

  /// devices/{deviceId}/events (most recent [_eventWindow] entries)
  Stream<DatabaseEvent> getEventStream(String deviceId) {
    return _dbRef
        .child('devices/$deviceId/events')
        .orderByKey()
        .limitToLast(_eventWindow)
        .onValue;
  }

  /// devices/{deviceId}/daily_summary (most recent [_summaryWindow] days)
  Stream<DatabaseEvent> getDailySummaryStream(String deviceId) {
    return _dbRef
        .child('devices/$deviceId/daily_summary')
        .orderByKey()
        .limitToLast(_summaryWindow)
        .onValue;
  }

  // ----------------------------------------------------------------- Writes

  /// Updates fan control state under devices/{deviceId}/fan
  Future<void> updateFanControl(
    String deviceId, {
    bool? isAutoMode,
    bool? isRunning,
  }) async {
    final updates = <String, Object?>{
      'auto_mode': ?isAutoMode,
      'is_running': ?isRunning,
      'updated_at': ServerValue.timestamp,
    };
    try {
      await _dbRef
          .child('devices/$deviceId/fan')
          .update(updates)
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('updateFanControl failed: $e');
    }
  }

  /// Writes a daily summary to devices/{deviceId}/daily_summary/{YYYY-MM-DD}.
  Future<void> writeDailySummary(String deviceId, DailySummary summary) async {
    try {
      await _dbRef
          .child('devices/$deviceId/daily_summary/${summary.date}')
          .set(summary.toJson())
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('writeDailySummary(${summary.date}) failed: $e');
    }
  }

  /// Computes and stores summaries for completed past days that have events
  /// but no `daily_summary` node yet (e.g. if the midnight job was missed).
  Future<void> backfillMissingSummaries(
    String deviceId,
    List<LitterEvent> events,
    Map<String, DailySummary> existing,
  ) async {
    final today = dateKey(DateTime.now());
    final grouped = groupEventsByDate(events);
    for (final entry in grouped.entries) {
      if (entry.key == today || existing.containsKey(entry.key)) continue;
      await writeDailySummary(
        deviceId,
        DailySummary.fromEvents(entry.key, entry.value),
      );
    }
  }

  // ---------------------------------------------------------------- Parsing

  /// Parses `devices/{deviceId}/events` into chronologically sorted events.
  List<LitterEvent> parseEvents(DataSnapshot? snapshot) {
    final raw = snapshot?.value;
    final List<LitterEvent> events = [];
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is Map) {
          final e = LitterEvent.fromMap(key.toString(), value);
          if (e != null) events.add(e);
        }
      });
    } else if (raw is List) {
      for (int i = 0; i < raw.length; i++) {
        final value = raw[i];
        if (value is Map) {
          final e = LitterEvent.fromMap('$i', value);
          if (e != null) events.add(e);
        }
      }
    }
    events.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return events;
  }

  /// Parses `devices/{deviceId}/daily_summary` keyed by YYYY-MM-DD.
  Map<String, DailySummary> parseDailySummaries(DataSnapshot? snapshot) {
    final raw = snapshot?.value;
    final Map<String, DailySummary> out = {};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is Map) {
          final s = DailySummary.fromMap(key.toString(), value);
          if (s != null) out[s.date] = s;
        }
      });
    }
    return out;
  }

  /// Today's visits for Page 1 (Daily Analytics) and the home dashboard.
  List<VisitRecord> todayVisits(List<LitterEvent> events) {
    final today = dateKey(DateTime.now());
    return events
        .where((e) => dateKey(e.timestamp.toLocal()) == today)
        .map((e) => e.toVisitRecord())
        .toList()
      ..sort((a, b) => a.hourX.compareTo(b.hourX));
  }

  /// Page 2 (Weekly): current Mon–Sun week. Stored summaries take precedence;
  /// days without one (e.g. today) are aggregated from raw events.
  /// Returns an empty list when the week has no data at all.
  List<WeeklyDayRecord> buildWeeklyRecords(
    Map<String, DailySummary> summaries,
    List<LitterEvent> events,
  ) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final grouped = groupEventsByDate(events);

    bool hasAny = false;
    final List<WeeklyDayRecord> week = [];
    for (int i = 0; i < 7; i++) {
      final key = dateKey(monday.add(Duration(days: i)));
      final dayEvents = grouped[key] ?? const <LitterEvent>[];
      final summary = summaries[key] ??
          (dayEvents.isNotEmpty ? DailySummary.fromEvents(key, dayEvents) : null);
      if (summary != null) hasAny = true;

      final purgeEvents =
          dayEvents.where((e) => e.fanPurgeDurationSeconds > 0).toList();
      final avgPurge = purgeEvents.isEmpty
          ? 0
          : (purgeEvents.fold<double>(
                      0, (s, e) => s + e.fanPurgeDurationSeconds) /
                  purgeEvents.length)
              .round();

      week.add(
        WeeklyDayRecord(
          dayIndex: i,
          dayLabel: _weekdayLabels[i],
          urineGrams: summary?.totalUrineOutputGrams ?? 0.0,
          fecesGrams: summary?.totalFecesOutputGrams ?? 0.0,
          totalVisits: summary?.totalVisits ?? 0,
          strainingVisits: dayEvents.where((e) => e.isStraining).length,
          totalDwellMinutes: summary?.totalStrainingMinutes ?? 0.0,
          fanPurgeSeconds: avgPurge,
        ),
      );
    }
    return hasAny ? week : [];
  }

  /// Page 3 (Monthly): days of the current calendar month that have data.
  /// The 7-day moving average only uses days with a valid weight reading.
  List<MonthlyDayRecord> buildMonthlyRecords(
    Map<String, DailySummary> summaries,
    List<LitterEvent> events,
  ) {
    final now = DateTime.now();
    final monthPrefix =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';

    final Map<String, DailySummary> merged = {
      for (final e in summaries.entries)
        if (e.key.startsWith(monthPrefix)) e.key: e.value,
    };
    groupEventsByDate(events).forEach((key, dayEvents) {
      if (key.startsWith(monthPrefix) && !merged.containsKey(key)) {
        merged[key] = DailySummary.fromEvents(key, dayEvents);
      }
    });

    final sortedKeys = merged.keys.toList()..sort();
    final List<MonthlyDayRecord> out = [];
    final List<double> weightWindow = [];
    for (final key in sortedKeys) {
      final s = merged[key]!;
      if (s.averageCatWeightKg > 0) {
        weightWindow.add(s.averageCatWeightKg);
        if (weightWindow.length > 7) weightWindow.removeAt(0);
      }
      final avg7d = weightWindow.isEmpty
          ? 0.0
          : _round(
              weightWindow.reduce((a, b) => a + b) / weightWindow.length, 2);
      out.add(
        MonthlyDayRecord(
          dayOfMonth: s.day.day,
          weightKg: s.averageCatWeightKg,
          movingAvg7dKg: avg7d,
          hourlyVisits: s.hourlyVisitDistribution,
          medianAmmoniaPpm: s.medianPeakAmmoniaPpm,
          medianOdorIndex: s.medianPeakOdorPct,
        ),
      );
    }
    return out;
  }

  /// Converts events to fl_chart FlSpot(hour, dwell minutes) for today.
  List<FlSpot> eventsToSpots(List<LitterEvent> events) {
    return todayVisits(events)
        .map((r) => FlSpot(r.hourX, r.durationMinutes))
        .toList();
  }

  // ---------------------------------------------------------------- Helpers

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Map<String, List<LitterEvent>> groupEventsByDate(
    List<LitterEvent> events,
  ) {
    final Map<String, List<LitterEvent>> grouped = {};
    for (final e in events) {
      grouped.putIfAbsent(dateKey(e.timestamp.toLocal()), () => []).add(e);
    }
    return grouped;
  }
}

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

double _round(double v, int places) =>
    double.parse(v.toStringAsFixed(places));

double _median(List<double> values) {
  if (values.isEmpty) return 0.0;
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Accepts epoch milliseconds, epoch seconds, numeric strings or ISO-8601.
DateTime? _parseTimestamp(dynamic raw) {
  if (raw is num) {
    final v = raw.toInt();
    if (v <= 0) return null;
    // Values below 1e11 are treated as epoch seconds.
    return DateTime.fromMillisecondsSinceEpoch(v < 100000000000 ? v * 1000 : v);
  }
  if (raw is String) {
    final asInt = int.tryParse(raw.trim());
    if (asInt != null) return _parseTimestamp(asInt);
    return DateTime.tryParse(raw.trim())?.toLocal();
  }
  return null;
}
