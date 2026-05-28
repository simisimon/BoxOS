import 'package:app/features/admin_analytics/domain/models/admin_analytics_overview.dart';

abstract class AdminAnalyticsRepository {
  Future<AdminAnalyticsOverview> fetchOverview();
}
