import 'package:app/core/network/dio_client.dart';
import 'package:app/features/admin_analytics/domain/models/admin_analytics_overview.dart';
import 'package:app/features/admin_analytics/domain/repositories/admin_analytics_repository.dart';
import 'package:app/features/auth/data/session/secure_token_storage.dart';
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
  Future<AdminAnalyticsOverview> fetchOverview({required int windowDays}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/analytics',
      queryParameters: {'window_days': windowDays},
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
    final pressure = data['pressure_classes'] as List<dynamic>? ?? const [];
    return AdminAnalyticsOverview(
      windowDays: overview['window_days'] as int? ?? 14,
      activeMembers: overview['active_members'] as int? ?? 0,
      activeTrainers: overview['active_trainers'] as int? ?? 0,
      pendingJoinRequests: overview['pending_join_requests'] as int? ?? 0,
      classesInWindow: overview['classes_in_window'] as int? ?? 0,
      bookingsInWindow: overview['bookings_in_window'] as int? ?? 0,
      attendedInWindow: overview['attended_in_window'] as int? ?? 0,
      noShowsInWindow: overview['no_shows_in_window'] as int? ?? 0,
      attendanceRateInWindow:
          (overview['attendance_rate_in_window'] as num? ?? 0).toDouble(),
      utilizationRateInWindow:
          (overview['utilization_rate_in_window'] as num? ?? 0).toDouble(),
      noShowRateInWindow:
          (overview['no_show_rate_in_window'] as num? ?? 0).toDouble(),
      upcomingClassesNext7Days:
          overview['upcoming_classes_next_7_days'] as int? ?? 0,
      upcomingBookingsNext7Days:
          overview['upcoming_bookings_next_7_days'] as int? ?? 0,
      upcomingCapacityNext7Days:
          overview['upcoming_capacity_next_7_days'] as int? ?? 0,
      upcomingWaitlistSpotsNext7Days:
          overview['upcoming_waitlist_spots_next_7_days'] as int? ?? 0,
      upcomingClassesWithWaitlistNext7Days:
          overview['upcoming_classes_with_waitlist_next_7_days'] as int? ?? 0,
      upcomingFullClassesNext7Days:
          overview['upcoming_full_classes_next_7_days'] as int? ?? 0,
      dailyAttendance: daily
          .map(
            (item) => _dailyAttendanceFromJson(item as Map<String, dynamic>),
          )
          .toList(),
      pressureClasses: pressure
          .map(
            (item) => _pressureClassFromJson(item as Map<String, dynamic>),
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

  AdminAnalyticsPressureClass _pressureClassFromJson(
    Map<String, dynamic> data,
  ) {
    return AdminAnalyticsPressureClass(
      id: data['id'] as int? ?? 0,
      title: data['title'] as String? ?? '',
      startTime: DateTime.parse(data['start_time'] as String? ?? ''),
      capacity: data['capacity'] as int? ?? 0,
      bookings: data['bookings'] as int? ?? 0,
      waitlistCount: data['waitlist_count'] as int? ?? 0,
      utilizationRate: (data['utilization_rate'] as num? ?? 0).toDouble(),
    );
  }
}
