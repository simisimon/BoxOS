import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/app.dart';
import 'package:app/core/routing/router.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/data/repositories/api_auth_repository.dart';
import 'package:app/features/auth/domain/repositories/auth_repository.dart';
import 'package:app/features/announcements/data/repositories/api_announcement_repository.dart';
import 'package:app/features/announcements/domain/models/announcement.dart';
import 'package:app/features/announcements/domain/repositories/announcement_repository.dart';
import 'package:app/features/auth/presentation/screens/change_password_screen.dart';
import 'package:app/features/auth/presentation/screens/delete_account_screen.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/schedule_booking.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:app/features/calendar/domain/models/schedule_section.dart';
import 'package:app/features/calendar/domain/models/schedule_trainer.dart';
import 'package:app/features/calendar/domain/repositories/schedule_repository.dart';
import 'package:app/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:app/features/gyms/data/repositories/api_gym_repository.dart';
import 'package:app/features/gyms/domain/models/gym_join_request.dart';
import 'package:app/features/gyms/domain/models/my_gym_join_request.dart';
import 'package:app/features/gyms/domain/repositories/gym_repository.dart';
import 'package:app/features/gyms/presentation/screens/create_gym_screen.dart';
import 'package:app/features/gyms/presentation/screens/gym_directory_screen.dart';
import 'package:app/features/gyms/presentation/screens/join_requests_screen.dart';
import 'package:app/features/home/presentation/screens/home_screen.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/domain/models/app_notification.dart';
import 'package:app/features/profile/domain/models/gym_membership.dart';
import 'package:app/features/profile/domain/models/gym_summary.dart';
import 'package:app/features/profile/data/repositories/api_profile_repository.dart';
import 'package:app/features/profile/domain/models/notification_preferences.dart';
import 'package:app/features/profile/domain/models/role_managed_user.dart';
import 'package:app/features/profile/domain/models/user_profile.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:app/features/profile/domain/repositories/profile_repository.dart';
import 'package:app/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:app/features/profile/presentation/screens/notification_settings_screen.dart';
import 'package:app/features/profile/presentation/screens/notifications_screen.dart';
import 'package:app/features/profile/presentation/screens/profile_screen.dart';
import 'package:app/features/profile/presentation/screens/role_management_screen.dart';
import 'package:go_router/go_router.dart';

class RecordingAuthRepository implements AuthRepository {
  bool isSignedIn = false;
  String? signUpEmail;
  String? signUpPassword;
  String? adminSignUpEmail;
  String? adminSignUpPassword;
  String? passwordResetEmail;
  String? resetToken;
  String? resetNewPassword;
  bool? resetLogoutOtherSessions;
  String? verifyToken;
  String? verifyType;
  String? resendEmail;
  String? changeCurrentPassword;
  String? changeNewPassword;
  bool? changeLogoutOtherSessions;
  String? deleteCurrentPassword;

  @override
  Future<bool> hasActiveSession() async => isSignedIn;

  @override
  Future<bool> signIn({required String email, required String password}) async {
    final isValid = email.trim().isNotEmpty && password.trim().isNotEmpty;
    isSignedIn = isValid;
    return isSignedIn;
  }

  @override
  Future<void> signOut() async {
    isSignedIn = false;
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    signUpEmail = email;
    signUpPassword = password;
  }

  @override
  Future<void> signUpAdmin({
    required String email,
    required String password,
  }) async {
    adminSignUpEmail = email;
    adminSignUpPassword = password;
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    passwordResetEmail = email;
  }

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
    required bool logoutOtherSessions,
  }) async {
    resetToken = token;
    resetNewPassword = newPassword;
    resetLogoutOtherSessions = logoutOtherSessions;
  }

  @override
  Future<void> verifyEmail({
    required String token,
    String type = 'signup',
  }) async {
    verifyToken = token;
    verifyType = type;
  }

  @override
  Future<void> resendEmailVerification({required String email}) async {
    resendEmail = email;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required bool logoutOtherSessions,
  }) async {
    changeCurrentPassword = currentPassword;
    changeNewPassword = newPassword;
    changeLogoutOtherSessions = logoutOtherSessions;
  }

  @override
  Future<void> deleteAccount({required String currentPassword}) async {
    deleteCurrentPassword = currentPassword;
    isSignedIn = false;
  }
}

class RecordingProfileRepository implements ProfileRepository {
  UserProfile profile = const UserProfile(
    email: 'demo@boxos.app',
    accountType: AccountType.athlete,
    role: UserRole.athlete,
    availableRoles: [UserRole.athlete],
    displayName: 'Demo Athlete',
    nickname: 'demo',
    notificationPreferences: NotificationPreferences(
      bookingConfirmations: true,
      waitlistPromotions: true,
      paymentIssues: true,
      wodPosted: true,
      prAchievements: true,
      announcementActivity: true,
    ),
    activeGym: null,
    memberships: [],
  );
  String? updatedDisplayName;
  String? updatedNickname;
  NotificationPreferences? updatedNotificationPreferences;
  NotificationInbox inbox = const NotificationInbox(
    unreadCount: 0,
    notifications: [],
  );
  List<RoleManagedUser> managedUsers = const [
    RoleManagedUser(
      id: 1,
      membershipId: 11,
      email: 'demo@boxos.app',
      role: UserRole.admin,
      availableRoles: [UserRole.admin],
      displayName: 'Demo Admin',
      nickname: 'admin',
      canEditRole: false,
    ),
    RoleManagedUser(
      id: 2,
      membershipId: 12,
      email: 'trainer@boxos.app',
      role: UserRole.trainer,
      availableRoles: [UserRole.athlete, UserRole.trainer],
      displayName: 'Demo Trainer',
      nickname: 'trainer',
      canEditRole: true,
    ),
  ];
  RoleManagedUser? updatedManagedUser;
  int? updatedActiveGymId;

  @override
  Future<UserProfile> fetchProfile() async => profile;

  @override
  Future<UserProfile> updateProfile({
    required String displayName,
    required String nickname,
  }) async {
    updatedDisplayName = displayName;
    updatedNickname = nickname;
    profile = UserProfile(
      email: profile.email,
      accountType: profile.accountType,
      role: profile.role,
      availableRoles: profile.availableRoles,
      displayName: displayName,
      nickname: nickname,
      notificationPreferences: profile.notificationPreferences,
      activeGym: profile.activeGym,
      memberships: profile.memberships,
    );
    return profile;
  }

