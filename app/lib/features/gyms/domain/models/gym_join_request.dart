class GymJoinRequest {
  const GymJoinRequest({
    required this.id,
    required this.email,
    required this.displayName,
    required this.nickname,
    required this.createdAt,
  });

  final int id;
  final String email;
  final String displayName;
  final String nickname;
  final String createdAt;
}
