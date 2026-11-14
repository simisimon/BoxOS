class NotificationPreferences {
  const NotificationPreferences({
    required this.bookingConfirmations,
    required this.waitlistPromotions,
    required this.paymentIssues,
    required this.wodPosted,
    required this.prAchievements,
    required this.announcementActivity,
    this.resultActivity = true,
  });

  final bool bookingConfirmations;
  final bool waitlistPromotions;
  final bool paymentIssues;
  final bool wodPosted;
  final bool prAchievements;
  final bool announcementActivity;

  /// Fist bumps and comments on the athlete's results.
  final bool resultActivity;

  NotificationPreferences copyWith({
    bool? bookingConfirmations,
    bool? waitlistPromotions,
    bool? paymentIssues,
    bool? wodPosted,
    bool? prAchievements,
    bool? announcementActivity,
    bool? resultActivity,
  }) {
    return NotificationPreferences(
      bookingConfirmations: bookingConfirmations ?? this.bookingConfirmations,
      waitlistPromotions: waitlistPromotions ?? this.waitlistPromotions,
      paymentIssues: paymentIssues ?? this.paymentIssues,
      wodPosted: wodPosted ?? this.wodPosted,
      prAchievements: prAchievements ?? this.prAchievements,
      announcementActivity: announcementActivity ?? this.announcementActivity,
      resultActivity: resultActivity ?? this.resultActivity,
    );
  }
}
