import 'package:app/features/admin_analytics/domain/models/admin_analytics_overview.dart';
import 'package:app/features/admin_analytics/domain/models/owner_dashboard_data.dart';

abstract class AdminAnalyticsRepository {
  Future<AdminAnalyticsOverview> fetchOverview({required int windowDays});

  Future<OwnerDashboardData> fetchDashboard();
}
