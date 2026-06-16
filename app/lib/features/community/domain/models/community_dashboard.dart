class CommunityDashboard {
  const CommunityDashboard({required this.stats, required this.newestPrs});

  final CommunityStats stats;
  final List<CommunityPr> newestPrs;
}

class CommunityStats {
  const CommunityStats({
    required this.activeMembers,
    required this.activeTrainers,
    required this.owners,
    required this.prsLast30Days,
    required this.messagesLast7Days,
  });

  final int activeMembers;
  final int activeTrainers;
  final int owners;
  final int prsLast30Days;
  final int messagesLast7Days;
}

class CommunityPr {
  const CommunityPr({
    required this.userId,
    required this.displayName,
    required this.nickname,
    required this.workoutTitle,
    required this.scoreLabel,
    required this.updatedAt,
  });

  final int userId;
  final String displayName;
  final String nickname;
  final String workoutTitle;
  final String scoreLabel;
  final DateTime updatedAt;

  String get memberLabel {
    if (displayName.trim().isNotEmpty) return displayName;
    if (nickname.trim().isNotEmpty) return nickname;
    return 'Member';
  }
}
