import 'dart:async';
import '../models/analytics_model.dart';

class ApiService {
  /// Fetches analytics data structure
  static Future<AnalyticsModel> fetchAnalyticsData() async {
    return AnalyticsModel(
      totalCleanings: 0,
      wasteWeightKg: 0.0,
      weeklyUsage: const [],
    );
  }
}
