import 'package:app/core/network/dio_client.dart';
import 'package:app/features/auth/data/session/secure_token_storage.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:app/features/calendar/domain/models/schedule_booking.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:app/features/calendar/domain/models/schedule_section.dart';
import 'package:app/features/calendar/domain/models/schedule_trainer.dart';
import 'package:app/features/calendar/domain/repositories/schedule_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  final dio = ref.read(dioProvider);
  final tokenStorage = ref.read(tokenStorageProvider);
  return ApiScheduleRepository(dio: dio, tokenStorage: tokenStorage);
});

/// Shared schedule list so the month grid and the day-detail sheet read the
/// same data and stay in sync — mutating actions just `ref.invalidate` this and
/// every watcher (grid + open sheet) refreshes.
final scheduleListProvider = FutureProvider.autoDispose<List<ScheduleClass>>(
  (ref) => ref.watch(scheduleRepositoryProvider).fetchSchedule(),
);

class ApiScheduleRepository implements ScheduleRepository {
  ApiScheduleRepository({required Dio dio, required TokenStorage tokenStorage})
    : _dio = dio,
      _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  @override
  Future<List<ScheduleClass>> fetchSchedule() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/schedule/classes',
      options: Options(headers: await _authHeaders()),
    );
    final items = response.data?['classes'] as List<dynamic>? ?? const [];
    return items
        .map((item) => _fromJson(item as Map<String, dynamic>?))
        .toList();
  }

  @override
  Future<ScheduleImportResult> importClasses(
    List<Map<String, dynamic>> rows,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/schedule/classes/import',
      data: {'rows': rows},
      options: Options(
        headers: await _authHeaders(),
        // 422 carries the per-row validation errors — read it instead of
        // throwing so the dialog can surface them.
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    final data = response.data ?? const <String, dynamic>{};
    final errors = ((data['errors'] as List<dynamic>?) ?? const [])
        .map((item) {
          final map = item as Map<String, dynamic>;
          return ScheduleImportError(
            row: map['row'] as int? ?? 0,
            message: map['message'] as String? ?? 'Invalid row',
          );
        })
        .toList();
    return ScheduleImportResult(
      createdCount: data['created_count'] as int? ?? 0,
      errors: errors,
    );
  }

  @override
  Future<List<ScheduleTrainer>> fetchTrainers() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/schedule/trainers',
      options: Options(headers: await _authHeaders()),
    );
    final items = response.data?['trainers'] as List<dynamic>? ?? const [];
    return items
        .map((item) => _trainerFromJson(item as Map<String, dynamic>?))
        .toList();
  }

  @override
  Future<ScheduleClass> createClass({
    required String title,
    required String classType,
    required DateTime startTime,
    required int durationMinutes,
    required int capacity,
    required int trainerUserId,
    required String wodDescription,
    List<ScheduleSection> sections = const [],
    String recurrenceFrequency = 'none',
    int occurrenceCount = 1,
  }) async {
    final endTime = startTime.add(Duration(minutes: durationMinutes));
    final response = await _dio.post<Map<String, dynamic>>(
      '/schedule/classes',
      data: {
        'title': title,
        'class_type': classType,
        'start_time': startTime.toUtc().toIso8601String(),
        'end_time': endTime.toUtc().toIso8601String(),
        'duration_minutes': durationMinutes,
        'capacity': capacity,
        'trainer_user_id': trainerUserId,
        'wod_description': wodDescription,
        'sections': [for (final section in sections) section.toJson()],
        'recurrence_frequency': recurrenceFrequency,
        'occurrence_count': occurrenceCount,
      },
      options: Options(headers: await _authHeaders()),
    );
    return _fromJson(response.data?['class'] as Map<String, dynamic>?);
  }

  @override
  Future<ScheduleClass> updateClass({
    required int id,
    required String title,
    required String classType,
    required DateTime startTime,
    required int durationMinutes,
    required int capacity,
    required int trainerUserId,
    required String wodDescription,
    List<ScheduleSection> sections = const [],
  }) async {
    final endTime = startTime.add(Duration(minutes: durationMinutes));
    final response = await _dio.patch<Map<String, dynamic>>(
      '/schedule/classes',
      data: {
        'id': id,
        'title': title,
        'class_type': classType,
        'start_time': startTime.toUtc().toIso8601String(),
        'end_time': endTime.toUtc().toIso8601String(),
        'duration_minutes': durationMinutes,
        'capacity': capacity,
        'trainer_user_id': trainerUserId,
        'wod_description': wodDescription,
        'sections': [for (final section in sections) section.toJson()],
      },
      options: Options(headers: await _authHeaders()),
    );
    return _fromJson(response.data?['class'] as Map<String, dynamic>?);
  }

  @override
  Future<void> deleteClass({required int id}) async {
    await _dio.delete<void>(
      '/schedule/classes',
      data: {'id': id},
      options: Options(headers: await _authHeaders()),
    );
  }

  @override
  Future<void> bookClass({required int classId}) async {
    await _dio.post<void>(
      '/schedule/bookings',
      data: {'class_id': classId},
      options: Options(headers: await _authHeaders()),
    );
  }

  @override
  Future<void> cancelBooking({required int classId}) async {
    await _dio.delete<void>(
      '/schedule/bookings',
      data: {'class_id': classId},
      options: Options(headers: await _authHeaders()),
    );
  }

  @override
  Future<void> joinWaitlist({required int classId}) async {
    await _dio.post<void>(
      '/schedule/waitlist',
      data: {'class_id': classId},
      options: Options(headers: await _authHeaders()),
    );
  }

  @override
  Future<void> leaveWaitlist({required int classId}) async {
    await _dio.delete<void>(
      '/schedule/waitlist',
      data: {'class_id': classId},
      options: Options(headers: await _authHeaders()),
    );
  }

  @override
  Future<ScheduleClass> updateAttendance({
    required int classId,
    required int userId,
    required String attendanceStatus,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/schedule/bookings/attendance',
      data: {
        'class_id': classId,
        'user_id': userId,
        'attendance_status': attendanceStatus,
      },
      options: Options(headers: await _authHeaders()),
    );
    return _fromJson(response.data?['class'] as Map<String, dynamic>?);
  }

  Future<Map<String, String>> _authHeaders() async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens == null) {
      throw Exception('No active session found.');
    }
    return {'Authorization': 'Bearer ${tokens.accessToken}'};
  }

  ScheduleClass _fromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing class schedule data.');
    }
    return ScheduleClass(
      id: data['id'] as int? ?? 0,
      gymId: data['gym_id'] as int? ?? 0,
      title: data['title'] as String? ?? '',
      classType: data['class_type'] as String? ?? '',
      startTime: DateTime.parse(data['start_time'] as String? ?? '').toLocal(),
      durationMinutes: data['duration_minutes'] as int? ?? 60,
      capacity: data['capacity'] as int? ?? 0,
      assignedTrainer: _nullableTrainerFromJson(
        data['assigned_trainer'] as Map<String, dynamic>?,
      ),
      wodDescription: data['wod_description'] as String? ?? '',
      sections: ((data['sections'] as List<dynamic>?) ?? const [])
          .map((item) => _sectionFromJson(item as Map<String, dynamic>?))
          .toList(),
      bookedCount: data['booked_count'] as int? ?? 0,
      remainingSpots: data['remaining_spots'] as int? ?? 0,
      waitlistCount: data['waitlist_count'] as int? ?? 0,
      isBooked: data['is_booked'] as bool? ?? false,
      isWaitlisted: data['is_waitlisted'] as bool? ?? false,
      attendanceStatus: data['attendance_status'] as String?,
      bookings: ((data['bookings'] as List<dynamic>?) ?? const [])
          .map((item) => _bookingFromJson(item as Map<String, dynamic>?))
          .toList(),
    );
  }

  ScheduleSection _sectionFromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing section data.');
    }
    return ScheduleSection(
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      scoreType: ScheduleSectionScore.fromApi(data['score_type'] as String?),
    );
  }

  ScheduleBooking _bookingFromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing booking data.');
    }
    return ScheduleBooking(
      userId: data['user_id'] as int? ?? 0,
      displayName: data['display_name'] as String? ?? '',
      nickname: data['nickname'] as String? ?? '',
      attendanceStatus: data['attendance_status'] as String? ?? 'booked',
      isCurrentUser: data['is_current_user'] as bool? ?? false,
    );
  }

  ScheduleTrainer? _nullableTrainerFromJson(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    return _trainerFromJson(data);
  }

  ScheduleTrainer _trainerFromJson(Map<String, dynamic>? data) {
    if (data == null) {
      throw Exception('Missing trainer data.');
    }
    return ScheduleTrainer(
      id: data['id'] as int? ?? 0,
      displayName: data['display_name'] as String? ?? '',
      nickname: data['nickname'] as String? ?? '',
    );
  }
}
