import 'package:flutter/material.dart';

import 'sensor_service.dart';

/// A single behavioural insight shown in the "Behavioral Insights" card.
class BehavioralInsight {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String severity; // 'high' | 'medium' | 'low'
  final String description;

  const BehavioralInsight({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.severity,
    required this.description,
  });
}

/// A small metric shown in the summary cards under the insights.
class SummaryMetric {
  final IconData icon;
  final String label;
  final String value;

  const SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
  });
}

/// Generates Daily / Weekly / Monthly behavioural insights and summary
/// metrics from the records that are read from Firebase Realtime Database.
///
/// Thresholds intentionally match the ones used by the charts in
/// analytics_screen.dart so the insights always agree with the graphs.
class BehaviorInsightsService {
  BehaviorInsightsService._();

  // ---------- Shared thresholds (same as the charts) ----------
  static const int strainingSeconds = 180; // visit >= 3 min
  static const double dangerAmmoniaPpm = 30.0;
  static const double dangerOdorPercent = 80.0;
  static const double heavyDepositGrams = 60.0;
  static const double highDailyOutputGrams = 240.0;
  static const double strainingDwellAlertMinutes = 15.0;
  static const int litterSwapPurgeSeconds = 180;
  static const double vetAlertWeightKg = 3.9;
  static const int minNormalVisits = 3;
  static const int maxNormalVisits = 8;

  static const Color _red = Color(0xFFE53935);
  static const Color _orange = Colors.orange;
  static const Color _green = Colors.green;
  static const Color _blue = Color(0xFF3D6BE0);

  // ---------- Helpers ----------
  static BehavioralInsight _high(IconData icon, String title, String desc) =>
      BehavioralInsight(
        icon: icon,
        iconColor: _red,
        title: title,
        severity: 'high',
        description: desc,
      );

  static BehavioralInsight _medium(IconData icon, String title, String desc) =>
      BehavioralInsight(
        icon: icon,
        iconColor: _orange,
        title: title,
        severity: 'medium',
        description: desc,
      );

  static BehavioralInsight _ok(String title, String desc) => BehavioralInsight(
        icon: Icons.check_circle_outline,
        iconColor: _green,
        title: title,
        severity: 'low',
        description: desc,
      );

  static BehavioralInsight _noData(String what) => BehavioralInsight(
        icon: Icons.info_outline,
        iconColor: _blue,
        title: 'No data yet',
        severity: 'low',
        description:
            'No $what found in the database yet. Insights will appear automatically once your cat uses the litter box.',
      );

  static String _dur(int seconds) =>
      '${(seconds / 60).toStringAsFixed(2)} min / ${seconds}s';

  static String _join(List<String> items, {int max = 4}) {
    if (items.length <= max) return items.join(', ');
    return '${items.take(max).join(', ')} +${items.length - max} more';
  }

  static double _avg(Iterable<num> values) {
    if (values.isEmpty) return 0;
    return values.fold<double>(0, (a, b) => a + b) / values.length;
  }

  static int _severityRank(String s) =>
      s == 'high' ? 0 : (s == 'medium' ? 1 : 2);