  @override
  Future<UserProfile> uploadProfileAvatar({
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async {
    return profile;
  }

  @override
  Future<UserProfile> deleteProfileAvatar() async {
    return profile;
  }

  @override
  Future<NotificationPreferences> fetchNotificationPreferences() async {
    return profile.notificationPreferences;
  }

  @override
  Future<NotificationPreferences> updateNotificationPreferences({
    required NotificationPreferences preferences,
  }) async {
    updatedNotificationPreferences = preferences;
    profile = UserProfile(
      email: profile.email,
      accountType: profile.accountType,
      role: profile.role,
      availableRoles: profile.availableRoles,
      displayName: profile.displayName,
      nickname: profile.nickname,
      notificationPreferences: preferences,
      activeGym: profile.activeGym,
      memberships: profile.memberships,
    );
    return preferences;
  }

  @override
  Future<NotificationInbox> fetchNotifications() async {
    return inbox;
  }

  @override
  Future<NotificationInbox> markAllNotificationsRead() async {
    inbox = NotificationInbox(
      unreadCount: 0,
      notifications: [
        for (final notification in inbox.notifications)
          AppNotification(
            id: notification.id,
            type: notification.type,
            title: notification.title,
            body: notification.body,
            entityType: notification.entityType,
            entityId: notification.entityId,
            readAt: notification.readAt ?? DateTime.utc(2026, 5, 29, 10),
            createdAt: notification.createdAt,
          ),
      ],
    );
    return inbox;
  }

  @override
  Future<List<RoleManagedUser>> fetchRoleManagedUsers() async {
    return managedUsers;
  }

  @override
  Future<RoleManagedUser> updateUserRole({
    required int userId,
    required List<UserRole> roles,
  }) async {
    final updated = managedUsers.firstWhere((user) => user.id == userId);
    final nextRole = roles.contains(updated.role) ? updated.role : roles.first;
    final next = RoleManagedUser(
      id: updated.id,
      membershipId: updated.membershipId,
      email: updated.email,
      role: nextRole,
      availableRoles: roles,
      displayName: updated.displayName,
      nickname: updated.nickname,
      canEditRole: updated.canEditRole,
    );
    managedUsers = [
      for (final user in managedUsers)
        if (user.id == userId) next else user,
    ];
    updatedManagedUser = next;
    if (profile.email == next.email) {
      profile = UserProfile(
        email: profile.email,
        accountType: profile.accountType,
        role: nextRole,
        availableRoles: roles,
        displayName: profile.displayName,
        nickname: profile.nickname,
        notificationPreferences: profile.notificationPreferences,
        activeGym: profile.activeGym,
        memberships: profile.memberships,
      );
    }
    return next;
  }

  @override
  Future<UserProfile> updateActiveRole({required UserRole role}) async {
    profile = UserProfile(
      email: profile.email,
      accountType: profile.accountType,
      role: role,
      availableRoles: profile.availableRoles,
      displayName: profile.displayName,
      nickname: profile.nickname,
      notificationPreferences: profile.notificationPreferences,
      activeGym: profile.activeGym,
      memberships: profile.memberships,
    );
    return profile;
  }

  @override
  Future<UserProfile> updateActiveGym({required int gymId}) async {
    updatedActiveGymId = gymId;
    final membership = profile.memberships.firstWhere(
      (item) => item.gym.id == gymId,
    );
    profile = UserProfile(
      email: profile.email,
      accountType: profile.accountType,
      role: membership.role,
      availableRoles: membership.availableRoles,
      displayName: profile.displayName,
      nickname: profile.nickname,
      notificationPreferences: profile.notificationPreferences,
      activeGym: membership.gym,
      memberships: profile.memberships,
    );
    return profile;
  }
}

class RecordingGymRepository implements GymRepository {
  int createGymCalls = 0;
  int fetchJoinRequestsCalls = 0;
  List<GymSummary> gyms = const [
    GymSummary(
      id: 1,
      name: 'CrossFit Mitte',
      slug: 'crossfit-mitte',
      logoUrl: 'https://example.com/m.png',
      timezone: 'Europe/Berlin',
    ),
  ];
  int? requestedGymId;
  int? reviewedRequestId;
  bool? lastReviewApproval;
  List<MyGymJoinRequest> myRequests = const [];
  List<GymJoinRequest> requests = const [
    GymJoinRequest(
      id: 1,
      email: 'member@boxos.app',
      displayName: 'Member Athlete',
      nickname: 'member',
      createdAt: '2026-04-13T10:00:00Z',
    ),
  ];

  @override
  Future<GymSummary> createGym({
    required String name,
    required String logoUrl,
    required String timezone,
  }) async {
    createGymCalls += 1;
    final gym = GymSummary(
      id: gyms.length + 1,
      name: name,
      slug: name.toLowerCase().replaceAll(' ', '-'),
      logoUrl: logoUrl,
      timezone: timezone,
    );
    gyms = [...gyms, gym];
    return gym;
  }

  @override
  Future<String> uploadGymLogo({
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async => 'https://example.com/uploaded-logo.png';

  @override
  Future<List<GymJoinRequest>> fetchJoinRequests() async {
    fetchJoinRequestsCalls += 1;
    return requests;
  }

  @override
  Future<List<MyGymJoinRequest>> fetchMyJoinRequests() async => myRequests;

  @override
  Future<List<GymSummary>> listGyms() async => gyms;

  @override
  Future<void> requestJoin({required int gymId}) async {
    requestedGymId = gymId;
    final gym = gyms.firstWhere((item) => item.id == gymId);
    myRequests = [
      MyGymJoinRequest(
        id: myRequests.length + 1,
        status: 'pending',
        createdAt: '2026-04-13T10:00:00Z',
        reviewedAt: null,
        gym: gym,
      ),
      ...myRequests,
    ];
  }

  @override
  Future<void> reviewJoinRequest({
    required int requestId,
    required bool approve,
  }) async {
    reviewedRequestId = requestId;
    lastReviewApproval = approve;
    requests = requests.where((request) => request.id != requestId).toList();
  }
}

class RecordingScheduleRepository implements ScheduleRepository {
  List<ScheduleTrainer> trainers = const [
    ScheduleTrainer(id: 2, displayName: 'Demo Trainer', nickname: 'trainer'),
  ];
  List<ScheduleClass> classes = [
    ScheduleClass(
      id: 1,
      gymId: 1,
      title: 'Evening WOD',
      classType: 'WOD',
      startTime: DateTime.now().add(const Duration(hours: 2)),
      durationMinutes: 60,
      capacity: 12,
      assignedTrainer: ScheduleTrainer(
        id: 2,
        displayName: 'Demo Trainer',
        nickname: 'trainer',
      ),
      wodDescription: '18.1',
      bookedCount: 3,
      remainingSpots: 9,
      waitlistCount: 0,
      isBooked: false,
      isWaitlisted: false,
      attendanceStatus: null,
      bookings: const [],
    ),
  ];
  ScheduleClass? lastCreatedClass;
  String? lastRecurrenceFrequency;
  int? lastOccurrenceCount;
  ScheduleClass? lastUpdatedClass;
  int? lastDeletedClassId;
  int? lastBookedClassId;
  int? lastCancelledClassId;
  int? lastWaitlistedClassId;
  int? lastLeftWaitlistClassId;
  int? lastAttendanceClassId;
  int? lastAttendanceUserId;
  String? lastAttendanceStatus;

  @override
  Future<ScheduleClass> createClass({
    required String title,
    required String classType,
    required DateTime startTime,
    required int durationMinutes,
    required int capacity,
    required int trainerUserId,
    required String wodDescription,
    List<ScheduleSection> sections = const [],
    String recurrenceFrequency = 'none',
    int occurrenceCount = 1,
  }) async {
    final trainer = trainers.firstWhere((item) => item.id == trainerUserId);
    final created = ScheduleClass(
      id: classes.length + 1,
      gymId: 1,
      title: title,
      classType: classType,
      startTime: startTime,
      durationMinutes: durationMinutes,
      capacity: capacity,
      assignedTrainer: trainer,
      wodDescription: wodDescription,
      bookedCount: 0,
      remainingSpots: capacity,
      waitlistCount: 0,
      isBooked: false,
      isWaitlisted: false,
      attendanceStatus: null,
      bookings: const [],
    );
    classes = [...classes, created];
    lastCreatedClass = created;
    lastRecurrenceFrequency = recurrenceFrequency;
    lastOccurrenceCount = occurrenceCount;
    return created;
  }

  @override
  Future<void> deleteClass({required int id}) async {
    lastDeletedClassId = id;
    classes = classes.where((item) => item.id != id).toList();
  }

  @override
  Future<List<ScheduleTrainer>> fetchTrainers() async => trainers;

  @override
  Future<void> bookClass({required int classId}) async {
    lastBookedClassId = classId;
    classes = [
      for (final item in classes)
        if (item.id == classId)
          ScheduleClass(
            id: item.id,
            gymId: item.gymId,
            title: item.title,
            classType: item.classType,
            startTime: item.startTime,
            durationMinutes: item.durationMinutes,
            capacity: item.capacity,
            assignedTrainer: item.assignedTrainer,
            wodDescription: item.wodDescription,
            bookedCount: item.bookedCount + 1,
            remainingSpots: item.remainingSpots - 1,
            waitlistCount: item.waitlistCount,
            isBooked: true,
            isWaitlisted: false,
          )
        else
          item,
    ];
  }

  @override
  Future<void> cancelBooking({required int classId}) async {
    lastCancelledClassId = classId;
    classes = [
      for (final item in classes)
        if (item.id == classId)
          ScheduleClass(
            id: item.id,
            gymId: item.gymId,
            title: item.title,
            classType: item.classType,
            startTime: item.startTime,
            durationMinutes: item.durationMinutes,
            capacity: item.capacity,
            assignedTrainer: item.assignedTrainer,
            wodDescription: item.wodDescription,
            bookedCount: item.bookedCount - 1,
            remainingSpots: item.remainingSpots + 1,
            waitlistCount: item.waitlistCount,
            isBooked: false,
            isWaitlisted: false,
          )
        else
          item,
    ];
  }

  @override
  Future<void> joinWaitlist({required int classId}) async {
    lastWaitlistedClassId = classId;
    classes = [
      for (final item in classes)
        if (item.id == classId)
          ScheduleClass(
            id: item.id,
            gymId: item.gymId,
            title: item.title,
            classType: item.classType,
            startTime: item.startTime,
            durationMinutes: item.durationMinutes,
            capacity: item.capacity,
            assignedTrainer: item.assignedTrainer,
            wodDescription: item.wodDescription,
            bookedCount: item.bookedCount,
            remainingSpots: item.remainingSpots,
            waitlistCount: item.waitlistCount + 1,
            isBooked: false,
            isWaitlisted: true,
            attendanceStatus: item.attendanceStatus,
            bookings: item.bookings,
          )
        else
          item,
    ];
  }

  @override
  Future<void> leaveWaitlist({required int classId}) async {
    lastLeftWaitlistClassId = classId;
    classes = [
      for (final item in classes)
        if (item.id == classId)
          ScheduleClass(
            id: item.id,
            gymId: item.gymId,
            title: item.title,
            classType: item.classType,
            startTime: item.startTime,
            durationMinutes: item.durationMinutes,
            capacity: item.capacity,
            assignedTrainer: item.assignedTrainer,
            wodDescription: item.wodDescription,
            bookedCount: item.bookedCount,
            remainingSpots: item.remainingSpots,
            waitlistCount: item.waitlistCount > 0 ? item.waitlistCount - 1 : 0,
            isBooked: false,
            isWaitlisted: false,
            attendanceStatus: item.attendanceStatus,
            bookings: item.bookings,
          )
        else
          item,
    ];
  }

  @override
  Future<ScheduleClass> updateAttendance({
    required int classId,
    required int userId,
    required String attendanceStatus,
  }) async {
    lastAttendanceClassId = classId;
    lastAttendanceUserId = userId;
    lastAttendanceStatus = attendanceStatus;
    late final ScheduleClass updated;
    classes = [
      for (final item in classes)
        if (item.id == classId)
          updated = ScheduleClass(
            id: item.id,
            gymId: item.gymId,
            title: item.title,
            classType: item.classType,
            startTime: item.startTime,
            durationMinutes: item.durationMinutes,
            capacity: item.capacity,
            assignedTrainer: item.assignedTrainer,
            wodDescription: item.wodDescription,
            bookedCount: item.bookedCount,
            remainingSpots: item.remainingSpots,
            waitlistCount: item.waitlistCount,
            isBooked: item.isBooked,
            isWaitlisted: item.isWaitlisted,
            attendanceStatus: item.attendanceStatus,
            bookings: [
              for (final booking in item.bookings)
                if (booking.userId == userId)
                  ScheduleBooking(
                    userId: booking.userId,
                    displayName: booking.displayName,
                    nickname: booking.nickname,
                    attendanceStatus: attendanceStatus,
                    isCurrentUser: booking.isCurrentUser,
                  )
                else
                  booking,
            ],
          )
        else
          item,
    ];
    return updated;
  }

  @override
  Future<List<ScheduleClass>> fetchSchedule() async => classes;

  @override
  Future<ScheduleClass> updateClass({
    required int id,
    required String title,
    required String classType,
    required DateTime startTime,
    required int durationMinutes,
    required int capacity,
    required int trainerUserId,
    required String wodDescription,
    List<ScheduleSection> sections = const [],
  }) async {
    final trainer = trainers.firstWhere((item) => item.id == trainerUserId);
    final updated = ScheduleClass(
      id: id,
      gymId: 1,
      title: title,
      classType: classType,
      startTime: startTime,
      durationMinutes: durationMinutes,
      capacity: capacity,
      assignedTrainer: trainer,
      wodDescription: wodDescription,
      bookedCount: 0,
      remainingSpots: capacity,
      waitlistCount: 0,
      isBooked: false,
      isWaitlisted: false,
      attendanceStatus: null,
      bookings: const [],
    );
    classes = [
      for (final item in classes)
        if (item.id == id) updated else item,
    ];
    lastUpdatedClass = updated;
    return updated;
  }
}

class RecordingAnnouncementRepository implements AnnouncementRepository {
  List<Announcement> announcements = const [];
  Announcement? lastCreatedAnnouncement;
  Announcement? lastUpdatedAnnouncement;
  int? lastDeletedAnnouncementId;
  int? lastLikedAnnouncementId;
  int? lastUnlikedAnnouncementId;
  AnnouncementComment? lastCreatedComment;
  AnnouncementComment? lastUpdatedComment;
  int? lastDeletedCommentId;
  String uploadedImageUrl = 'https://example.com/uploaded-announcement.png';

  @override
  Future<String> uploadAnnouncementImage({
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async => uploadedImageUrl;

  @override
  Future<Announcement> createAnnouncement({
    required String title,
    required String description,
    String? imageUrl,
  }) async {
    final created = Announcement(
      id: announcements.length + 1,
      gymId: 1,
      title: title,
      description: description,
      imageUrl: imageUrl,
      authorName: 'Demo Coach',
      createdAt: DateTime.utc(2026, 5, 29, 7),
      updatedAt: DateTime.utc(2026, 5, 29, 7),
      likeCount: 0,
      likedByMe: false,
      commentCount: 0,
      comments: const [],
      canManage: true,
    );
    announcements = [created, ...announcements];
    lastCreatedAnnouncement = created;
    return created;
  }

  @override
  Future<Announcement> updateAnnouncement({
    required int id,
    required String title,
    required String description,
    String? imageUrl,
  }) async {
    final existing = announcements.firstWhere((item) => item.id == id);
    final updated = Announcement(
      id: existing.id,
      gymId: existing.gymId,
      title: title,
      description: description,
      imageUrl: imageUrl,
      authorName: existing.authorName,
      createdAt: existing.createdAt,
      updatedAt: DateTime.utc(2026, 5, 29, 8),
      likeCount: existing.likeCount,
      likedByMe: existing.likedByMe,
      commentCount: existing.commentCount,
      comments: existing.comments,
      canManage: existing.canManage,
    );
    announcements = [
      for (final item in announcements) if (item.id == id) updated else item,
    ];
    lastUpdatedAnnouncement = updated;
    return updated;
  }

  @override
  Future<void> deleteAnnouncement({required int id}) async {
    announcements = announcements.where((item) => item.id != id).toList();
    lastDeletedAnnouncementId = id;
  }

  @override
  Future<Announcement> likeAnnouncement({required int announcementId}) async {
    lastLikedAnnouncementId = announcementId;
    final updated = announcements.firstWhere((item) => item.id == announcementId);
    final next = Announcement(
      id: updated.id,
      gymId: updated.gymId,
      title: updated.title,
      description: updated.description,
      imageUrl: updated.imageUrl,
      authorName: updated.authorName,
      createdAt: updated.createdAt,
      updatedAt: updated.updatedAt,
      likeCount: updated.likeCount + 1,
      likedByMe: true,
      commentCount: updated.commentCount,
      comments: updated.comments,
      canManage: updated.canManage,
    );
    announcements = [for (final item in announcements) if (item.id == announcementId) next else item];
    return next;
  }

  @override
  Future<Announcement> unlikeAnnouncement({required int announcementId}) async {
    lastUnlikedAnnouncementId = announcementId;
    final updated = announcements.firstWhere((item) => item.id == announcementId);
    final next = Announcement(
      id: updated.id,
      gymId: updated.gymId,
      title: updated.title,
      description: updated.description,
      imageUrl: updated.imageUrl,
      authorName: updated.authorName,
      createdAt: updated.createdAt,
      updatedAt: updated.updatedAt,
      likeCount: updated.likeCount > 0 ? updated.likeCount - 1 : 0,
      likedByMe: false,
      commentCount: updated.commentCount,
      comments: updated.comments,
      canManage: updated.canManage,
    );
    announcements = [for (final item in announcements) if (item.id == announcementId) next else item];
    return next;
  }

  @override
  Future<AnnouncementComment> createComment({
    required int announcementId,
    required String body,
  }) async {
    final existing = announcements.firstWhere((item) => item.id == announcementId);
    final comment = AnnouncementComment(
      id: existing.comments.length + 1,
      announcementId: announcementId,
      authorName: 'Demo Coach',
      body: body,
      createdAt: DateTime.utc(2026, 5, 29, 8, 30),
      updatedAt: DateTime.utc(2026, 5, 29, 8, 30),
      canManage: true,
    );
    final updated = Announcement(
      id: existing.id,
      gymId: existing.gymId,
      title: existing.title,
      description: existing.description,
      imageUrl: existing.imageUrl,
      authorName: existing.authorName,
      createdAt: existing.createdAt,
      updatedAt: existing.updatedAt,
      likeCount: existing.likeCount,
      likedByMe: existing.likedByMe,
      commentCount: existing.commentCount + 1,
      comments: [...existing.comments, comment],
      canManage: existing.canManage,
    );
    announcements = [for (final item in announcements) if (item.id == announcementId) updated else item];
    lastCreatedComment = comment;
    return comment;
  }

  @override
  Future<AnnouncementComment> updateComment({
    required int commentId,
    required String body,
  }) async {
    late AnnouncementComment updatedComment;
    announcements = [
      for (final announcement in announcements)
        if (announcement.comments.any((comment) => comment.id == commentId))
          Announcement(
            id: announcement.id,
            gymId: announcement.gymId,
            title: announcement.title,
            description: announcement.description,
            imageUrl: announcement.imageUrl,
            authorName: announcement.authorName,
            createdAt: announcement.createdAt,
            updatedAt: announcement.updatedAt,
            likeCount: announcement.likeCount,
            likedByMe: announcement.likedByMe,
            commentCount: announcement.commentCount,
            comments: [
              for (final comment in announcement.comments)
                if (comment.id == commentId)
                  updatedComment = AnnouncementComment(
                    id: comment.id,
                    announcementId: comment.announcementId,
                    authorName: comment.authorName,
                    body: body,
                    createdAt: comment.createdAt,
                    updatedAt: DateTime.utc(2026, 5, 29, 9),
                    canManage: comment.canManage,
                  )
                else
                  comment,
            ],
            canManage: announcement.canManage,
          )
        else
          announcement,
    ];
    lastUpdatedComment = updatedComment;
    return updatedComment;
  }

  @override
  Future<void> deleteComment({required int commentId}) async {
    announcements = [
      for (final announcement in announcements)
        if (announcement.comments.any((comment) => comment.id == commentId))
          Announcement(
            id: announcement.id,
            gymId: announcement.gymId,
            title: announcement.title,
            description: announcement.description,
            imageUrl: announcement.imageUrl,
            authorName: announcement.authorName,
            createdAt: announcement.createdAt,
            updatedAt: announcement.updatedAt,
            likeCount: announcement.likeCount,
            likedByMe: announcement.likedByMe,
            commentCount: announcement.commentCount - 1,
            comments: [for (final comment in announcement.comments) if (comment.id != commentId) comment],
            canManage: announcement.canManage,
          )
        else
          announcement,
    ];
    lastDeletedCommentId = commentId;
  }

  @override
  Future<List<Announcement>> fetchAnnouncements() async => announcements;
}

Future<void> _configureTestViewport(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _settleApp(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _waitForAuthBootstrap(
  WidgetTester tester,
  ProviderContainer container,
) async {
  for (var i = 0; i < 20; i++) {
    final authState = container.read(authControllerProvider);
    if (authState.hasValue || authState.hasError) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<GoRouter> _pumpAuthenticatedRouter(
  WidgetTester tester,
  RecordingAuthRepository repository,
  RecordingProfileRepository profileRepository, {
  String initialLocation = '/home',
  RecordingGymRepository? gymRepository,
  RecordingScheduleRepository? scheduleRepository,
  RecordingAnnouncementRepository? announcementRepository,
}) async {
  await _configureTestViewport(tester);

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWith((ref) => repository),
      profileRepositoryProvider.overrideWith((ref) => profileRepository),
      gymRepositoryProvider.overrideWith(
        (ref) => gymRepository ?? RecordingGymRepository(),
      ),
      scheduleRepositoryProvider.overrideWith(
        (ref) => scheduleRepository ?? RecordingScheduleRepository(),
      ),
      announcementRepositoryProvider.overrideWith(
        (ref) => announcementRepository ?? RecordingAnnouncementRepository(),
      ),
    ],
  );

  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/my-box',
        builder: (context, state) => const MyBoxScreen(),
      ),
      GoRoute(path: '/calendar', redirect: (context, state) => '/my-box'),
      GoRoute(
        path: '/change-password',
        builder: (context, state) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: '/delete-account',
        builder: (context, state) => const DeleteAccountScreen(),
      ),
      GoRoute(
        path: '/edit-profile',
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: '/notification-settings',
        builder: (context, state) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/role-management',
        builder: (context, state) => const RoleManagementScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Sign In'))),
      ),
      GoRoute(
        path: '/gyms',
        builder: (context, state) => const GymDirectoryScreen(),
      ),
      GoRoute(
        path: '/gym-requests',
        builder: (context, state) => const JoinRequestsScreen(),
      ),
      GoRoute(
        path: '/create-gym',
        builder: (context, state) => const CreateGymScreen(),
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await _settleApp(tester);

  return router;
}

Future<ProviderContainer> _pumpAppWithRepository(
  WidgetTester tester,
  RecordingAuthRepository repository,
) async {
  return _pumpAppWithRepositories(
    tester,
    repository,
    RecordingProfileRepository(),
    RecordingGymRepository(),
    RecordingAnnouncementRepository(),
  );
}

Future<ProviderContainer> _pumpAppWithRepositories(
  WidgetTester tester,
  RecordingAuthRepository repository,
  RecordingProfileRepository profileRepository,
  RecordingGymRepository gymRepository,
  RecordingAnnouncementRepository announcementRepository,
) async {
  await _configureTestViewport(tester);

  final effectiveProfileRepository = profileRepository;
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWith((ref) => repository),
      profileRepositoryProvider.overrideWith(
        (ref) => effectiveProfileRepository,
      ),
      gymRepositoryProvider.overrideWith((ref) => gymRepository),
      announcementRepositoryProvider.overrideWith((ref) => announcementRepository),
    ],
  );

  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const BoxOsApp()),
  );
  await _waitForAuthBootstrap(tester, container);
  await _settleApp(tester);

  return container;
}

void main() {
  testWidgets('Invalid login input shows validation errors', (
    WidgetTester tester,
  ) async {
    await _pumpAppWithRepository(tester, RecordingAuthRepository());

    final signInButton = find.widgetWithText(FilledButton, 'Sign In');
    await tester.ensureVisible(signInButton);
    await tester.tap(signInButton);
    await tester.pump();

    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
    expect(find.text('BoxOS Home'), findsNothing);
  });

  testWidgets('Valid login submits credentials', (WidgetTester tester) async {
    final repository = RecordingAuthRepository();
    await _pumpAppWithRepository(tester, repository);

    await tester.enterText(find.byType(TextFormField).at(0), 'demo@boxos.app');
    await tester.enterText(find.byType(TextFormField).at(1), 'demopw');

    final signInButton = find.widgetWithText(FilledButton, 'Sign In');
    await tester.ensureVisible(signInButton);
    await tester.tap(signInButton);
    await _settleApp(tester);

    expect(repository.isSignedIn, isTrue);
  });

  testWidgets('Login shows brand hero and create box entry point', (
    WidgetTester tester,
  ) async {
    final container = await _pumpAppWithRepository(
      tester,
      RecordingAuthRepository(),
    );
    final router = container.read(appRouterProvider);

    expect(find.text('BoxOS'), findsOneWidget);
    expect(find.text('Access'), findsNothing);
    expect(
      find.widgetWithText(TextButton, 'I need admin access'),
      findsNothing,
    );

    final createBoxButton = find.widgetWithText(OutlinedButton, 'Create Box');
    expect(createBoxButton, findsOneWidget);
    await tester.ensureVisible(createBoxButton);
    await tester.tap(createBoxButton);
    await _settleApp(tester);

    expect(router.state.matchedLocation, '/admin-sign-up');
    expect(find.text('Create Admin Account'), findsWidgets);
  });

  testWidgets('Sign up flow calls API and routes to verify email', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository();
    final container = await _pumpAppWithRepository(tester, repository);
    final router = container.read(appRouterProvider);

    router.go('/sign-up');
    await _settleApp(tester);

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'new-athlete@boxos.app',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
    await tester.enterText(find.byType(TextFormField).at(2), 'secret123');

    final submitButton = find.widgetWithText(FilledButton, 'Create Account');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await _settleApp(tester);

    expect(repository.signUpEmail, 'new-athlete@boxos.app');
    expect(repository.signUpPassword, 'secret123');
    expect(
      find.widgetWithText(OutlinedButton, 'Resend Verification Email'),
      findsOneWidget,
    );
  });

  testWidgets('Admin sign up flow uses distinct onboarding path', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository();
    final container = await _pumpAppWithRepository(tester, repository);
    final router = container.read(appRouterProvider);

    router.go('/admin-sign-up');
    await _settleApp(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'admin@boxos.app');
    await tester.enterText(find.byType(TextFormField).at(1), 'adminpass123');
    await tester.enterText(find.byType(TextFormField).at(2), 'adminpass123');
    final createAdminButton = find.widgetWithText(
      FilledButton,
      'Create Admin Account',
    );
    await tester.ensureVisible(createAdminButton);
    await _settleApp(tester);
    await tester.tap(createAdminButton);
    await _settleApp(tester);

    expect(repository.adminSignUpEmail, 'admin@boxos.app');
    expect(repository.adminSignUpPassword, 'adminpass123');
    expect(find.text('Verification Token'), findsWidgets);
  });

  testWidgets('Verify email flow returns to login after verification', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository();
    final container = await _pumpAppWithRepository(tester, repository);
    final router = container.read(appRouterProvider);

    router.go('/verify-email?email=member%40boxos.app');
    await _settleApp(tester);

    await tester.enterText(find.byType(TextField).at(0), 'verify-token-123');
    await tester.tap(find.widgetWithText(FilledButton, 'Verify Email'));
    await _settleApp(tester);

    expect(find.text('Sign In'), findsWidgets);

    expect(repository.verifyToken, 'verify-token-123');
    expect(repository.verifyType, 'signup');
  });

  testWidgets('Verify email flow can resend verification email', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository();
    final container = await _pumpAppWithRepository(tester, repository);
    final router = container.read(appRouterProvider);

    router.go('/verify-email?email=member%40boxos.app');
    await _settleApp(tester);

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Resend Verification Email'),
    );
    await _settleApp(tester);

    expect(repository.resendEmail, 'member@boxos.app');
  });

  testWidgets('Auth callback verifies signup links automatically', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository();
    final container = await _pumpAppWithRepository(tester, repository);
    final router = container.read(appRouterProvider);

    router.go('/auth/callback?type=signup&token_hash=verify-token-abc');
    await _settleApp(tester);

    expect(repository.verifyToken, 'verify-token-abc');
    expect(repository.verifyType, 'signup');
    expect(find.text('Email verified. You can now sign in.'), findsOneWidget);
  });

  testWidgets('Auth callback routes recovery links to reset password', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository();
    final container = await _pumpAppWithRepository(tester, repository);
    final router = container.read(appRouterProvider);

    router.go('/auth/callback?type=recovery&token_hash=reset-token-callback');
    await _settleApp(tester);

    expect(find.text('Reset Password'), findsWidgets);

    await tester.enterText(find.byType(TextFormField).at(1), 'newpassword123');
    await tester.enterText(find.byType(TextFormField).at(2), 'newpassword123');
    await tester.tap(find.byType(Switch));
    await _settleApp(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Update Password'));
    await _settleApp(tester);

    expect(repository.resetToken, 'reset-token-callback');
    expect(repository.resetNewPassword, 'newpassword123');
    expect(repository.resetLogoutOtherSessions, isFalse);
  });

  testWidgets('Forgot password flow submits reset request', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository();
    final container = await _pumpAppWithRepository(tester, repository);
    final router = container.read(appRouterProvider);

    router.go('/forgot-password');
    await _settleApp(tester);

    await tester.enterText(
      find.byType(TextFormField).first,
      'athlete@boxos.app',
    );
    final sendLinkButton = find.widgetWithText(FilledButton, 'Send Reset Link');
    await tester.ensureVisible(sendLinkButton);
    await tester.tap(sendLinkButton);
    await _settleApp(tester);

    expect(repository.passwordResetEmail, 'athlete@boxos.app');
  });

  testWidgets('Reset password flow uses token and returns to login', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository();
    final container = await _pumpAppWithRepository(tester, repository);
    final router = container.read(appRouterProvider);

    router.go('/reset-password?token=reset-token-abc');
    await _settleApp(tester);

    expect(find.text('Reset Password'), findsWidgets);
    await tester.enterText(find.byType(TextFormField).at(1), 'newpassword123');
    await tester.enterText(find.byType(TextFormField).at(2), 'newpassword123');
    final updatePasswordButton = find.widgetWithText(
      FilledButton,
      'Update Password',
    );
    await tester.ensureVisible(updatePasswordButton);
    await _settleApp(tester);
    await tester.tap(updatePasswordButton);
    await _settleApp(tester);

    expect(repository.resetToken, 'reset-token-abc');
    expect(repository.resetNewPassword, 'newpassword123');
    expect(repository.resetLogoutOtherSessions, isTrue);
    expect(find.text('Sign In'), findsWidgets);
  });

  testWidgets('Change password flow submits form and returns home', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    await _pumpAuthenticatedRouter(
      tester,
      repository,
      RecordingProfileRepository(),
      initialLocation: '/change-password',
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'oldpassword');
    await tester.enterText(find.byType(TextFormField).at(1), 'newpassword123');
    await tester.enterText(find.byType(TextFormField).at(2), 'newpassword123');
    await tester.tap(find.byType(Switch));
    await _settleApp(tester);
    final updatePasswordButton = find.widgetWithText(
      FilledButton,
      'Update Password',
    );
    await tester.ensureVisible(updatePasswordButton);
    await _settleApp(tester);
    await tester.tap(updatePasswordButton);
    await _settleApp(tester);

    expect(repository.changeCurrentPassword, 'oldpassword');
    expect(repository.changeNewPassword, 'newpassword123');
    expect(repository.changeLogoutOtherSessions, isTrue);
    expect(find.text('News'), findsOneWidget);
  });

  testWidgets('Delete account flow opens confirmation dialog', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    await _pumpAuthenticatedRouter(
      tester,
      repository,
      RecordingProfileRepository(),
      initialLocation: '/delete-account',
    );

    await tester.enterText(find.byType(TextFormField).first, 'currentpassword');
    final deleteAccountButton = find.widgetWithText(
      FilledButton,
      'Delete Account',
    );
    await tester.ensureVisible(deleteAccountButton);
    await _settleApp(tester);
    await tester.tap(deleteAccountButton);
    await _settleApp(tester);

    expect(find.text('Delete Account?'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Delete'), findsOneWidget);
  });

  testWidgets('Edit profile flow updates profile and returns home', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final profileRepository = RecordingProfileRepository();
    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
      initialLocation: '/edit-profile',
    );

    await tester.enterText(find.byType(TextFormField).at(1), 'Basti Athlete');
    await tester.enterText(find.byType(TextFormField).at(2), 'basti');
    final saveProfileButton = find.widgetWithText(FilledButton, 'Save Profile');
    await tester.ensureVisible(saveProfileButton);
    await _settleApp(tester);
    await tester.tap(saveProfileButton);
    await _settleApp(tester);

    expect(profileRepository.updatedDisplayName, 'Basti Athlete');
    expect(profileRepository.updatedNickname, 'basti');
    expect(find.text('News'), findsOneWidget);
  });

  testWidgets('Home screen uses stacked full-width sections', (
    WidgetTester tester,
  ) async {
    final profileRepository = RecordingProfileRepository()
      ..profile = const UserProfile(
        email: 'demo@boxos.app',
        accountType: AccountType.athlete,
        role: UserRole.athlete,
        availableRoles: [UserRole.athlete],
        displayName: 'Demo Athlete',
        nickname: 'demo',
        notificationPreferences: NotificationPreferences(
          bookingConfirmations: true,
          waitlistPromotions: true,
          paymentIssues: true,
          wodPosted: true,
          prAchievements: true,
          announcementActivity: true,
        ),
        activeGym: GymSummary(
          id: 1,
          name: 'CrossFit Mitte',
          slug: 'crossfit-mitte',
          logoUrl: 'https://example.com/m.png',
          timezone: 'Europe/Berlin',
        ),
        memberships: [
          GymMembership(
            gym: GymSummary(
              id: 1,
              name: 'CrossFit Mitte',
              slug: 'crossfit-mitte',
              logoUrl: 'https://example.com/m.png',
              timezone: 'Europe/Berlin',
            ),
            role: UserRole.athlete,
            availableRoles: [UserRole.athlete],
            status: 'active',
          ),
        ],
      );
    final announcementRepository = RecordingAnnouncementRepository()
      ..announcements = [
        Announcement(
          id: 1,
          gymId: 1,
          title: 'Murph briefing',
          description: 'Heat assignments go live tonight.',
          imageUrl: null,
          authorName: 'Demo Coach',
          createdAt: DateTime.utc(2026, 5, 29, 7),
          updatedAt: DateTime.utc(2026, 5, 29, 7),
          likeCount: 0,
          likedByMe: false,
          commentCount: 0,
          comments: const [],
          canManage: false,
        ),
      ];
    final scheduleRepository = RecordingScheduleRepository();
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) => profileRepository),
        announcementRepositoryProvider.overrideWith(
          (ref) => announcementRepository,
        ),
        scheduleRepositoryProvider.overrideWith((ref) => scheduleRepository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: HomeScreen())),
      ),
    );
    await _settleApp(tester);

    expect(find.text('Today at a glance'), findsNothing);
    expect(find.text('Class access'), findsOneWidget);
    expect(find.text('Book a class'), findsOneWidget);
    final bookingSectionTop = tester.getTopLeft(find.text('Class access')).dy;
    await tester.drag(find.byType(ListView).first, const Offset(0, -350));
    await _settleApp(tester);
    expect(find.text('Murph briefing'), findsOneWidget);
    final todayTop = tester.getTopLeft(find.text('Murph briefing')).dy;
    expect(bookingSectionTop, lessThan(todayTop));

    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await _settleApp(tester);
  });

  testWidgets('Coach can create and expand announcements on home', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final profileRepository = RecordingProfileRepository()
      ..profile = const UserProfile(
        email: 'trainer@boxos.app',
        accountType: AccountType.athlete,
        role: UserRole.trainer,
        availableRoles: [UserRole.athlete, UserRole.trainer],
        displayName: 'Demo Trainer',
        nickname: 'trainer',
        notificationPreferences: NotificationPreferences(
          bookingConfirmations: true,
          waitlistPromotions: true,
          paymentIssues: true,
          wodPosted: true,
          prAchievements: true,
          announcementActivity: true,
        ),
        activeGym: GymSummary(
          id: 1,
          name: 'CrossFit Mitte',
          slug: 'crossfit-mitte',
          logoUrl: 'https://example.com/m.png',
          timezone: 'Europe/Berlin',
        ),
        memberships: [
          GymMembership(
            gym: GymSummary(
              id: 1,
              name: 'CrossFit Mitte',
              slug: 'crossfit-mitte',
              logoUrl: 'https://example.com/m.png',
              timezone: 'Europe/Berlin',
            ),
            role: UserRole.trainer,
            availableRoles: [UserRole.athlete, UserRole.trainer],
            status: 'active',
          ),
        ],
      );
    final announcementRepository = RecordingAnnouncementRepository()
      ..announcements = [
        Announcement(
          id: 1,
          gymId: 1,
          title: 'Open Gym shift',
          description: 'Open Gym starts 30 minutes later this Friday.',
          imageUrl: null,
          authorName: 'Demo Coach',
          createdAt: DateTime.utc(2026, 5, 29, 7),
          updatedAt: DateTime.utc(2026, 5, 29, 7),
          likeCount: 0,
          likedByMe: false,
          commentCount: 0,
          comments: const [],
          canManage: true,
        ),
      ];

    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
      initialLocation: '/home',
      announcementRepository: announcementRepository,
    );

    expect(find.text('Post a new announcement'), findsOneWidget);
    expect(find.textContaining('Posted by Demo Coach'), findsOneWidget);
    await tester.tap(find.text('Open Gym shift'));
    await _settleApp(tester);
    expect(
      find.text('Open Gym starts 30 minutes later this Friday.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Post a new announcement'));
    await _settleApp(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Saturday heat list',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description'),
      'Heat assignments are now live at the front desk.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Post Announcement'));
    await _settleApp(tester);

    expect(announcementRepository.lastCreatedAnnouncement, isNotNull);
    expect(
      announcementRepository.lastCreatedAnnouncement!.title,
      'Saturday heat list',
    );
    expect(find.text('Saturday heat list'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await _settleApp(tester);
    await tester.tap(find.text('Edit announcement'));
    await _settleApp(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Saturday heat list updated',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description'),
      'Updated heat assignments are now live.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save Changes'));
    await _settleApp(tester);

    expect(announcementRepository.lastUpdatedAnnouncement, isNotNull);
    expect(
      announcementRepository.lastUpdatedAnnouncement!.title,
      'Saturday heat list updated',
    );
    expect(find.text('Saturday heat list updated'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await _settleApp(tester);
    await tester.tap(find.text('Delete announcement'));
    await _settleApp(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await _settleApp(tester);

    expect(announcementRepository.lastDeletedAnnouncementId, isNotNull);
  });

  testWidgets('Home announcements support likes and comments', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final profileRepository = RecordingProfileRepository()
      ..profile = const UserProfile(
        email: 'athlete@boxos.app',
        accountType: AccountType.athlete,
        role: UserRole.athlete,
        availableRoles: [UserRole.athlete],
        displayName: 'Demo Athlete',
        nickname: 'athlete',
        notificationPreferences: NotificationPreferences(
          bookingConfirmations: true,
          waitlistPromotions: true,
          paymentIssues: true,
          wodPosted: true,
          prAchievements: true,
          announcementActivity: true,
        ),
        activeGym: GymSummary(
          id: 1,
          name: 'CrossFit Mitte',
          slug: 'crossfit-mitte',
          logoUrl: 'https://example.com/m.png',
          timezone: 'Europe/Berlin',
        ),
        memberships: [
          GymMembership(
            gym: GymSummary(
              id: 1,
              name: 'CrossFit Mitte',
              slug: 'crossfit-mitte',
              logoUrl: 'https://example.com/m.png',
              timezone: 'Europe/Berlin',
            ),
            role: UserRole.athlete,
            availableRoles: [UserRole.athlete],
            status: 'active',
          ),
        ],
      );
    final announcementRepository = RecordingAnnouncementRepository()
      ..announcements = [
        Announcement(
          id: 1,
          gymId: 1,
          title: 'Friday throwdown',
          description: 'Comment with your scaling plan before the heat list drops.',
          imageUrl: null,
          authorName: 'Demo Coach',
          createdAt: DateTime.utc(2026, 5, 29, 7),
          updatedAt: DateTime.utc(2026, 5, 29, 7),
          likeCount: 0,
          likedByMe: false,
          commentCount: 0,
          comments: const [],
          canManage: false,
        ),
      ];

    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
      initialLocation: '/home',
      announcementRepository: announcementRepository,
    );

    await tester.tap(find.text('Friday throwdown'));
    await _settleApp(tester);

    await tester.tap(find.text('0 likes'));
    await _settleApp(tester);
    expect(announcementRepository.lastLikedAnnouncementId, 1);

    await tester.tap(find.text('Friday throwdown'));
    await _settleApp(tester);
    await tester.enterText(find.byType(TextField).first, 'I will scale volume but keep the pace.');
    await tester.tap(find.widgetWithText(FilledButton, 'Post'));
    await _settleApp(tester);

    expect(announcementRepository.lastCreatedComment, isNotNull);
    await tester.tap(find.text('Friday throwdown'));
    await _settleApp(tester);
    expect(find.text('I will scale volume but keep the pace.'), findsOneWidget);
    expect(announcementRepository.announcements.first.commentCount, 1);
  });

  testWidgets('Home booking quick access shows placeholder without bookings', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final profileRepository = RecordingProfileRepository()
      ..profile = const UserProfile(
        email: 'athlete@boxos.app',
        accountType: AccountType.athlete,
        role: UserRole.athlete,
        availableRoles: [UserRole.athlete],
        displayName: 'Demo Athlete',
        nickname: 'athlete',
        notificationPreferences: NotificationPreferences(
          bookingConfirmations: true,
          waitlistPromotions: true,
          paymentIssues: true,
          wodPosted: true,
          prAchievements: true,
          announcementActivity: true,
        ),
        activeGym: GymSummary(
          id: 1,
          name: 'CrossFit Mitte',
          slug: 'crossfit-mitte',
          logoUrl: 'https://example.com/m.png',
          timezone: 'Europe/Berlin',
        ),
        memberships: [
          GymMembership(
            gym: GymSummary(
              id: 1,
              name: 'CrossFit Mitte',
              slug: 'crossfit-mitte',
              logoUrl: 'https://example.com/m.png',
              timezone: 'Europe/Berlin',
            ),
            role: UserRole.athlete,
            availableRoles: [UserRole.athlete],
            status: 'active',
          ),
        ],
      );
    final scheduleRepository = RecordingScheduleRepository()
      ..classes = [
        ScheduleClass(
          id: 1,
          gymId: 1,
          title: 'Morning WOD',
          classType: 'WOD',
          startTime: DateTime.now().add(const Duration(hours: 3)),
          durationMinutes: 60,
          capacity: 12,
          assignedTrainer: const ScheduleTrainer(
            id: 2,
            displayName: 'Demo Trainer',
            nickname: 'trainer',
          ),
          wodDescription: '18.1',
          bookedCount: 3,
          remainingSpots: 9,
          waitlistCount: 0,
          isBooked: false,
          isWaitlisted: false,
          attendanceStatus: null,
          bookings: const [],
        ),
      ];

    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
      initialLocation: '/home',
      scheduleRepository: scheduleRepository,
    );

    expect(find.text('Book a class'), findsOneWidget);
    expect(find.text('No class booked yet'), findsOneWidget);
  });

  testWidgets('Home booking quick access shows booked classes carousel', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final profileRepository = RecordingProfileRepository()
      ..profile = const UserProfile(
        email: 'athlete@boxos.app',
        accountType: AccountType.athlete,
        role: UserRole.athlete,
        availableRoles: [UserRole.athlete],
        displayName: 'Demo Athlete',
        nickname: 'athlete',
        notificationPreferences: NotificationPreferences(
          bookingConfirmations: true,
          waitlistPromotions: true,
          paymentIssues: true,
          wodPosted: true,
          prAchievements: true,
          announcementActivity: true,
        ),
        activeGym: GymSummary(
          id: 1,
          name: 'CrossFit Mitte',
          slug: 'crossfit-mitte',
          logoUrl: 'https://example.com/m.png',
          timezone: 'Europe/Berlin',
        ),
        memberships: [
          GymMembership(
            gym: GymSummary(
              id: 1,
              name: 'CrossFit Mitte',
              slug: 'crossfit-mitte',
              logoUrl: 'https://example.com/m.png',
              timezone: 'Europe/Berlin',
            ),
            role: UserRole.athlete,
            availableRoles: [UserRole.athlete],
            status: 'active',
          ),
        ],
      );
    final scheduleRepository = RecordingScheduleRepository()
      ..classes = [
        ScheduleClass(
          id: 11,
          gymId: 1,
          title: 'Lunch Lift',
          classType: 'Strength',
          startTime: DateTime.now().add(const Duration(hours: 4)),
          durationMinutes: 60,
          capacity: 12,
          assignedTrainer: const ScheduleTrainer(
            id: 2,
            displayName: 'Demo Trainer',
            nickname: 'trainer',
          ),
          wodDescription: '',
          bookedCount: 8,
          remainingSpots: 4,
          waitlistCount: 0,
          isBooked: true,
          isWaitlisted: false,
          attendanceStatus: null,
          bookings: const [],
        ),
        ScheduleClass(
          id: 12,
          gymId: 1,
          title: 'Evening Engine',
          classType: 'Conditioning',
          startTime: DateTime.now().add(const Duration(hours: 8)),
          durationMinutes: 60,
          capacity: 14,
          assignedTrainer: const ScheduleTrainer(
            id: 3,
            displayName: 'Coach Maya',
            nickname: 'maya',
          ),
          wodDescription: '',
          bookedCount: 10,
          remainingSpots: 4,
          waitlistCount: 0,
          isBooked: true,
          isWaitlisted: false,
          attendanceStatus: null,
          bookings: const [],
        ),
      ];

    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
      initialLocation: '/home',
      scheduleRepository: scheduleRepository,
    );

    expect(find.text('Book a class'), findsOneWidget);
    expect(find.text('Lunch Lift'), findsOneWidget);
    expect(find.text('Evening Engine'), findsOneWidget);
    expect(find.text('No class booked yet'), findsNothing);
  });

  testWidgets('Notification settings flow updates preferences', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final profileRepository = RecordingProfileRepository();
    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
      initialLocation: '/notification-settings',
    );

    expect(find.text('Control what reaches you'), findsOneWidget);
    await tester.tap(find.byType(Switch).at(3));
    await _settleApp(tester);
    await tester.tap(find.byType(Switch).at(4));
    await _settleApp(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save Settings'));
    await _settleApp(tester);

    final updated = profileRepository.updatedNotificationPreferences;
    expect(updated, isNotNull);
    expect(updated!.wodPosted, isFalse);
    expect(updated.prAchievements, isFalse);
  });

  testWidgets('Notifications screen shows empty placeholder', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    await _pumpAuthenticatedRouter(
      tester,
      repository,
      RecordingProfileRepository(),
      initialLocation: '/notifications',
    );

    expect(find.text('Stay on top of the box pulse.'), findsOneWidget);
    expect(find.text('You are all caught up'), findsOneWidget);
    expect(
      find.textContaining('Booking changes, WOD drops, waitlist moves'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Notification Settings'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Inbox clear'), findsOneWidget);

    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('Notifications screen shows announcement activity items', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final profileRepository = RecordingProfileRepository()
      ..inbox = NotificationInbox(
        unreadCount: 2,
        notifications: [
          AppNotification(
            id: 1,
            type: 'announcement_commented',
            title: 'New comment on your announcement',
            body: 'Demo Athlete commented on "Friday throwdown": I will scale volume but keep the pace.',
            entityType: 'announcement',
            entityId: 7,
            readAt: null,
            createdAt: DateTime.utc(2026, 5, 29, 10),
          ),
          AppNotification(
            id: 2,
            type: 'announcement_liked',
            title: 'New like on your announcement',
            body: 'Demo Athlete liked "Friday throwdown".',
            entityType: 'announcement',
            entityId: 7,
            readAt: null,
            createdAt: DateTime.utc(2026, 5, 29, 9, 30),
          ),
        ],
      );

    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
      initialLocation: '/notifications',
    );

    expect(find.text('New comment on your announcement'), findsOneWidget);
    expect(find.text('New like on your announcement'), findsOneWidget);
    expect(find.text('Community'), findsOneWidget);
    expect(find.text('Mark all read'), findsOneWidget);
  });

  testWidgets('Footer routes between home profile and calendar pages', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final profileRepository = RecordingProfileRepository()
      ..profile = const UserProfile(
        email: 'athlete@boxos.app',
        accountType: AccountType.athlete,
        role: UserRole.athlete,
        availableRoles: [UserRole.athlete],
        displayName: 'Active Athlete',
        nickname: 'athlete',
        notificationPreferences: NotificationPreferences(
          bookingConfirmations: true,
          waitlistPromotions: true,
          paymentIssues: true,
          wodPosted: true,
          prAchievements: true,
          announcementActivity: true,
        ),
        activeGym: GymSummary(
          id: 1,
          name: 'CrossFit Mitte',
          slug: 'crossfit-mitte',
          logoUrl: 'https://example.com/m.png',
          timezone: 'Europe/Berlin',
        ),
        memberships: [
          GymMembership(
            gym: GymSummary(
              id: 1,
              name: 'CrossFit Mitte',
              slug: 'crossfit-mitte',
              logoUrl: 'https://example.com/m.png',
              timezone: 'Europe/Berlin',
            ),
            role: UserRole.athlete,
            availableRoles: [UserRole.athlete],
            status: 'active',
          ),
        ],
      );
    final router = await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
    );

    expect(find.text('QUICK ACCESS'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/home');

    router.go('/profile');
    await _settleApp(tester);
    expect(router.routeInformationProvider.value.uri.path, '/profile');
    expect(find.text('Switch gym context fast'), findsOneWidget);

    router.go('/logbook');
    await _settleApp(tester);
    expect(router.routeInformationProvider.value.uri.path, '/logbook');

    router.go('/home');
    await _settleApp(tester);
    expect(router.routeInformationProvider.value.uri.path, '/home');
    expect(find.text('QUICK ACCESS'), findsOneWidget);
  });

  testWidgets('Trainer can manage classes from schedule screen', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final profileRepository = RecordingProfileRepository()
      ..profile = const UserProfile(
        email: 'trainer@boxos.app',
        accountType: AccountType.athlete,
        role: UserRole.trainer,
        availableRoles: [UserRole.athlete, UserRole.trainer],
        displayName: 'Demo Trainer',
        nickname: 'trainer',
        notificationPreferences: NotificationPreferences(
          bookingConfirmations: true,
          waitlistPromotions: true,
          paymentIssues: true,
          wodPosted: true,
          prAchievements: true,
          announcementActivity: true,
        ),
        activeGym: GymSummary(
          id: 1,
          name: 'CrossFit Mitte',
          slug: 'crossfit-mitte',
          logoUrl: 'https://example.com/m.png',
          timezone: 'Europe/Berlin',
        ),
        memberships: [
          GymMembership(
            gym: GymSummary(
              id: 1,
              name: 'CrossFit Mitte',
              slug: 'crossfit-mitte',
              logoUrl: 'https://example.com/m.png',
              timezone: 'Europe/Berlin',
            ),
            role: UserRole.trainer,
            availableRoles: [UserRole.athlete, UserRole.trainer],
            status: 'active',
          ),
        ],
      );

    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
      initialLocation: '/my-box',
    );

    expect(find.widgetWithText(FilledButton, 'Add New Class'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Edit'), findsOneWidget);
  });

  testWidgets('Trainer can create a recurring class from schedule screen', (
    WidgetTester tester,
  ) async {
    final profileRepository = RecordingProfileRepository()
      ..profile = const UserProfile(
        email: 'trainer@boxos.app',
        accountType: AccountType.athlete,
        role: UserRole.trainer,
        availableRoles: [UserRole.athlete, UserRole.trainer],
        displayName: 'Demo Trainer',
        nickname: 'trainer',
        notificationPreferences: NotificationPreferences(
          bookingConfirmations: true,
          waitlistPromotions: true,
          paymentIssues: true,
          wodPosted: true,
          prAchievements: true,
          announcementActivity: true,
        ),
        activeGym: GymSummary(
          id: 1,
          name: 'CrossFit Mitte',
          slug: 'crossfit-mitte',
          logoUrl: 'https://example.com/m.png',
          timezone: 'Europe/Berlin',
        ),
        memberships: [
          GymMembership(
            gym: GymSummary(
              id: 1,
              name: 'CrossFit Mitte',
              slug: 'crossfit-mitte',
              logoUrl: 'https://example.com/m.png',
              timezone: 'Europe/Berlin',
            ),
            role: UserRole.trainer,
            availableRoles: [UserRole.athlete, UserRole.trainer],
            status: 'active',
          ),
        ],
      );
    final scheduleRepository = RecordingScheduleRepository();
    await _configureTestViewport(tester);
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) => profileRepository),
        scheduleRepositoryProvider.overrideWith((ref) => scheduleRepository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: MyBoxScreen())),
      ),
    );
    await _settleApp(tester);

    await tester.ensureVisible(find.text('Add New Class'));
    await _settleApp(tester);
    await tester.tap(find.text('Add New Class'));
    await _settleApp(tester);

    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await _settleApp(tester);
    await tester.tap(find.text('Demo Trainer').last);
    await _settleApp(tester);

    await tester.ensureVisible(find.text('Repeat'));
    await _settleApp(tester);
    expect(find.text('Repeat'), findsOneWidget);
    expect(find.text('Does not repeat'), findsOneWidget);

    await tester.tap(find.text('Does not repeat'));
    await _settleApp(tester);
    await tester.tap(find.text('Weekly').last);
    await _settleApp(tester);

    expect(find.text('Occurrences'), findsOneWidget);

    await tester.ensureVisible(find.text('Occurrences'));
    await _settleApp(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Occurrences'),
      '4',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save Class'));
    await _settleApp(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save Class'));
    await _settleApp(tester);

    expect(scheduleRepository.lastRecurrenceFrequency, 'weekly');
    expect(scheduleRepository.lastOccurrenceCount, 4);
  });

  testWidgets(
    'Recurring class form rejects occurrence counts beyond weekly UI horizon',
    (WidgetTester tester) async {
      final profileRepository = RecordingProfileRepository()
        ..profile = const UserProfile(
          email: 'trainer@boxos.app',
          accountType: AccountType.athlete,
          role: UserRole.trainer,
          availableRoles: [UserRole.athlete, UserRole.trainer],
          displayName: 'Demo Trainer',
          nickname: 'trainer',
          notificationPreferences: NotificationPreferences(
            bookingConfirmations: true,
            waitlistPromotions: true,
            paymentIssues: true,
            wodPosted: true,
            prAchievements: true,
            announcementActivity: true,
          ),
          activeGym: GymSummary(
            id: 1,
            name: 'CrossFit Mitte',
            slug: 'crossfit-mitte',
            logoUrl: 'https://example.com/m.png',
            timezone: 'Europe/Berlin',
          ),
          memberships: [
            GymMembership(
              gym: GymSummary(
                id: 1,
                name: 'CrossFit Mitte',
                slug: 'crossfit-mitte',
                logoUrl: 'https://example.com/m.png',
                timezone: 'Europe/Berlin',
              ),
              role: UserRole.trainer,
              availableRoles: [UserRole.athlete, UserRole.trainer],
              status: 'active',
            ),
          ],
        );
      final scheduleRepository = RecordingScheduleRepository();
      await _configureTestViewport(tester);
      final container = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWith((ref) => profileRepository),
          scheduleRepositoryProvider.overrideWith((ref) => scheduleRepository),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: MyBoxScreen())),
        ),
      );
      await _settleApp(tester);

      await tester.ensureVisible(find.text('Add New Class'));
      await _settleApp(tester);
      await tester.tap(find.text('Add New Class'));
      await _settleApp(tester);

      await tester.tap(find.byType(DropdownButtonFormField<int>).first);
      await _settleApp(tester);
      await tester.tap(find.text('Demo Trainer').last);
      await _settleApp(tester);

      await tester.ensureVisible(find.text('Does not repeat'));
      await _settleApp(tester);
      await tester.tap(find.text('Does not repeat'));
      await _settleApp(tester);
      await tester.tap(find.text('Weekly').last);
      await _settleApp(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Occurrences'),
        '54',
      );
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Save Class'),
      );
      await _settleApp(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save Class'));
      await _settleApp(tester);

      expect(
        find.text('Enter 53 or fewer occurrences for weekly repeats'),
        findsOneWidget,
      );
      expect(scheduleRepository.lastCreatedClass, isNull);
    },
  );

  testWidgets('Trainer can record attendance from schedule screen', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final profileRepository = RecordingProfileRepository()
      ..profile = const UserProfile(
        email: 'trainer@boxos.app',
        accountType: AccountType.athlete,
        role: UserRole.trainer,
        availableRoles: [UserRole.athlete, UserRole.trainer],
        displayName: 'Demo Trainer',
        nickname: 'trainer',
        notificationPreferences: NotificationPreferences(
          bookingConfirmations: true,
          waitlistPromotions: true,
          paymentIssues: true,
          wodPosted: true,
          prAchievements: true,
          announcementActivity: true,
        ),
        activeGym: GymSummary(
          id: 1,
          name: 'CrossFit Mitte',
          slug: 'crossfit-mitte',
          logoUrl: 'https://example.com/m.png',
          timezone: 'Europe/Berlin',
        ),
        memberships: [
          GymMembership(
            gym: GymSummary(
              id: 1,
              name: 'CrossFit Mitte',
              slug: 'crossfit-mitte',
              logoUrl: 'https://example.com/m.png',
              timezone: 'Europe/Berlin',
            ),
            role: UserRole.trainer,
            availableRoles: [UserRole.athlete, UserRole.trainer],
            status: 'active',
          ),
        ],
      );
    final scheduleRepository = RecordingScheduleRepository()
      ..classes = [
        ScheduleClass(
          id: 1,
          gymId: 1,
          title: 'Morning WOD',
          classType: 'WOD',
          startTime: DateTime.now().subtract(const Duration(hours: 2)),
          durationMinutes: 60,
          capacity: 12,
          assignedTrainer: ScheduleTrainer(
            id: 2,
            displayName: 'Demo Trainer',
            nickname: 'trainer',
          ),
          wodDescription: 'Fran',
          bookedCount: 1,
          remainingSpots: 11,
          isBooked: false,
          bookings: const [
            ScheduleBooking(
              userId: 7,
              displayName: 'Demo Athlete',
              nickname: 'demo',
              attendanceStatus: 'booked',
              isCurrentUser: false,
            ),
          ],
        ),
      ];

    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
      initialLocation: '/my-box',
      scheduleRepository: scheduleRepository,
    );

    expect(find.text('Booked Members'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Attended'));
    await _settleApp(tester);

    expect(scheduleRepository.lastAttendanceClassId, 1);
    expect(scheduleRepository.lastAttendanceUserId, 7);
    expect(scheduleRepository.lastAttendanceStatus, 'attended');
    expect(find.text('Attended'), findsWidgets);
  });

  testWidgets('Athlete can book and cancel a class from schedule screen', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final profileRepository = RecordingProfileRepository()
      ..profile = const UserProfile(
        email: 'demo@boxos.app',
        accountType: AccountType.athlete,
        role: UserRole.athlete,
        availableRoles: [UserRole.athlete],
        displayName: 'Demo Athlete',
        nickname: 'demo',
        notificationPreferences: NotificationPreferences(
          bookingConfirmations: true,
          waitlistPromotions: true,
          paymentIssues: true,
          wodPosted: true,
          prAchievements: true,
          announcementActivity: true,
        ),
        activeGym: GymSummary(
          id: 1,
          name: 'CrossFit Mitte',
          slug: 'crossfit-mitte',
          logoUrl: 'https://example.com/m.png',
          timezone: 'Europe/Berlin',
        ),
        memberships: [
          GymMembership(
            gym: GymSummary(
              id: 1,
              name: 'CrossFit Mitte',
              slug: 'crossfit-mitte',
              logoUrl: 'https://example.com/m.png',
              timezone: 'Europe/Berlin',
            ),
            role: UserRole.athlete,
            availableRoles: [UserRole.athlete],
            status: 'active',
          ),
        ],
      );
    final scheduleRepository = RecordingScheduleRepository();

    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
      initialLocation: '/my-box',
      scheduleRepository: scheduleRepository,
    );

    expect(find.widgetWithText(FilledButton, 'Book Class'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Book Class'));
    await _settleApp(tester);

    expect(scheduleRepository.lastBookedClassId, 1);
    expect(find.text('Cancel Booking'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel Booking'));
    await _settleApp(tester);

    expect(scheduleRepository.lastCancelledClassId, 1);
    expect(find.widgetWithText(FilledButton, 'Book Class'), findsOneWidget);
  });

  testWidgets('Athlete can join and leave waitlist from full class', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final profileRepository = RecordingProfileRepository()
      ..profile = const UserProfile(
        email: 'demo@boxos.app',
        accountType: AccountType.athlete,
        role: UserRole.athlete,
        availableRoles: [UserRole.athlete],
        displayName: 'Demo Athlete',
        nickname: 'demo',
        notificationPreferences: NotificationPreferences(
          bookingConfirmations: true,
          waitlistPromotions: true,
          paymentIssues: true,
          wodPosted: true,
          prAchievements: true,
          announcementActivity: true,
        ),
        activeGym: GymSummary(
          id: 1,
          name: 'CrossFit Mitte',
          slug: 'crossfit-mitte',
          logoUrl: 'https://example.com/m.png',
          timezone: 'Europe/Berlin',
        ),
        memberships: [
          GymMembership(
            gym: GymSummary(
              id: 1,
              name: 'CrossFit Mitte',
              slug: 'crossfit-mitte',
              logoUrl: 'https://example.com/m.png',
              timezone: 'Europe/Berlin',
            ),
            role: UserRole.athlete,
            availableRoles: [UserRole.athlete],
            status: 'active',
          ),
        ],
      );
    final scheduleRepository = RecordingScheduleRepository()
      ..classes = [
        ScheduleClass(
          id: 1,
          gymId: 1,
          title: 'Packed WOD',
          classType: 'WOD',
          startTime: DateTime.now().add(const Duration(hours: 2)),
          durationMinutes: 60,
          capacity: 12,
          assignedTrainer: ScheduleTrainer(
            id: 2,
            displayName: 'Demo Trainer',
            nickname: 'trainer',
          ),
          wodDescription: '18.1',
          bookedCount: 12,
          remainingSpots: 0,
          waitlistCount: 0,
          isBooked: false,
          isWaitlisted: false,
          attendanceStatus: null,
          bookings: const [],
        ),
      ];

    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
      initialLocation: '/my-box',
      scheduleRepository: scheduleRepository,
    );

    expect(find.widgetWithText(FilledButton, 'Join Waitlist'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Join Waitlist'));
    await _settleApp(tester);

    expect(scheduleRepository.lastWaitlistedClassId, 1);
    expect(
      find.widgetWithText(OutlinedButton, 'Leave Waitlist'),
      findsOneWidget,
    );
    expect(find.text('Waitlist: Active'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Leave Waitlist'));
    await _settleApp(tester);

    expect(scheduleRepository.lastLeftWaitlistClassId, 1);
    expect(find.widgetWithText(FilledButton, 'Join Waitlist'), findsOneWidget);
  });

  testWidgets('Admin without gym sees create gym setup on home', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final profileRepository = RecordingProfileRepository()
      ..profile = const UserProfile(
        email: 'admin@boxos.app',
        accountType: AccountType.admin,
        role: UserRole.admin,
        availableRoles: [UserRole.admin],
        displayName: 'Admin User',
        nickname: 'admin',
        notificationPreferences: NotificationPreferences(
          bookingConfirmations: true,
          waitlistPromotions: true,
          paymentIssues: true,
          wodPosted: true,
          prAchievements: true,
          announcementActivity: true,
        ),
        activeGym: null,
        memberships: [],
      );

    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
      initialLocation: '/home',
    );

    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await _settleApp(tester);
    expect(find.text('Create Your First Gym'), findsOneWidget);
    expect(find.text('Open the floor'), findsOneWidget);
  });

  testWidgets('Gym directory filters gyms and shows my request status', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final gymRepository = RecordingGymRepository()
      ..gyms = const [
        GymSummary(
          id: 1,
          name: 'CrossFit Mitte',
          slug: 'crossfit-mitte',
          logoUrl: 'https://example.com/m.png',
          timezone: 'Europe/Berlin',
        ),
        GymSummary(
          id: 2,
          name: 'BoxOS Downtown',
          slug: 'boxos-downtown',
          logoUrl: 'https://example.com/d.png',
          timezone: 'America/New_York',
        ),
      ]
      ..myRequests = const [
        MyGymJoinRequest(
          id: 1,
          status: 'pending',
          createdAt: '2026-04-13T10:00:00Z',
          reviewedAt: null,
          gym: GymSummary(
            id: 1,
            name: 'CrossFit Mitte',
            slug: 'crossfit-mitte',
            logoUrl: 'https://example.com/m.png',
            timezone: 'Europe/Berlin',
          ),
        ),
      ];

    await _pumpAuthenticatedRouter(
      tester,
      repository,
      RecordingProfileRepository(),
      initialLocation: '/gyms',
      gymRepository: gymRepository,
    );

    expect(find.text('My Requests'), findsOneWidget);
    expect(find.text('Pending'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'downtown');
    await _settleApp(tester);

    expect(find.text('BoxOS Downtown'), findsOneWidget);
    expect(find.text('CrossFit Mitte'), findsOneWidget);
  });

  testWidgets('Admin can review join requests from admin-only screen', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final gymRepository = RecordingGymRepository();
    final profileRepository = RecordingProfileRepository()
      ..profile = const UserProfile(
        email: 'admin@boxos.app',
        accountType: AccountType.admin,
        role: UserRole.admin,
        availableRoles: [UserRole.admin],
        displayName: 'Admin User',
        nickname: 'admin',
        notificationPreferences: NotificationPreferences(
          bookingConfirmations: true,
          waitlistPromotions: true,
          paymentIssues: true,
          wodPosted: true,
          prAchievements: true,
          announcementActivity: true,
        ),
        activeGym: GymSummary(
          id: 1,
          name: 'CrossFit Mitte',
          slug: 'crossfit-mitte',
          logoUrl: 'https://example.com/m.png',
          timezone: 'Europe/Berlin',
        ),
        memberships: [
          GymMembership(
            gym: GymSummary(
              id: 1,
              name: 'CrossFit Mitte',
              slug: 'crossfit-mitte',
              logoUrl: 'https://example.com/m.png',
              timezone: 'Europe/Berlin',
            ),
            role: UserRole.admin,
            availableRoles: [UserRole.admin],
            status: 'active',
          ),
        ],
      );

    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
      initialLocation: '/gym-requests',
      gymRepository: gymRepository,
    );

    expect(find.text('Join Requests'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await _settleApp(tester);

    expect(gymRepository.reviewedRequestId, 1);
    expect(gymRepository.lastReviewApproval, isTrue);
  });

  testWidgets('Athletes are blocked from join request review screen', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final profileRepository = RecordingProfileRepository();
    final gymRepository = RecordingGymRepository();

    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
      initialLocation: '/gym-requests',
      gymRepository: gymRepository,
    );

    expect(
      find.text('You need an active admin gym to review join requests.'),
      findsOneWidget,
    );
    expect(gymRepository.fetchJoinRequestsCalls, 0);
  });

  testWidgets('Athletes are blocked from create gym screen', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final profileRepository = RecordingProfileRepository();
    final gymRepository = RecordingGymRepository();

    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
      initialLocation: '/create-gym',
      gymRepository: gymRepository,
    );

    expect(find.text('Only admin accounts can create a gym.'), findsOneWidget);
    expect(gymRepository.createGymCalls, 0);
  });

  testWidgets('Profile shows gym switcher actions for multiple memberships', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final profileRepository = RecordingProfileRepository()
      ..profile = const UserProfile(
        email: 'athlete@boxos.app',
        accountType: AccountType.athlete,
        role: UserRole.athlete,
        availableRoles: [UserRole.athlete],
        displayName: 'Athlete User',
        nickname: 'athlete',
        notificationPreferences: NotificationPreferences(
          bookingConfirmations: true,
          waitlistPromotions: true,
          paymentIssues: true,
          wodPosted: true,
          prAchievements: true,
          announcementActivity: true,
        ),
        activeGym: GymSummary(
          id: 1,
          name: 'Gym One',
          slug: 'gym-one',
          logoUrl: 'https://example.com/one.png',
          timezone: 'Europe/Berlin',
        ),
        memberships: [
          GymMembership(
            gym: GymSummary(
              id: 1,
              name: 'Gym One',
              slug: 'gym-one',
              logoUrl: 'https://example.com/one.png',
              timezone: 'Europe/Berlin',
            ),
            role: UserRole.athlete,
            availableRoles: [UserRole.athlete],
            status: 'active',
          ),
          GymMembership(
            gym: GymSummary(
              id: 2,
              name: 'Gym Two',
              slug: 'gym-two',
              logoUrl: 'https://example.com/two.png',
              timezone: 'America/New_York',
            ),
            role: UserRole.athlete,
            availableRoles: [UserRole.athlete],
            status: 'active',
          ),
        ],
      );

    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
      initialLocation: '/profile',
    );

    final switchButton = find.widgetWithText(
      OutlinedButton,
      'Switch to This Gym',
    );
    await tester.ensureVisible(switchButton);
    await _settleApp(tester);

    expect(find.text('Switch gym context fast'), findsOneWidget);
    expect(find.text('Current Gym'), findsOneWidget);
    expect(switchButton, findsOneWidget);
  });

  testWidgets('Trainer home starts with news instead of the role hero', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final profileRepository = RecordingProfileRepository()
      ..profile = const UserProfile(
        email: 'trainer@boxos.app',
        accountType: AccountType.athlete,
        role: UserRole.trainer,
        availableRoles: [UserRole.athlete, UserRole.trainer],
        displayName: 'Casey Trainer',
        nickname: 'coachcasey',
        notificationPreferences: NotificationPreferences(
          bookingConfirmations: true,
          waitlistPromotions: true,
          paymentIssues: true,
          wodPosted: true,
          prAchievements: true,
          announcementActivity: true,
        ),
        activeGym: null,
        memberships: [],
      );

    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
      initialLocation: '/home',
    );

    expect(find.text('News'), findsOneWidget);
    expect(find.text('Today at a glance'), findsNothing);
    expect(find.text('Role: Trainer'), findsNothing);
  });

  testWidgets('Admin users can access role management from profile', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final profileRepository = RecordingProfileRepository()
      ..profile = const UserProfile(
        email: 'demo@boxos.app',
        accountType: AccountType.admin,
        role: UserRole.admin,
        availableRoles: [UserRole.athlete, UserRole.admin],
        displayName: 'Demo Admin',
        nickname: 'admin',
        notificationPreferences: NotificationPreferences(
          bookingConfirmations: true,
          waitlistPromotions: true,
          paymentIssues: true,
          wodPosted: true,
          prAchievements: true,
          announcementActivity: true,
        ),
        activeGym: GymSummary(
          id: 1,
          name: 'Demo Admin',
          slug: 'demo-box',
          logoUrl: 'https://example.com/box.png',
          timezone: 'Europe/Berlin',
        ),
        memberships: [
          GymMembership(
            gym: GymSummary(
              id: 1,
              name: 'Demo Admin',
              slug: 'demo-box',
              logoUrl: 'https://example.com/box.png',
              timezone: 'Europe/Berlin',
            ),
            role: UserRole.admin,
            availableRoles: [UserRole.athlete, UserRole.admin],
            status: 'active',
          ),
        ],
      );

    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
      initialLocation: '/profile',
    );

    expect(find.text('Manage Gym Members'), findsOneWidget);
  });

  testWidgets('Admin users can manage roles', (WidgetTester tester) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final profileRepository = RecordingProfileRepository()
      ..profile = const UserProfile(
        email: 'demo@boxos.app',
        accountType: AccountType.admin,
        role: UserRole.admin,
        availableRoles: [UserRole.athlete, UserRole.admin],
        displayName: 'Demo Admin',
        nickname: 'admin',
        notificationPreferences: NotificationPreferences(
          bookingConfirmations: true,
          waitlistPromotions: true,
          paymentIssues: true,
          wodPosted: true,
          prAchievements: true,
          announcementActivity: true,
        ),
        activeGym: GymSummary(
          id: 1,
          name: 'Demo Admin',
          slug: 'demo-box',
          logoUrl: 'https://example.com/box.png',
          timezone: 'Europe/Berlin',
        ),
        memberships: [
          GymMembership(
            gym: GymSummary(
              id: 1,
              name: 'Demo Admin',
              slug: 'demo-box',
              logoUrl: 'https://example.com/box.png',
              timezone: 'Europe/Berlin',
            ),
            role: UserRole.admin,
            availableRoles: [UserRole.athlete, UserRole.admin],
            status: 'active',
          ),
        ],
      );

    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
      initialLocation: '/role-management',
    );

    expect(find.text('Gym Members'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Trainer').first);
    await _settleApp(tester);
    final saveRoleButton = find.widgetWithText(FilledButton, 'Save Role').last;
    await tester.ensureVisible(saveRoleButton);
    await _settleApp(tester);
    await tester.tap(saveRoleButton);
    await _settleApp(tester);

    expect(profileRepository.updatedManagedUser, isNotNull);
    expect(profileRepository.updatedManagedUser!.email, 'trainer@boxos.app');
    expect(
      profileRepository.updatedManagedUser!.availableRoles,
      contains(UserRole.trainer),
    );
  });

  testWidgets('Non-admin users are blocked from role management', (
    WidgetTester tester,
  ) async {
    final repository = RecordingAuthRepository()..isSignedIn = true;
    final profileRepository = RecordingProfileRepository();

    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
      initialLocation: '/role-management',
    );

    expect(
      find.text('You need an active admin gym to manage member roles.'),
      findsOneWidget,
    );
  });
}
