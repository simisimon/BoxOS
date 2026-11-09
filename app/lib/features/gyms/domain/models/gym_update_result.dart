import 'package:app/features/profile/domain/models/gym_summary.dart';

/// Result of editing the box identity. [detachedSessions] counts booked
/// classes that kept their time after a timezone change and became one-offs.
class GymUpdateResult {
  const GymUpdateResult({required this.gym, required this.detachedSessions});

  final GymSummary gym;
  final int detachedSessions;
}
