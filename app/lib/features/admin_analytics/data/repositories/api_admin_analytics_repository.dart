import 'package:app/core/network/dio_client.dart';
import 'package:app/features/admin_analytics/domain/models/admin_analytics_overview.dart';
import 'package:app/features/admin_analytics/domain/repositories/admin_analytics_repository.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final adminAnalyticsRepositoryProvider = Provider<AdminAnalyticsRepository>((
  ref,
) {
  final dio = ref.read(dioProvider);
  final tokenStorage = ref.read(tokenStorageProvider);
  return ApiAdminAnalyticsRepository(dio: dio, tokenStorage: tokenStorage);
});

class ApiAdminAnalyticsRepository implements AdminAnalyticsRepository {
  ApiAdminAnalyticsRepository({
    required Dio dio,
    required TokenStorage tokenStorage,
  }) : _dio = dio,
       _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  @override
  Future<AdminAnalyticsOverview> fetchOverview() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/analytics',
      options: Options(headers: await _authHeaders()),
    );
    return _overviewFromJson(response.data);
  }

  Future<Map<String, String>> _authHeaders() async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens == null) {
      throw Exception('No active session found.');
    }
    return {'Authorization': 'Bearer ${tokens.accessToken}'};
  }

  AdminAnalyticsOverview _overviewFromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing admin analytics data.');
    }
    final overview = data['overview'] as Map<String, dynamic>?;
    if (overview == null) {
      throw Exception('Missing admin analytics overview.');
    }
    final daily = data['daily_attendance'] as List<dynamic>? ?? const [];
    return AdminAnalyticsOverview(
      windowDays: overview['window_days'] as int? ?? 14,
      activeMembers: overview['active_members'] as int? ?? 0,
      activeTrainers: overview['active_trainers'] as int? ?? 0,
      pendingJoinRequests: overview['pending_join_requests'] as int? ?? 0,
      classesLast14Days: overview['classes_last_14_days'] as int? ?? 0,
      bookingsLast14Days: overview['bookings_last_14_days'] as int? ?? 0,
      attendedLast14Days: overview['attended_last_14_days'] as int? ?? 0,
      noShowsLast14Days: overview['no_shows_last_14_days'] as int? ?? 0,
      attendanceRateLast14Days:
          (overview['attendance_rate_last_14_days'] as num? ?? 0).toDouble(),
      utilizationRateLast14Days:
          (overview['utilization_rate_last_14_days'] as num? ?? 0).toDouble(),
      noShowRateLast14Days:
          (overview['no_show_rate_last_14_days'] as num? ?? 0).toDouble(),
      upcomingClassesNext7Days:
          overview['upcoming_classes_next_7_days'] as int? ?? 0,
      upcomingBookingsNext7Days:
          overview['upcoming_bookings_next_7_days'] as int? ?? 0,
      upcomingCapacityNext7Days:
          overview['upcoming_capacity_next_7_days'] as int? ?? 0,
      dailyAttendance: daily
          .map(
            (item) => _dailyAttendanceFromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  AdminAnalyticsDailyAttendance _dailyAttendanceFromJson(
    Map<String, dynamic> data,
  ) {
    return AdminAnalyticsDailyAttendance(
      date: DateTime.parse(data['date'] as String? ?? ''),
      classes: data['classes'] as int? ?? 0,
      capacity: data['capacity'] as int? ?? 0,
      bookings: data['bookings'] as int? ?? 0,
      attended: data['attended'] as int? ?? 0,
      noShows: data['no_shows'] as int? ?? 0,
      utilizationRate: (data['utilization_rate'] as num? ?? 0).toDouble(),
    );
  }
}