  static List<BehavioralInsight> _sorted(List<BehavioralInsight> list) {
    final copy = List<BehavioralInsight>.from(list);
    // List.sort is not stable, so decorate with the original index.
    final indexed = copy.asMap().entries.toList()
      ..sort((a, b) {
        final c = _severityRank(a.value.severity)
            .compareTo(_severityRank(b.value.severity));
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).toList();
  }

  // =====================================================================
  // DAILY  (devices/<id>/visits)
  // =====================================================================
  static List<BehavioralInsight> daily(
    List<VisitRecord> visits, {
    DateTime? now,
  }) {
    if (visits.isEmpty) return [_noData('visits recorded today')];
    final clock = now ?? DateTime.now();
    final out = <BehavioralInsight>[];
    final total = visits.length;

    // 1. Visit frequency
    if (total > maxNormalVisits) {
      out.add(_medium(
        Icons.swap_vert_rounded,
        'High Visit Frequency',
        '$total visits recorded in the 24-hour cycle, above the usual range of '
            '$minNormalVisits–$maxNormalVisits. Frequent small visits can be linked to '
            'urinary discomfort, so keep an eye on it.',
      ));
    } else if (total < minNormalVisits && clock.hour >= 20) {
      out.add(_medium(
        Icons.swap_vert_rounded,
        'Low Visit Frequency',
        'Only $total visit${total == 1 ? '' : 's'} recorded today, below the usual '
            '$minNormalVisits–$maxNormalVisits. Check that your cat is drinking and '
            'eliminating normally.',
      ));
    } else {
      out.add(_ok(
        'Normal Visit Frequency',
        '$total visit${total == 1 ? '' : 's'} recorded so far today '
            '(healthy range is $minNormalVisits–$maxNormalVisits per day).',
      ));
    }

    // 2. Prolonged dwell / straining
    final prolonged = visits
        .where((v) =>
            v.durationSeconds >= strainingSeconds || v.status == 'straining')
        .toList();
    if (prolonged.isNotEmpty) {
      final list = _join(
          prolonged.map((v) => '${v.timeLabel} (${_dur(v.durationSeconds)})').toList());
      final longest = prolonged
          .reduce((a, b) => a.durationSeconds >= b.durationSeconds ? a : b);
      final desc = 'Extended dwell detected at $list. Longest visit: '
          '${_dur(longest.durationSeconds)} at ${longest.timeLabel}.';
      out.add(prolonged.length >= 2
          ? _high(Icons.trending_up, 'Repeated Straining / Long Dwell', desc)
          : _medium(Icons.trending_up, 'Extended Dwell Time', desc));
    } else {
      final extended = visits
          .where((v) => v.durationSeconds >= 120 || v.status == 'extended')
          .toList();
      if (extended.isNotEmpty) {
        out.add(_medium(
          Icons.timer_outlined,
          'Slightly Longer Dwell Time',
          'Longer than usual visit${extended.length == 1 ? '' : 's'} at '
              '${_join(extended.map((v) => '${v.timeLabel} (${_dur(v.durationSeconds)})').toList())}.',
        ));
      }
    }

    // 3. Gas levels (ammonia / odor)
    final gas = visits
        .where((v) =>
            v.ammoniaPpm >= dangerAmmoniaPpm ||
            v.odorIndex >= dangerOdorPercent)
        .toList();
    if (gas.isNotEmpty) {
      final peakNh3 = gas.map((v) => v.ammoniaPpm).reduce((a, b) => a > b ? a : b);
      final peakOdor = gas.map((v) => v.odorIndex).reduce((a, b) => a > b ? a : b);
      out.add(_high(
        Icons.air_rounded,
        'High Ammonia / Odor Levels',
        '${gas.length} visit${gas.length == 1 ? '' : 's'} crossed the gas threshold '
            '(${_join(gas.map((v) => v.timeLabel).toList())}). Peak NH₃ '
            '${peakNh3.toStringAsFixed(0)} ppm, peak odor ${peakOdor.toStringAsFixed(0)}%. '
            'Consider scooping or running the fan.',
      ));
    }

    // 4. Heavy deposits
    final heavy = visits.where((v) => v.depositGrams >= heavyDepositGrams).toList();
    if (heavy.isNotEmpty) {
      final peak = heavy.map((v) => v.depositGrams).reduce((a, b) => a > b ? a : b);
      out.add(_medium(
        Icons.scale_rounded,
        'Heavy Deposit Detected',
        '${heavy.length} deposit${heavy.length == 1 ? '' : 's'} at or above '
            '${heavyDepositGrams.toStringAsFixed(0)} g '
            '(${_join(heavy.map((v) => v.timeLabel).toList())}), peak '
            '${peak.toStringAsFixed(0)} g.',
      ));
    }

    // 5. Night-time elimination (01:00 - 04:59)
    final night = visits.where((v) => v.hourX >= 1 && v.hourX < 5).toList();
    if (night.length >= 2) {
      out.add(_medium(
        Icons.nightlight_round,
        'Night-time Elimination',
        '${night.length} visits between 01:00 and 05:00 '
            '(${_join(night.map((v) => v.timeLabel).toList())}). Repeated night visits '
            'can be an early sign of nocturia.',
      ));
    }

    // 6. Everything fine
    if (prolonged.isEmpty && gas.isEmpty && heavy.isEmpty) {
      out.add(_ok(
        'Dwell Time & Air Quality Normal',
        'Average dwell time is ${_dur(_avg(visits.map((v) => v.durationSeconds)).round())} '
            'and all gas readings are within the safe range.',
      ));
    }

    return _sorted(out);
  }

  static List<SummaryMetric> dailySummary(
    List<VisitRecord> visits, {
    required bool inSeconds,
  }) {
    final total = visits.length;
    final avgSec = total == 0
        ? 0
        : (visits.fold<int>(0, (s, v) => s + v.durationSeconds) / total).round();
    final avgMin = avgSec / 60.0;
    return [
      SummaryMetric(
        icon: Icons.pets_rounded,
        label: "Today's Visits",
        value: '$total visit${total == 1 ? '' : 's'}',
      ),
      SummaryMetric(
        icon: Icons.timer_outlined,
        label: 'Avg Dwell Time',
        value: total == 0
            ? '--'
            : (inSeconds ? '$avgSec sec' : '${avgMin.toStringAsFixed(1)} min'),
      ),
    ];
  }

  // =====================================================================
  // WEEKLY  (devices/<id>/weekly)
  // =====================================================================
  static List<BehavioralInsight> weekly(List<WeeklyDayRecord> days) {
    if (days.isEmpty) return [_noData('weekly records')];
    final out = <BehavioralInsight>[];
    final n = days.length;

    // 1. Straining ratio + long dwell
    final totalVisits = days.fold<int>(0, (s, d) => s + d.totalVisits);
    final totalStraining = days.fold<int>(0, (s, d) => s + d.strainingVisits);
    final strainDays = days.where((d) => d.strainingVisits >= 2).toList();
    final longDwellDays =
        days.where((d) => d.totalDwellMinutes >= strainingDwellAlertMinutes).toList();
    if (totalStraining == 0) {
      out.add(_ok(
        'No Straining This Week',
        'None of the $totalVisits visits this week showed straining or extended dwell.',
      ));
    } else {
      final ratio = totalVisits == 0 ? 0 : totalStraining / totalVisits * 100;
      final parts = <String>[
        '$totalStraining of $totalVisits visits (${ratio.toStringAsFixed(0)}%) involved straining.',
        if (strainDays.isNotEmpty)
          'Worst days: ${_join(strainDays.map((d) => '${d.dayLabel} (${d.strainingVisits})').toList())}.',
        if (longDwellDays.isNotEmpty)
          'Dwell exceeded ${strainingDwellAlertMinutes.toStringAsFixed(0)} min on '
              '${_join(longDwellDays.map((d) => '${d.dayLabel} (${d.totalDwellMinutes.toStringAsFixed(1)} min)').toList())}.',
      ];
      final sev = (strainDays.isNotEmpty || totalStraining >= 4)
          ? 'high'
          : 'medium';
      out.add(sev == 'high'
          ? _high(Icons.trending_up, 'Frequent Straining Detected', parts.join(' '))
          : _medium(Icons.trending_up, 'Occasional Straining', parts.join(' ')));
    }

    // 2. Output volume (level + trend)
    final highDays = days.where((d) => d.totalGrams >= highDailyOutputGrams).toList();
    if (highDays.isNotEmpty) {
      out.add(_medium(
        Icons.scale_rounded,
        'High Output Days',
        'Output reached ${highDailyOutputGrams.toStringAsFixed(0)} g or more on '
            '${_join(highDays.map((d) => '${d.dayLabel} (${d.totalGrams.toStringAsFixed(0)} g)').toList())}.',
      ));
    }
    if (n >= 4) {
      final half = n ~/ 2;
      final first = _avg(days.take(half).map((d) => d.totalGrams));
      final second = _avg(days.skip(half).map((d) => d.totalGrams));
      if (first > 0) {
        final change = (second - first) / first * 100;
        if (change >= 25) {
          out.add(_medium(
            Icons.arrow_upward_rounded,
            'Output Rising',
            'Average daily output rose ${change.toStringAsFixed(0)}% in the second half of the week '
                '(${first.toStringAsFixed(0)} g → ${second.toStringAsFixed(0)} g).',
          ));
        } else if (change <= -25) {
          out.add(_medium(
            Icons.arrow_downward_rounded,
            'Output Dropping',
            'Average daily output fell ${change.abs().toStringAsFixed(0)}% in the second half of the week '
                '(${first.toStringAsFixed(0)} g → ${second.toStringAsFixed(0)} g). '
                'Make sure your cat is drinking enough.',
          ));
        }
      }
    }

    // 3. Visit frequency
    final avgVisits = totalVisits / n;
    final busyDays = days.where((d) => d.totalVisits > maxNormalVisits).toList();
    if (avgVisits > maxNormalVisits || avgVisits < minNormalVisits) {
      out.add(_medium(
        Icons.swap_vert_rounded,
        avgVisits > maxNormalVisits ? 'High Weekly Frequency' : 'Low Weekly Frequency',
        'Averaging ${avgVisits.toStringAsFixed(1)} visits per day '
            '(healthy range $minNormalVisits–$maxNormalVisits).',
      ));
    } else {
      out.add(_ok(
        'Normal Weekly Frequency',
        'Averaging ${avgVisits.toStringAsFixed(1)} visits per day across $n days'
            '${busyDays.isNotEmpty ? ', with busier days on ${_join(busyDays.map((d) => d.dayLabel).toList())}' : ''}.',
      ));
    }

    // 4. Litter degradation (fan purge duration)
    final degraded =
        days.where((d) => d.fanPurgeSeconds >= litterSwapPurgeSeconds).toList();
    final latest = days.last;
    if (degraded.isNotEmpty) {
      final msg = 'Fan purge duration reached ${(latest.fanPurgeSeconds / 60).toStringAsFixed(1)} min '
          'on ${latest.dayLabel}; it first crossed ${litterSwapPurgeSeconds ~/ 60} min on '
          '${degraded.first.dayLabel}. The litter is absorbing less odor.';
      out.add(latest.fanPurgeSeconds >= litterSwapPurgeSeconds
          ? _high(Icons.cleaning_services_rounded, 'Time to Change the Litter', msg)
          : _medium(Icons.cleaning_services_rounded, 'Litter Degradation Noticed', msg));
    } else {
      out.add(_ok(
        'Litter Still Fresh',
        'Fan purge time peaked at ${(days.map((d) => d.fanPurgeSeconds).reduce((a, b) => a > b ? a : b) / 60).toStringAsFixed(1)} min, '
            'below the ${litterSwapPurgeSeconds ~/ 60}-minute swap alert.',
      ));
    }

    return _sorted(out);
  }

  static List<SummaryMetric> weeklySummary(List<WeeklyDayRecord> days) {
    final visits = days.fold<int>(0, (s, d) => s + d.totalVisits);
    final dwell = days.fold<double>(0, (s, d) => s + d.totalDwellMinutes);
    return [
      SummaryMetric(
        icon: Icons.pets_rounded,
        label: 'Visits This Week',
        value: days.isEmpty ? '--' : '$visits visits',
      ),
      SummaryMetric(
        icon: Icons.timer_outlined,
        label: 'Avg Dwell / Visit',
        value: visits == 0 ? '--' : '${(dwell / visits).toStringAsFixed(1)} min',
      ),
    ];
  }

  // =====================================================================
  // MONTHLY  (devices/<id>/monthly)
  // =====================================================================
  static int _nightVisits(MonthlyDayRecord d) {
    int sum = 0;
    for (int h = 1; h <= 4; h++) {
      if (h < d.hourlyVisits.length) sum += d.hourlyVisits[h];
    }
    return sum;
  }

  static int _dayVisits(MonthlyDayRecord d) =>
      d.hourlyVisits.fold<int>(0, (s, v) => s + v);

  static List<BehavioralInsight> monthly(List<MonthlyDayRecord> days) {
    if (days.isEmpty) return [_noData('monthly records')];
    final out = <BehavioralInsight>[];
    final n = days.length;

    // 1. Body weight trajectory
    if (n >= 7) {
      final baseline = _avg(days.take(7).map((d) => d.weightKg));
      final latestAvg = days.last.movingAvg7dKg;
      final latestKg = days.last.weightKg;
      final changePct = baseline == 0 ? 0 : (latestAvg - baseline) / baseline * 100;
      final lowDays = days.where((d) => d.weightKg <= vetAlertWeightKg).length;

      if (changePct <= -5 || latestKg <= vetAlertWeightKg) {
        out.add(_high(
          Icons.monitor_weight_outlined,
          'Significant Weight Loss',
          'Weight fell ${changePct.abs().toStringAsFixed(1)}% from the first-week baseline '
              '(${baseline.toStringAsFixed(2)} kg → ${latestAvg.toStringAsFixed(2)} kg 7-day avg)'
              '${lowDays > 0 ? ', with $lowDays day${lowDays == 1 ? '' : 's'} at or below ${vetAlertWeightKg.toStringAsFixed(1)} kg' : ''}. '
              'Please consult a veterinarian.',
        ));
      } else if (changePct <= -3) {
        out.add(_medium(
          Icons.monitor_weight_outlined,
          'Gradual Weight Loss',
          'Weight is down ${changePct.abs().toStringAsFixed(1)}% from the first-week baseline '
              '(${baseline.toStringAsFixed(2)} kg → ${latestAvg.toStringAsFixed(2)} kg). Keep monitoring.',
        ));
      } else if (changePct >= 5) {
        out.add(_medium(
          Icons.monitor_weight_outlined,
          'Weight Gain',
          'Weight is up ${changePct.toStringAsFixed(1)}% from the first-week baseline '
              '(${baseline.toStringAsFixed(2)} kg → ${latestAvg.toStringAsFixed(2)} kg).',
        ));
      } else {
        out.add(_ok(
          'Stable Body Weight',
          'Weight is steady at ${latestAvg.toStringAsFixed(2)} kg '
              '(${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(1)}% vs first-week baseline).',
        ));
      }
    } else {
      out.add(_ok(
        'Building Weight Baseline',
        'At least 7 days of weight readings are needed to detect trends. $n day${n == 1 ? '' : 's'} recorded so far.',
      ));
    }

    // 2. Night-time elimination (nocturia)
    final hasHourly = days.any((d) => d.hourlyVisits.length == 24);
    if (hasHourly) {
      final recent = days.length > 7 ? days.sublist(days.length - 7) : days;
      final earlier = days.length > 7 ? days.sublist(0, days.length - 7) : <MonthlyDayRecord>[];
      final recentAvg = _avg(recent.map(_nightVisits));
      final earlierAvg = earlier.isEmpty ? null : _avg(earlier.map(_nightVisits));
      final nightDays = recent.where((d) => _nightVisits(d) >= 3).length;

      if (recentAvg >= 3) {
        out.add(_high(
          Icons.nightlight_round,
          'Nocturia Pattern Detected',
          'Averaging ${recentAvg.toStringAsFixed(1)} visits between 01:00 and 05:00 over the last '
              '${recent.length} days ($nightDays night${nightDays == 1 ? '' : 's'} with 3+ visits)'
              '${earlierAvg != null ? ', compared with ${earlierAvg.toStringAsFixed(1)} earlier in the month' : ''}. '
              'A shift to night-time elimination can indicate kidney, thyroid or urinary issues.',
        ));
      } else if (recentAvg >= 2 || (earlierAvg != null && recentAvg - earlierAvg >= 1.5)) {
        out.add(_medium(
          Icons.nightlight_round,
          'Increasing Night-time Visits',
          'Averaging ${recentAvg.toStringAsFixed(1)} night visits (01:00–05:00) recently'
              '${earlierAvg != null ? ' vs ${earlierAvg.toStringAsFixed(1)} earlier' : ''}.',
        ));
      } else {
        out.add(_ok(
          'Healthy Circadian Rhythm',
          'Visits follow a normal dawn / midday / dusk pattern with very few night-time visits '
              '(${recentAvg.toStringAsFixed(1)} per night).',
        ));
      }

      // 3. Overall frequency
      final avgPerDay = _avg(days.map(_dayVisits));
      if (avgPerDay > maxNormalVisits || (avgPerDay < minNormalVisits && avgPerDay > 0)) {
        out.add(_medium(
          Icons.swap_vert_rounded,
          avgPerDay > maxNormalVisits ? 'High Monthly Frequency' : 'Low Monthly Frequency',
          'Averaging ${avgPerDay.toStringAsFixed(1)} visits per day this month '
              '(healthy range $minNormalVisits–$maxNormalVisits).',
        ));
      }
    }

    // 4. Chronic gas baseline
    final overDays = days
        .where((d) =>
            d.medianAmmoniaPpm >= dangerAmmoniaPpm ||
            d.medianOdorIndex >= dangerOdorPercent)
        .toList();
    final latest = days.last;
    final first7 = _avg(days.take(7).map((d) => d.medianAmmoniaPpm));
    final last7 = _avg(
        (days.length > 7 ? days.sublist(days.length - 7) : days)
            .map((d) => d.medianAmmoniaPpm));
    final nh3Rise = first7 == 0 ? 0 : (last7 - first7) / first7 * 100;

    if (overDays.isNotEmpty) {
      out.add(_high(
        Icons.air_rounded,
        'Chronic Ammonia / Odor Rise',
        'Median gas levels crossed the danger threshold on ${overDays.length} day'
            '${overDays.length == 1 ? '' : 's'} (first on day ${overDays.first.dayOfMonth}). '
            'Latest: NH₃ ${latest.medianAmmoniaPpm.toStringAsFixed(1)} ppm, '
            'odor ${latest.medianOdorIndex.toStringAsFixed(0)}%. '
            'Deep clean the box and check for urinary changes.',
      ));
    } else if (n >= 14 && nh3Rise >= 30) {
      out.add(_medium(
        Icons.air_rounded,
        'Ammonia Baseline Trending Up',
        'Median ammonia is ${nh3Rise.toStringAsFixed(0)}% higher than at the start of the month '
            '(${first7.toStringAsFixed(1)} → ${last7.toStringAsFixed(1)} ppm) but still below the '
            '${dangerAmmoniaPpm.toStringAsFixed(0)} ppm alert.',
      ));
    } else {
      out.add(_ok(
        'Stable Air Quality',
        'Median ammonia (${latest.medianAmmoniaPpm.toStringAsFixed(1)} ppm) and odor '
            '(${latest.medianOdorIndex.toStringAsFixed(0)}%) stayed within the safe baseline.',
      ));
    }

    return _sorted(out);
  }

  static List<SummaryMetric> monthlySummary(List<MonthlyDayRecord> days) {
    final hasHourly = days.any((d) => d.hourlyVisits.length == 24);
    final avgPerDay = hasHourly ? _avg(days.map(_dayVisits)) : 0.0;
    return [
      SummaryMetric(
        icon: Icons.monitor_weight_outlined,
        label: 'Body Weight (7d avg)',
        value: days.isEmpty ? '--' : '${days.last.movingAvg7dKg.toStringAsFixed(2)} kg',
      ),
      SummaryMetric(
        icon: Icons.pets_rounded,
        label: 'Avg Visits / Day',
        value: hasHourly ? avgPerDay.toStringAsFixed(1) : '--',
      ),
    ];
  }
}