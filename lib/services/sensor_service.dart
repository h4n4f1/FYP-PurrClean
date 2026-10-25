import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';

class VisitRecord {
  final String id;
  final double hourX; // 0.0 (00:00) to 23.99 (23:59)
  final String timeLabel; // "HH:mm"
  final double durationMinutes;
  final int durationSeconds;
  final double ammoniaPpm; // NH3 ppm
  final double odorIndex; // 0 - 100 %
  final double depositGrams; // Load cell delta (ΔWeight in grams)
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
    this.status = 'normal',
  });
}

class WeeklyDayRecord {
  final int dayIndex; // 0 = Mon .. 6 = Sun
  final String dayLabel; // "Mon" .. "Sun"
  final double urineGrams; // Estimated urine output (g)
  final double fecesGrams; // Estimated feces output (g)
  final int totalVisits; // Total eliminations that day
  final int strainingVisits; // Visits with straining / extended dwell (>3m)
  final double totalDwellMinutes; // Total minutes spent straining/dwelling
  final int fanPurgeSeconds; // Avg fan purge duration per event (seconds)

  const WeeklyDayRecord({
    required this.dayIndex,
    required this.dayLabel,
    required this.urineGrams,
    required this.fecesGrams,
    required this.totalVisits,
    this.strainingVisits = 0,
    this.totalDwellMinutes = 10.0,
    this.fanPurgeSeconds = 45,
  });

  double get totalGrams => urineGrams + fecesGrams;
  double get fanPurgeMinutes => fanPurgeSeconds / 60.0;
}

class MonthlyDayRecord {
  final int dayOfMonth; // 1 .. 30
  final double weightKg; // Daily stable entry load-cell reading (kg)
  final double movingAvg7dKg; // 7-day moving average (kg)
  final List<int> hourlyVisits; // 24-hour visit count/intensity (hours 0..23)
  final double medianAmmoniaPpm; // Daily median peak NH3 (ppm)
  final double medianOdorIndex; // Daily median Odor Index (%)

  const MonthlyDayRecord({
    required this.dayOfMonth,
    required this.weightKg,
    required this.movingAvg7dKg,
    this.hourlyVisits = const [],
    this.medianAmmoniaPpm = 16.0,
    this.medianOdorIndex = 38.0,
  });
}

class SensorService {
  static const String databaseUrl =
      'https://purrclean-124-default-rtdb.asia-southeast1.firebasedatabase.app';

  late final DatabaseReference _dbRef;

  SensorService() {
    final FirebaseApp app = Firebase.app();
    final FirebaseDatabase db = FirebaseDatabase.instanceFor(
      app: app,
      databaseURL: databaseUrl,
    );
    _dbRef = db.ref();
  }

  // Listens to live sensor data under: devices/<deviceId>/visits
  Stream<DatabaseEvent> getVisitStream(String deviceId) {
    return _dbRef.child('devices/$deviceId/visits').onValue;
  }

  // Listens to weekly 7-day summary data under: devices/<deviceId>/weekly
  Stream<DatabaseEvent> getWeeklyStream(String deviceId) {
    return _dbRef.child('devices/$deviceId/weekly').onValue;
  }

  // Listens to monthly 30-day veterinary health data under: devices/<deviceId>/monthly
  Stream<DatabaseEvent> getMonthlyStream(String deviceId) {
    return _dbRef.child('devices/$deviceId/monthly').onValue;
  }

