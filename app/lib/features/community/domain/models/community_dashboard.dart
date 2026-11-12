class CommunityDashboard {
  const CommunityDashboard({required this.stats});

  final CommunityStats stats;
}

class CommunityStats {
  const CommunityStats({
    required this.activeMembers,
    required this.activeTrainers,
    required this.owners,
    required this.messagesLast7Days,
  });

  final int activeMembers;
  final int activeTrainers;
  final int owners;
  final int messagesLast7Days;
}
