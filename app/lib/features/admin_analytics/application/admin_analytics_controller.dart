import 'package:app/features/admin_analytics/data/repositories/api_admin_analytics_repository.dart';
import 'package:app/features/admin_analytics/domain/models/admin_analytics_overview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final adminAnalyticsOverviewProvider =
    FutureProvider<AdminAnalyticsOverview>((ref) async {
      final repository = ref.read(adminAnalyticsRepositoryProvider);
      return repository.fetchOverview();
    });
