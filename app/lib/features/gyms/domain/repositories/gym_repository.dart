import 'dart:typed_data';

import 'package:app/features/gyms/domain/models/gym_join_request.dart';
import 'package:app/features/gyms/domain/models/my_gym_join_request.dart';
import 'package:app/features/profile/domain/models/gym_summary.dart';

abstract class GymRepository {
  Future<List<GymSummary>> listGyms();

  Future<GymSummary> createGym({
    required String name,
    required String logoUrl,
    required String timezone,
  });

  Future<String> uploadGymLogo({
    required Uint8List bytes,
    required String filename,
    required String contentType,
  });

  Future<void> requestJoin({required int gymId});

  Future<List<MyGymJoinRequest>> fetchMyJoinRequests();

  Future<List<GymJoinRequest>> fetchJoinRequests();

  Future<void> reviewJoinRequest({
    required int requestId,
    required bool approve,
  });
}