  /// Parses Firebase snapshot into chronological [VisitRecord] items (00:00 to 23:59).
  List<VisitRecord> parseVisitRecords(DataSnapshot snapshot) {
    final List<VisitRecord> records = [];
    final rawValue = snapshot.value;
    if (rawValue is! Map) return records;

    final Map<dynamic, dynamic> rawMap = Map<dynamic, dynamic>.from(rawValue);

    rawMap.forEach((key, value) {
      if (value is! Map) return;

      double? hourX;
      String? timeLabel;

      // Prefer explicit "HH:mm" time string if available, otherwise timestamp
      final rawTime = value['time'];
      if (rawTime is String && rawTime.contains(':')) {
        final parts = rawTime.split(':');
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        hourX = (h.clamp(0, 23)) + (m.clamp(0, 59) / 60.0);
        timeLabel =
            '${h.clamp(0, 23).toString().padLeft(2, '0')}:${m.clamp(0, 59).toString().padLeft(2, '0')}';
      } else if (value['timestamp'] is num) {
        final time = DateTime.fromMillisecondsSinceEpoch(
          (value['timestamp'] as num).toInt(),
        );
        hourX = time.hour + (time.minute / 60.0);
        timeLabel =
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      }

      if (hourX == null || timeLabel == null) return;

      int durationSec = 0;
      double durationMin = 0.0;

      if (value['duration_seconds'] is num) {
        durationSec = (value['duration_seconds'] as num).round();
        durationMin = durationSec / 60.0;
      } else if (value['duration_minutes'] is num) {
        durationMin = (value['duration_minutes'] as num).toDouble();
        durationSec = (durationMin * 60).round();
      } else if (value['duration'] is num) {
        durationMin = (value['duration'] as num).toDouble();
        durationSec = (durationMin * 60).round();
      }

      double ammoniaPpm = 0.0;
      if (value['ammonia_ppm'] is num) {
        ammoniaPpm = (value['ammonia_ppm'] as num).toDouble();
      } else if (value['ammonia'] is num) {
        ammoniaPpm = (value['ammonia'] as num).toDouble();
      }

      double odorIndex = 0.0;
      if (value['odor_index'] is num) {
        odorIndex = (value['odor_index'] as num).toDouble();
      } else if (value['odor'] is num) {
        odorIndex = (value['odor'] as num).toDouble();
      }

      double depositGrams = 0.0;
      if (value['deposit_g'] is num) {
        depositGrams = (value['deposit_g'] as num).toDouble();
      } else if (value['delta_weight_g'] is num) {
        depositGrams = (value['delta_weight_g'] as num).toDouble();
      } else {
        // Fallback estimation if older DB record lacks explicit deposit_g
        depositGrams = (durationSec * 0.32).clamp(18.0, 85.0);
      }

      final status = (value['status'] as String?) ?? 'normal';

      records.add(
        VisitRecord(
          id: key.toString(),
          hourX: hourX,
          timeLabel: timeLabel,
          durationMinutes: double.parse(durationMin.toStringAsFixed(2)),
          durationSeconds: durationSec,
          ammoniaPpm: ammoniaPpm,
          odorIndex: odorIndex,
          depositGrams: depositGrams,
          status: status,
        ),
      );
    });

    records.sort((a, b) => a.hourX.compareTo(b.hourX));
    return records;
  }

  // Converts Firebase JSON payload to fl_chart FlSpot(x, y) coordinates (in minutes)
  List<FlSpot> parseSensorDataToSpots(DataSnapshot snapshot) {
    final records = parseVisitRecords(snapshot);
    return records
        .map((r) => FlSpot(r.hourX, r.durationMinutes))
        .toList();
  }

  /// Mock dataset representing a full 24-hour day (00:00 to 23:59) of cat visits
  /// and dwell times inside the litter box.
  static Map<String, Map<String, Object>> buildMockVisitsPayload() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    int tsFor(int hour, int minute) =>
        startOfDay.add(Duration(hours: hour, minutes: minute)).millisecondsSinceEpoch;

