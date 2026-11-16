import 'package:flutter_test/flutter_test.dart';
import 'package:purrclean_test/services/behavior_insights_service.dart';
import 'package:purrclean_test/services/sensor_service.dart';

VisitRecord visit(
  int id, {
  int seconds = 60,
  double ammonia = 0,
  double odor = 0,
  double deposit = 0,
  double hour = 12,
  String status = 'normal',
}) {
  return VisitRecord(
    id: '$id',
    hourX: hour,
    timeLabel: '12:00',
    durationMinutes: seconds / 60,
    durationSeconds: seconds,
    ammoniaPpm: ammonia,
    odorIndex: odor,
    depositGrams: deposit,
    status: status,
  );
}

void main() {
  group('UC-004: view usage data', () {
    test('empty data shows a no-data insight and empty summary values', () {
      final insights = BehaviorInsightsService.daily(const []);
      final summary = BehaviorInsightsService.dailySummary(
        const [],
        inSeconds: true,
      );

      expect(insights.single.title, 'No data yet');
      expect(summary.first.value, '0 visits');
      expect(summary.last.value, '--');
    });

    test('summary counts visits and calculates average dwell time', () {
      final summary = BehaviorInsightsService.dailySummary(
        [visit(1, seconds: 30), visit(2, seconds: 60), visit(3, seconds: 90)],
        inSeconds: true,
      );

      expect(summary.first.value, '3 visits');
      expect(summary.last.value, '60 sec');
    });
  });

  group('UC-005 and UC-006: detect and analyze behavior', () {
    test('normal visits do not produce abnormal-behavior insights', () {
      final insights = BehaviorInsightsService.daily(
        [visit(1), visit(2), visit(3)],
        now: DateTime(2026, 11, 16, 12),
      );
      final titles = insights.map((insight) => insight.title);

      expect(titles, contains('Normal Visit Frequency'));
      expect(titles, contains('Dwell Time & Air Quality Normal'));
      expect(titles, isNot(contains('High Visit Frequency')));
      expect(titles, isNot(contains('High Ammonia / Odor Levels')));
    });

    test('high frequency, prolonged dwell, and gas readings are flagged', () {
      final visits = [
        for (var id = 0; id < 8; id++) visit(id),
        visit(8, seconds: 180, ammonia: 30, odor: 80, status: 'straining'),
      ];
      final insights = BehaviorInsightsService.daily(
        visits,
        now: DateTime(2026, 11, 16, 12),
      );
      final titles = insights.map((insight) => insight.title);

      expect(titles, contains('High Visit Frequency'));
      expect(titles, contains('Extended Dwell Time'));
      expect(titles, contains('High Ammonia / Odor Levels'));
    });
  });
}
