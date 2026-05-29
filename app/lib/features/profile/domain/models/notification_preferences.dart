class NotificationPreferences {
  const NotificationPreferences({
    required this.bookingConfirmations,
    required this.waitlistPromotions,
    required this.paymentIssues,
    required this.wodPosted,
    required this.prAchievements,
    required this.announcementActivity,
  });

  final bool bookingConfirmations;
  final bool waitlistPromotions;
  final bool paymentIssues;
  final bool wodPosted;
  final bool prAchievements;
  final bool announcementActivity;

  NotificationPreferences copyWith({
    bool? bookingConfirmations,
    bool? waitlistPromotions,
    bool? paymentIssues,
    bool? wodPosted,
    bool? prAchievements,
    bool? announcementActivity,
  }) {
    return NotificationPreferences(
      bookingConfirmations: bookingConfirmations ?? this.bookingConfirmations,
      waitlistPromotions: waitlistPromotions ?? this.waitlistPromotions,
      paymentIssues: paymentIssues ?? this.paymentIssues,
      wodPosted: wodPosted ?? this.wodPosted,
      prAchievements: prAchievements ?? this.prAchievements,
      announcementActivity: announcementActivity ?? this.announcementActivity,
    );
  }
}
