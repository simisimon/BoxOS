class AdminAnalyticsOverview {
  const AdminAnalyticsOverview({
    required this.windowDays,
    required this.activeMembers,
    required this.activeTrainers,
    required this.pendingJoinRequests,
    required this.classesInWindow,
    required this.bookingsInWindow,
    required this.attendedInWindow,
    required this.noShowsInWindow,
    required this.attendanceRateInWindow,
    required this.utilizationRateInWindow,
    required this.noShowRateInWindow,
    required this.upcomingClassesNext7Days,
    required this.upcomingBookingsNext7Days,
    required this.upcomingCapacityNext7Days,
    required this.upcomingWaitlistSpotsNext7Days,
    required this.upcomingClassesWithWaitlistNext7Days,
    required this.upcomingFullClassesNext7Days,
    required this.dailyAttendance,
    required this.pressureClasses,
  });

  final int windowDays;
  final int activeMembers;
  final int activeTrainers;
  final int pendingJoinRequests;
  final int classesInWindow;
  final int bookingsInWindow;
  final int attendedInWindow;
  final int noShowsInWindow;
  final double attendanceRateInWindow;
  final double utilizationRateInWindow;
  final double noShowRateInWindow;
  final int upcomingClassesNext7Days;
  final int upcomingBookingsNext7Days;
  final int upcomingCapacityNext7Days;
  final int upcomingWaitlistSpotsNext7Days;
  final int upcomingClassesWithWaitlistNext7Days;
  final int upcomingFullClassesNext7Days;
  final List<AdminAnalyticsDailyAttendance> dailyAttendance;
  final List<AdminAnalyticsPressureClass> pressureClasses;
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

class AdminAnalyticsPressureClass {
  const AdminAnalyticsPressureClass({
    required this.id,
    required this.title,
    required this.startTime,
    required this.capacity,
    required this.bookings,
    required this.waitlistCount,
    required this.utilizationRate,
  });

  final int id;
  final String title;
  final DateTime startTime;
  final int capacity;
  final int bookings;
  final int waitlistCount;
  final double utilizationRate;
}
