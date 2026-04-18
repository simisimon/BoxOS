class ScheduleBooking {
  const ScheduleBooking({
    required this.userId,
    required this.displayName,
    required this.nickname,
    required this.attendanceStatus,
    required this.isCurrentUser,
  });

  final int userId;
  final String displayName;
  final String nickname;
  final String attendanceStatus;
  final bool isCurrentUser;
}
