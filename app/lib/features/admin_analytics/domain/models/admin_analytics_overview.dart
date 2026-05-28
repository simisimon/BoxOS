class AdminAnalyticsOverview {
  const AdminAnalyticsOverview({
    required this.windowDays,
    required this.activeMembers,
    required this.activeTrainers,
    required this.pendingJoinRequests,
    required this.newMembersInWindow,
    required this.roleMix,
    required this.recentMembers,
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
    required this.problemClasses,
  });

  final int windowDays;
  final int activeMembers;
  final int activeTrainers;
  final int pendingJoinRequests;
  final int newMembersInWindow;
  final AdminAnalyticsRoleMix roleMix;
  final List<AdminAnalyticsRecentMember> recentMembers;
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
  final List<AdminAnalyticsProblemClass> problemClasses;
}

class AdminAnalyticsRoleMix {
  const AdminAnalyticsRoleMix({
    required this.athleteOnly,
    required this.trainerCapable,
    required this.adminCapable,
  });

  final int athleteOnly;
  final int trainerCapable;
  final int adminCapable;
}

class AdminAnalyticsRecentMember {
  const AdminAnalyticsRecentMember({
    required this.membershipId,
    required this.userId,
    required this.email,
    required this.displayName,
    required this.nickname,
    required this.activeRole,
    required this.createdAt,
  });

  final int membershipId;
  final int userId;
  final String email;
  final String displayName;
  final String nickname;
  final String activeRole;
  final DateTime createdAt;
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

class AdminAnalyticsProblemClass {
  const AdminAnalyticsProblemClass({
    required this.id,
    required this.title,
    required this.startTime,
    required this.capacity,
    required this.bookings,
    required this.attended,
    required this.noShows,
    required this.utilizationRate,
    required this.attendanceRate,
    required this.noShowRate,
  });

  final int id;
  final String title;
  final DateTime startTime;
  final int capacity;
  final int bookings;
  final int attended;
  final int noShows;
  final double utilizationRate;
  final double attendanceRate;
  final double noShowRate;
}