    return {
      'visit_01': {
        'timestamp': tsFor(1, 30),
        'time': '01:30',
        'duration': 0.92,
        'duration_minutes': 0.92,
        'duration_seconds': 55,
        'weight_g': 4180,
        'deposit_g': 28.0,
        'delta_weight_g': 28.0,
        'ammonia_ppm': 12.0,
        'odor_index': 28,
        'status': 'normal',
      },
      'visit_02': {
        'timestamp': tsFor(6, 15),
        'time': '06:15',
        'duration': 1.25,
        'duration_minutes': 1.25,
        'duration_seconds': 75,
        'weight_g': 4210,
        'deposit_g': 36.0,
        'delta_weight_g': 36.0,
        'ammonia_ppm': 18.0,
        'odor_index': 42,
        'status': 'normal',
      },
      'visit_03': {
        'timestamp': tsFor(8, 40),
        'time': '08:40',
        'duration': 3.58,
        'duration_minutes': 3.58,
        'duration_seconds': 215,
        'weight_g': 4200,
        'deposit_g': 68.0,
        'delta_weight_g': 68.0,
        'ammonia_ppm': 38.0,
        'odor_index': 84,
        'status': 'straining',
      },
      'visit_04': {
        'timestamp': tsFor(11, 20),
        'time': '11:20',
        'duration': 1.00,
        'duration_minutes': 1.00,
        'duration_seconds': 60,
        'weight_g': 4190,
        'deposit_g': 32.0,
        'delta_weight_g': 32.0,
        'ammonia_ppm': 15.0,
        'odor_index': 35,
        'status': 'normal',
      },
      'visit_05': {
        'timestamp': tsFor(14, 45),
        'time': '14:45',
        'duration': 2.25,
        'duration_minutes': 2.25,
        'duration_seconds': 135,
        'weight_g': 4195,
        'deposit_g': 48.0,
        'delta_weight_g': 48.0,
        'ammonia_ppm': 27.0,
        'odor_index': 62,
        'status': 'extended',
      },
      'visit_06': {
        'timestamp': tsFor(17, 10),
        'time': '17:10',
        'duration': 0.75,
        'duration_minutes': 0.75,
        'duration_seconds': 45,
        'weight_g': 4185,
        'deposit_g': 24.0,
        'delta_weight_g': 24.0,
        'ammonia_ppm': 11.0,
        'odor_index': 24,
        'status': 'normal',
      },
      'visit_07': {
        'timestamp': tsFor(20, 5),
        'time': '20:05',
        'duration': 4.08,
        'duration_minutes': 4.08,
        'duration_seconds': 245,
        'weight_g': 4220,
        'deposit_g': 76.0,
        'delta_weight_g': 76.0,
        'ammonia_ppm': 44.0,
        'odor_index': 92,
        'status': 'straining',
      },
      'visit_08': {
        'timestamp': tsFor(22, 30),
        'time': '22:30',
        'duration': 1.33,
        'duration_minutes': 1.33,
        'duration_seconds': 80,
        'weight_g': 4190,
        'deposit_g': 38.0,
        'delta_weight_g': 38.0,
        'ammonia_ppm': 19.0,
        'odor_index': 45,
        'status': 'normal',
      },
    };
  }

  /// Seeds the mock daily, weekly, and monthly datasets into Firebase Realtime Database.
  Future<bool> seedMockVisits(String deviceId) async {
    final payload = buildMockVisitsPayload();
    final weeklyPayload = buildMockWeeklyPayload();
    final monthlyPayload = buildMockMonthlyPayload();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.parse('$databaseUrl/devices/$deviceId/visits.json');
      final req = await client.putUrl(uri);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(payload));
      final res = await req.close().timeout(const Duration(seconds: 8));
      await res.drain<void>();

      final weeklyUri = Uri.parse('$databaseUrl/devices/$deviceId/weekly.json');
      final weeklyReq = await client.putUrl(weeklyUri);
      weeklyReq.headers.contentType = ContentType.json;
      weeklyReq.write(jsonEncode(weeklyPayload));
      final weeklyRes =
          await weeklyReq.close().timeout(const Duration(seconds: 8));
      await weeklyRes.drain<void>();

      final monthlyUri =
          Uri.parse('$databaseUrl/devices/$deviceId/monthly.json');
      final monthlyReq = await client.putUrl(monthlyUri);
      monthlyReq.headers.contentType = ContentType.json;
      monthlyReq.write(jsonEncode(monthlyPayload));
      final monthlyRes =
          await monthlyReq.close().timeout(const Duration(seconds: 8));
      await monthlyRes.drain<void>();

      if (res.statusCode == 200 &&
          weeklyRes.statusCode == 200 &&
          monthlyRes.statusCode == 200) {
        return true;
      }
    } catch (e) {
      debugPrint('REST seedMockVisits failed, trying SDK: $e');
    } finally {
      client.close(force: true);
    }

    try {
      await _dbRef
          .child('devices/$deviceId/visits')
          .set(payload)
          .timeout(const Duration(seconds: 8));
      await _dbRef
          .child('devices/$deviceId/weekly')
          .set(weeklyPayload)
          .timeout(const Duration(seconds: 8));
      await _dbRef
          .child('devices/$deviceId/monthly')
          .set(monthlyPayload)
          .timeout(const Duration(seconds: 8));
      return true;
    } catch (e) {
      debugPrint('SDK seedMockVisits failed: $e');
      return false;
    }
  }

  static Map<String, Map<String, Object>> buildMockWeeklyPayload() {
    return {
      'day_01_mon': {
        'day_index': 0,
        'day': 'Mon',
        'urine_g': 135.0,
        'feces_g': 55.0,
        'total_visits': 6,
        'straining_visits': 0,
        'total_dwell_min': 9.5,
        'fan_purge_sec': 45,
      },
      'day_02_tue': {
        'day_index': 1,
        'day': 'Tue',
        'urine_g': 148.0,
        'feces_g': 62.0,
        'total_visits': 6,
        'straining_visits': 1,
        'total_dwell_min': 11.2,
        'fan_purge_sec': 65,
      },
      'day_03_wed': {
        'day_index': 2,
        'day': 'Wed',
        'urine_g': 182.0,
        'feces_g': 86.0,
        'total_visits': 8,
        'straining_visits': 2,
        'total_dwell_min': 18.5,
        'fan_purge_sec': 95,
      },
      'day_04_thu': {
        'day_index': 3,
        'day': 'Thu',
        'urine_g': 128.0,
        'feces_g': 52.0,
        'total_visits': 5,
        'straining_visits': 0,
        'total_dwell_min': 8.0,
        'fan_purge_sec': 125,
      },
      'day_05_fri': {
        'day_index': 4,
        'day': 'Fri',
        'urine_g': 142.0,
        'feces_g': 64.0,
        'total_visits': 6,
        'straining_visits': 1,
        'total_dwell_min': 12.0,
        'fan_purge_sec': 160,
      },
      'day_06_sat': {
        'day_index': 5,
        'day': 'Sat',
        'urine_g': 175.0,
        'feces_g': 80.0,
        'total_visits': 8,
        'straining_visits': 2,
        'total_dwell_min': 17.4,
        'fan_purge_sec': 200,
      },
      'day_07_sun': {
        'day_index': 6,
        'day': 'Sun',
        'urine_g': 138.0,
        'feces_g': 58.0,
        'total_visits': 6,
        'straining_visits': 0,
        'total_dwell_min': 9.8,
        'fan_purge_sec': 230,
      },
    };
  }

  static List<WeeklyDayRecord> defaultWeeklyRecords() {
    return const [
      WeeklyDayRecord(
        dayIndex: 0,
        dayLabel: 'Mon',
        urineGrams: 135.0,
        fecesGrams: 55.0,
        totalVisits: 6,
        strainingVisits: 0,
        totalDwellMinutes: 9.5,
        fanPurgeSeconds: 45,
      ),
      WeeklyDayRecord(
        dayIndex: 1,
        dayLabel: 'Tue',
        urineGrams: 148.0,
        fecesGrams: 62.0,
        totalVisits: 6,
        strainingVisits: 1,
        totalDwellMinutes: 11.2,
        fanPurgeSeconds: 65,
      ),
      WeeklyDayRecord(
        dayIndex: 2,
        dayLabel: 'Wed',
        urineGrams: 182.0,
        fecesGrams: 86.0,
        totalVisits: 8,
        strainingVisits: 2,
        totalDwellMinutes: 18.5,
        fanPurgeSeconds: 95,
      ),
      WeeklyDayRecord(
        dayIndex: 3,
        dayLabel: 'Thu',
        urineGrams: 128.0,
        fecesGrams: 52.0,
        totalVisits: 5,
        strainingVisits: 0,
        totalDwellMinutes: 8.0,
        fanPurgeSeconds: 125,
      ),
      WeeklyDayRecord(
        dayIndex: 4,
        dayLabel: 'Fri',
        urineGrams: 142.0,
        fecesGrams: 64.0,
        totalVisits: 6,
        strainingVisits: 1,
        totalDwellMinutes: 12.0,
        fanPurgeSeconds: 160,
      ),
      WeeklyDayRecord(
        dayIndex: 5,
        dayLabel: 'Sat',
        urineGrams: 175.0,
        fecesGrams: 80.0,
        totalVisits: 8,
        strainingVisits: 2,
        totalDwellMinutes: 17.4,
        fanPurgeSeconds: 200,
      ),
      WeeklyDayRecord(
        dayIndex: 6,
        dayLabel: 'Sun',
        urineGrams: 138.0,
        fecesGrams: 58.0,
        totalVisits: 6,
        strainingVisits: 0,
        totalDwellMinutes: 9.8,
        fanPurgeSeconds: 230,
      ),
    ];
  }

  List<WeeklyDayRecord> parseWeeklyRecords(DataSnapshot? snapshot) {
    final rawValue = snapshot?.value;
    if (rawValue is! Map) return defaultWeeklyRecords();

    const fallbackPurgeSec = [45, 65, 95, 125, 160, 200, 230];
    final List<WeeklyDayRecord> records = [];
    final Map<dynamic, dynamic> rawMap = Map<dynamic, dynamic>.from(rawValue);

    rawMap.forEach((key, value) {
      if (value is! Map) return;
      final idx = ((value['day_index'] as num?)?.toInt() ?? 0).clamp(0, 6);
      final dayLabel = (value['day'] as String?) ?? 'Day';
      final urineG = (value['urine_g'] as num?)?.toDouble() ?? 130.0;
      final fecesG = (value['feces_g'] as num?)?.toDouble() ?? 55.0;
      final visits = (value['total_visits'] as num?)?.toInt() ?? 6;
      final strainingVisits = (value['straining_visits'] as num?)?.toInt() ??
          (visits >= 8 ? 2 : 0);
      final totalDwellMin = (value['total_dwell_min'] as num?)?.toDouble() ??
          (visits * 2.1);
      final fanPurgeSec =
          (value['fan_purge_sec'] as num?)?.toInt() ?? fallbackPurgeSec[idx];
      records.add(
        WeeklyDayRecord(
          dayIndex: idx,
          dayLabel: dayLabel,
          urineGrams: urineG,
          fecesGrams: fecesG,
          totalVisits: visits,
          strainingVisits: strainingVisits,
          totalDwellMinutes: totalDwellMin,
          fanPurgeSeconds: fanPurgeSec,
        ),
      );
    });

    if (records.isEmpty) return defaultWeeklyRecords();
    records.sort((a, b) => a.dayIndex.compareTo(b.dayIndex));
    return records;
  }

  static const List<double> _kMockMonthlyWeightsKg = [
    4.22, 4.24, 4.19, 4.23, 4.21, 4.25, 4.20, // Days 1-7
    4.22, 4.18, 4.21, 4.23, 4.19, 4.20, 4.17, // Days 8-14
    4.19, 4.16, 4.18, 4.15, 4.13, 4.11, 4.08, // Days 15-21
    4.06, 4.03, 3.99, 3.96, 3.92, 3.88, 3.86, // Days 22-28
    3.84, 3.82, // Days 29-30
  ];

  /// Generates deterministic 24-hour circadian visit counts (0..3) for a given day (1..30).
  /// Days 1-21 follow a healthy crepuscular pattern (dawn 06-08, midday 13-14, dusk 19-21).
  /// Days 22-30 introduce nocturnal elimination (01:00-04:00 nocturia alert).
  static List<int> buildCircadianRowForDay(int day) {
    final List<int> hours = List<int>.filled(24, 0);
    // Morning peak (06:00 - 08:00)
    hours[6 + (day % 3)] = (day % 4 == 0) ? 2 : 1;
    if (day % 2 == 0) hours[8] = 1;

    // Afternoon visit (12:00 - 15:00)
    hours[12 + (day % 4)] = 1;

    // Evening peak (18:00 - 22:00)
    hours[18 + (day % 3)] = (day % 3 == 0) ? 2 : 1;
    hours[21 + (day % 2)] = 1;

    // Late-month nocturia / circadian shift (Days 22-30, 01:00 - 04:00)
    if (day >= 22) {
      hours[1 + (day % 3)] = (day >= 26) ? 3 : 2;
      if (day >= 25) hours[4] = 2;
    } else if (day % 7 == 0) {
      hours[2] = 1;
    }
    return hours;
  }

  static List<MonthlyDayRecord> defaultMonthlyRecords() {
    final List<MonthlyDayRecord> list = [];
    for (int i = 0; i < _kMockMonthlyWeightsKg.length; i++) {
      final startIdx = (i - 6) < 0 ? 0 : (i - 6);
      double sum = 0;
      int count = 0;
      for (int j = startIdx; j <= i; j++) {
        sum += _kMockMonthlyWeightsKg[j];
        count++;
      }
      final avg7d = double.parse((sum / count).toStringAsFixed(2));
      final dayNum = i + 1;
      // Gradual rise in median NH3 and Odor towards late month (days 24-30 cross danger thresholds)
      final double nh3Ppm = dayNum < 20
          ? 14.0 + ((dayNum * 3) % 7)
          : 22.0 + ((dayNum - 20) * 1.4);
      final double odorPct = dayNum < 20
          ? 34.0 + ((dayNum * 5) % 14)
          : 58.0 + ((dayNum - 20) * 3.0);
      list.add(
        MonthlyDayRecord(
          dayOfMonth: dayNum,
          weightKg: _kMockMonthlyWeightsKg[i],
          movingAvg7dKg: avg7d,
          hourlyVisits: buildCircadianRowForDay(dayNum),
          medianAmmoniaPpm: double.parse(nh3Ppm.toStringAsFixed(1)),
          medianOdorIndex: double.parse(odorPct.toStringAsFixed(0)),
        ),
      );
    }
    return list;
  }

  static Map<String, Map<String, Object>> buildMockMonthlyPayload() {
    final records = defaultMonthlyRecords();
    final Map<String, Map<String, Object>> map = {};
    for (final r in records) {
      final key = 'day_${r.dayOfMonth.toString().padLeft(2, '0')}';
      map[key] = {
        'day_of_month': r.dayOfMonth,
        'weight_kg': r.weightKg,
        'moving_avg_7d_kg': r.movingAvg7dKg,
        'hourly_visits': r.hourlyVisits,
        'median_ammonia_ppm': r.medianAmmoniaPpm,
        'median_odor_index': r.medianOdorIndex,
      };
    }
    return map;
  }

  List<MonthlyDayRecord> parseMonthlyRecords(DataSnapshot? snapshot) {
    final rawValue = snapshot?.value;
    if (rawValue is! Map) return defaultMonthlyRecords();

    final defaults = defaultMonthlyRecords();
    final List<MonthlyDayRecord> temp = [];
    final Map<dynamic, dynamic> rawMap = Map<dynamic, dynamic>.from(rawValue);

    rawMap.forEach((key, value) {
      if (value is! Map) return;
      final day = ((value['day_of_month'] as num?)?.toInt() ?? 1).clamp(1, 30);
      final fallback = defaults[day - 1];
      final weightKg =
          (value['weight_kg'] as num?)?.toDouble() ?? fallback.weightKg;
      final avgKg =
          (value['moving_avg_7d_kg'] as num?)?.toDouble() ?? weightKg;

      List<int> hourly = buildCircadianRowForDay(day);
      final rawHourly = value['hourly_visits'];
      if (rawHourly is List && rawHourly.length == 24) {
        hourly = rawHourly.map((e) => (e as num?)?.toInt() ?? 0).toList();
      }

      final nh3Ppm = (value['median_ammonia_ppm'] as num?)?.toDouble() ??
          fallback.medianAmmoniaPpm;
      final odorPct = (value['median_odor_index'] as num?)?.toDouble() ??
          fallback.medianOdorIndex;

      temp.add(
        MonthlyDayRecord(
          dayOfMonth: day,
          weightKg: weightKg,
          movingAvg7dKg: avgKg,
          hourlyVisits: hourly,
          medianAmmoniaPpm: nh3Ppm,
          medianOdorIndex: odorPct,
        ),
      );
    });

    if (temp.isEmpty) return defaultMonthlyRecords();
    temp.sort((a, b) => a.dayOfMonth.compareTo(b.dayOfMonth));
    return temp;
  }
}
