import 'dart:typed_data';

import 'package:app/features/gyms/domain/models/gym_join_request.dart';
import 'package:app/features/gyms/domain/models/gym_update_result.dart';
import 'package:app/features/gyms/domain/models/my_gym_join_request.dart';
import 'package:app/features/profile/domain/models/gym_summary.dart';

abstract class GymRepository {
  Future<List<GymSummary>> listGyms();

  Future<GymSummary> createGym({
    required String name,
    required String logoUrl,
    required String timezone,
  });

  /// Edits the active box's identity (owner only). Fields left null are kept;
  /// an empty [logoUrl] removes the logo.
  Future<GymUpdateResult> updateCurrentGym({
    String? name,
    String? logoUrl,
    String? timezone,
  });

  Future<String> uploadGymLogo({
    required Uint8List bytes,
    required String filename,
    required String contentType,
  });

  /// [planId] is the plan the athlete would like; the owner reviews it as a
  /// plan request once the join request is approved.
  Future<void> requestJoin({required int gymId, int? planId});

  Future<List<MyGymJoinRequest>> fetchMyJoinRequests();

  Future<List<GymJoinRequest>> fetchJoinRequests();

  Future<void> reviewJoinRequest({
    required int requestId,
    required bool approve,
  });
}
