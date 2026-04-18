import 'package:app/features/profile/domain/models/gym_summary.dart';

class MyGymJoinRequest {
  const MyGymJoinRequest({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.reviewedAt,
    required this.gym,
  });

  final int id;
  final String status;
  final String createdAt;
  final String? reviewedAt;
  final GymSummary gym;
}
