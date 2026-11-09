class GymJoinRequest {
  const GymJoinRequest({
    required this.id,
    required this.email,
    required this.displayName,
    required this.nickname,
    required this.createdAt,
    this.requestedPlanName,
  });

  final int id;
  final String email;
  final String displayName;
  final String nickname;
  final String createdAt;

  /// Plan the athlete picked while asking to join; it becomes a plan request
  /// once the join request is approved.
  final String? requestedPlanName;
}
