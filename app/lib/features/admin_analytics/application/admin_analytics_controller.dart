import 'package:app/features/admin_analytics/data/repositories/api_admin_analytics_repository.dart';
import 'package:app/features/admin_analytics/domain/models/admin_analytics_overview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final adminAnalyticsWindowDaysProvider =
    NotifierProvider<AdminAnalyticsWindowDaysNotifier, int>(
      AdminAnalyticsWindowDaysNotifier.new,
    );

class AdminAnalyticsWindowDaysNotifier extends Notifier<int> {
  @override
  int build() => 14;

  void setWindowDays(int value) {
    state = value;
  }
}

final adminAnalyticsOverviewProvider = FutureProvider<AdminAnalyticsOverview>((
  ref,
) async {
  final repository = ref.read(adminAnalyticsRepositoryProvider);
  final windowDays = ref.watch(adminAnalyticsWindowDaysProvider);
  return repository.fetchOverview(windowDays: windowDays);
});
