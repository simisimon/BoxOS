class AdminAnalyticsOverview {
  const AdminAnalyticsOverview({
    required this.windowDays,
    required this.activeMembers,
    required this.activeTrainers,
    required this.pendingJoinRequests,
    required this.classesLast14Days,
    required this.bookingsLast14Days,
    required this.attendedLast14Days,
    required this.noShowsLast14Days,
    required this.attendanceRateLast14Days,
    required this.utilizationRateLast14Days,
    required this.noShowRateLast14Days,
    required this.upcomingClassesNext7Days,
    required this.upcomingBookingsNext7Days,
    required this.upcomingCapacityNext7Days,
    required this.dailyAttendance,
  });

  final int windowDays;
  final int activeMembers;
  final int activeTrainers;
  final int pendingJoinRequests;
  final int classesLast14Days;
  final int bookingsLast14Days;
  final int attendedLast14Days;
  final int noShowsLast14Days;
  final double attendanceRateLast14Days;
  final double utilizationRateLast14Days;
  final double noShowRateLast14Days;
  final int upcomingClassesNext7Days;
  final int upcomingBookingsNext7Days;
  final int upcomingCapacityNext7Days;
  final List<AdminAnalyticsDailyAttendance> dailyAttendance;
}

class AdminAnalyticsDailyAttendance {
  const AdminAnalyticsDailyAttendance({
    required this.date,
    required this.classes,
    required this.capacity,
    required this.bookings,
    required this.attended,
    required this.noShows,
    required this.utilizationRate,
  });

  final DateTime date;
  final int classes;
  final int capacity;
  final int bookings;
  final int attended;
  final int noShows;
  final double utilizationRate;
}
