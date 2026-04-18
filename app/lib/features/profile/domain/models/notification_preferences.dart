class NotificationPreferences {
  const NotificationPreferences({
    required this.bookingConfirmations,
    required this.waitlistPromotions,
    required this.paymentIssues,
    required this.wodPosted,
    required this.prAchievements,
  });

  final bool bookingConfirmations;
  final bool waitlistPromotions;
  final bool paymentIssues;
  final bool wodPosted;
  final bool prAchievements;

  NotificationPreferences copyWith({
    bool? bookingConfirmations,
    bool? waitlistPromotions,
    bool? paymentIssues,
    bool? wodPosted,
    bool? prAchievements,
  }) {
    return NotificationPreferences(
      bookingConfirmations: bookingConfirmations ?? this.bookingConfirmations,
      waitlistPromotions: waitlistPromotions ?? this.waitlistPromotions,
      paymentIssues: paymentIssues ?? this.paymentIssues,
      wodPosted: wodPosted ?? this.wodPosted,
      prAchievements: prAchievements ?? this.prAchievements,
    );
  }
}
