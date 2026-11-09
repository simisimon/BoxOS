import 'package:app/core/network/dio_client.dart';
import 'package:app/features/auth/data/session/secure_token_storage.dart';
import 'package:app/features/auth/data/session/token_storage.dart';
import 'package:app/features/memberships/domain/membership_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final membershipRepositoryProvider = Provider<MembershipRepository>((ref) {
  return MembershipRepository(
    dio: ref.read(dioProvider),
    tokenStorage: ref.read(tokenStorageProvider),
  );
});

/// Open plan requests of the active box (owners only). Counted into the
/// Members nav badge next to join requests.
/// Errors count as "none" so the badge never blocks or retries the shell.
final pendingPlanRequestsProvider =
    FutureProvider.autoDispose<List<MemberPlan>>((ref) async {
      try {
        return await ref.read(membershipRepositoryProvider).fetchPlanRequests();
      } catch (_) {
        return const [];
      }
    });

/// Client for the `/membership/*` endpoints (see `backend/plan_service.py`).
class MembershipRepository {
  MembershipRepository({required Dio dio, required TokenStorage tokenStorage})
    : _dio = dio,
      _tokenStorage = tokenStorage;

  final Dio _dio;
  final TokenStorage _tokenStorage;

  Future<MembershipSettings> fetchSettings() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/membership/settings',
      options: await _options(),
    );
    return MembershipSettings.fromJson(response.data);
  }

  Future<MembershipSettings> updateSettings({
    String? currency,
    bool? requirePlanForBooking,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/membership/settings',
      data: {
        'currency': ?currency,
        'require_plan_for_booking': ?requirePlanForBooking,
      },
      options: await _options(),
    );
    return MembershipSettings.fromJson(response.data);
  }

  Future<List<MembershipPlan>> fetchPlans({
    bool includeArchived = false,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/membership/plans',
      queryParameters: {if (includeArchived) 'include_archived': true},
      options: await _options(),
    );
    return _plans(response.data);
  }

  /// Plans a box offers, for choosing one in the join request.
  Future<List<MembershipPlan>> fetchGymPlans(int gymId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/gyms/$gymId/plans',
      options: await _options(),
    );
    return _plans(response.data);
  }

  Future<MembershipPlan> createPlan(MembershipPlanDraft draft) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/membership/plans',
      data: draft.toJson(),
      options: await _options(),
    );
    return _plan(response.data);
  }

  Future<MembershipPlan> updatePlan(
    int planId,
    MembershipPlanDraft draft,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/membership/plans',
      data: {...draft.toJson(), 'plan_id': planId},
      options: await _options(),
    );
    return _plan(response.data);
  }

  Future<MembershipPlan> setPlanArchived(
    int planId, {
    required bool archived,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/membership/plans/archive',
      data: {'plan_id': planId, 'archived': archived},
      options: await _options(),
    );
    return _plan(response.data);
  }

  Future<MyMembership> fetchMyMembership() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/membership/me',
      options: await _options(),
    );
    return MyMembership(
      plans: _memberPlans(response.data?['plans']),
      requirePlanForBooking:
          response.data?['require_plan_for_booking'] as bool? ?? false,
    );
  }

  Future<void> requestPlan(int planId) async {
    await _dio.post<void>(
      '/membership/requests',
      data: {'plan_id': planId},
      options: await _options(),
    );
  }

  Future<void> withdrawPlanRequest() async {
    await _dio.delete<void>('/membership/requests', options: await _options());
  }

  Future<List<MemberPlan>> fetchPlanRequests() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/membership/requests',
      options: await _options(),
    );
    return _memberPlans(response.data?['requests']);
  }

  Future<void> reviewPlanRequest({
    required int requestId,
    required bool approve,
    String? startsOn,
    int? priceCents,
  }) async {
    await _dio.patch<void>(
      '/membership/requests',
      data: {
        'request_id': requestId,
        'decision': approve ? 'approve' : 'reject',
        'starts_on': ?startsOn,
        'price_cents': ?priceCents,
      },
      options: await _options(),
    );
  }

  Future<List<MemberPlan>> fetchMemberPlans(int userId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/membership/members/$userId',
      options: await _options(),
    );
    return _memberPlans(response.data?['plans']);
  }

  Future<void> assignPlan({
    required int userId,
    required int planId,
    String? startsOn,
    int? priceCents,
  }) async {
    await _dio.post<void>(
      '/membership/assignments',
      data: {
        'user_id': userId,
        'plan_id': planId,
        'starts_on': ?startsOn,
        'price_cents': ?priceCents,
      },
      options: await _options(),
    );
  }

  Future<void> updatePaymentStatus(
    int memberPlanId,
    PaymentStatus status,
  ) async {
    await _dio.patch<void>(
      '/membership/assignments',
      data: {'member_plan_id': memberPlanId, 'payment_status': status.apiValue},
      options: await _options(),
    );
  }

  Future<void> endMemberPlan(int memberPlanId) async {
    await _dio.post<void>(
      '/membership/assignments/end',
      data: {'member_plan_id': memberPlanId},
      options: await _options(),
    );
  }

  Future<Options> _options() async {
    final tokens = await _tokenStorage.readTokens();
    if (tokens == null) {
      throw Exception('No active session found.');
    }
    return Options(headers: {'Authorization': 'Bearer ${tokens.accessToken}'});
  }

  List<MembershipPlan> _plans(Map<String, dynamic>? data) => [
    for (final item in data?['plans'] as List<dynamic>? ?? const [])
      MembershipPlan.fromJson(item as Map<String, dynamic>),
  ];

  MembershipPlan _plan(Map<String, dynamic>? data) {
    final plan = data?['plan'] as Map<String, dynamic>?;
    if (plan == null) throw Exception('Missing plan data.');
    return MembershipPlan.fromJson(plan);
  }

  List<MemberPlan> _memberPlans(dynamic items) => [
    for (final item in items as List<dynamic>? ?? const [])
      MemberPlan.fromJson(item as Map<String, dynamic>),
  ];
}
