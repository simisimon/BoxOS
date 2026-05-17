import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/app.dart';
import 'package:app/core/routing/router.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/data/repositories/api_auth_repository.dart';
import 'package:app/features/auth/domain/repositories/auth_repository.dart';
import 'package:app/features/auth/presentation/screens/change_password_screen.dart';
import 'package:app/features/auth/presentation/screens/delete_account_screen.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/schedule_booking.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
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
    ),
    activeGym: null,
    memberships: [],
  );
  String? updatedDisplayName;
  String? updatedNickname;
  NotificationPreferences? updatedNotificationPreferences;
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
    return const NotificationInbox(unreadCount: 0, notifications: []);
  }

  @override
  Future<NotificationInbox> markAllNotificationsRead() async {
    return const NotificationInbox(unreadCount: 0, notifications: []);
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
  Future<List<GymJoinRequest>> fetchJoinRequests() async => requests;

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
      startTime: DateTime(2026, 4, 16, 18),
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

Future<void> _tapFooterDestination(WidgetTester tester, int index) async {
  await tester.tap(find.byType(NavigationDestination).at(index));
  await _settleApp(tester);
}

Future<GoRouter> _pumpAuthenticatedRouter(
  WidgetTester tester,
  RecordingAuthRepository repository,
  RecordingProfileRepository profileRepository, {
  String initialLocation = '/home',
  RecordingGymRepository? gymRepository,
  RecordingScheduleRepository? scheduleRepository,
}) async {
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
      GoRoute(
        path: '/calendar',
        redirect: (context, state) => '/my-box',
      ),
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
  );
}

Future<ProviderContainer> _pumpAppWithRepositories(
  WidgetTester tester,
  RecordingAuthRepository repository,
  RecordingProfileRepository profileRepository,
  RecordingGymRepository gymRepository,
) async {
  final effectiveProfileRepository = profileRepository;
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWith((ref) => repository),
      profileRepositoryProvider.overrideWith(
        (ref) => effectiveProfileRepository,
      ),
      gymRepositoryProvider.overrideWith((ref) => gymRepository),
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

    await tester.ensureVisible(find.text('Sign In'));
    await tester.tap(find.text('Sign In'));
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

    await tester.ensureVisible(find.text('Sign In'));
    await tester.tap(find.text('Sign In'));
    await _settleApp(tester);

    expect(repository.isSignedIn, isTrue);
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
    await tester.tap(find.widgetWithText(FilledButton, 'Create Admin Account'));
    await _settleApp(tester);

    expect(repository.adminSignUpEmail, 'admin@boxos.app');
    expect(repository.adminSignUpPassword, 'adminpass123');
    expect(find.text('Verification Token'), findsOneWidget);
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

    expect(find.text('Sign In'), findsOneWidget);

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

    expect(find.text('Reset Password'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(1), 'newpassword123');
    await tester.enterText(find.byType(TextFormField).at(2), 'newpassword123');
    await tester.tap(find.byType(CheckboxListTile));
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

    expect(find.text('Reset Password'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(1), 'newpassword123');
    await tester.enterText(find.byType(TextFormField).at(2), 'newpassword123');
    await tester.tap(find.widgetWithText(FilledButton, 'Update Password'));
    await _settleApp(tester);

    expect(repository.resetToken, 'reset-token-abc');
    expect(repository.resetNewPassword, 'newpassword123');
    expect(repository.resetLogoutOtherSessions, isTrue);
    expect(find.text('Sign In'), findsOneWidget);
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
    await tester.tap(find.byType(CheckboxListTile));
    await _settleApp(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Update Password'));
    await _settleApp(tester);

    expect(repository.changeCurrentPassword, 'oldpassword');
    expect(repository.changeNewPassword, 'newpassword123');
    expect(repository.changeLogoutOtherSessions, isTrue);
    expect(find.text('BoxOS'), findsOneWidget);
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
    await tester.tap(find.widgetWithText(FilledButton, 'Delete Account'));
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
    await tester.tap(find.widgetWithText(FilledButton, 'Save Profile'));
    await _settleApp(tester);

    expect(profileRepository.updatedDisplayName, 'Basti Athlete');
    expect(profileRepository.updatedNickname, 'basti');
    expect(find.text('Basti Athlete'), findsWidgets);
    expect(find.text('@basti'), findsOneWidget);
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

    expect(find.text('Notification Settings'), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, 'WOD Posted'));
    await _settleApp(tester);
    await tester.tap(find.widgetWithText(SwitchListTile, 'PR Achievements'));
    await _settleApp(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save Settings'));
    await _settleApp(tester);

    final updated = profileRepository.updatedNotificationPreferences;
    expect(updated, isNotNull);
    expect(updated!.wodPosted, isFalse);
    expect(updated.prAchievements, isFalse);
    expect(find.text('Account Settings'), findsOneWidget);
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
    await _pumpAuthenticatedRouter(
      tester,
      repository,
      profileRepository,
    );

    expect(find.text('Quick Actions'), findsOneWidget);

    await _tapFooterDestination(tester, 1);
    expect(find.text('Account Settings'), findsOneWidget);

    await _tapFooterDestination(tester, 2);
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Evening WOD'), findsOneWidget);

    await _tapFooterDestination(tester, 0);
    expect(find.text('Quick Actions'), findsOneWidget);
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

    expect(find.widgetWithText(FilledButton, 'Add Class'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Edit'), findsOneWidget);
  });

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
          startTime: DateTime(2026, 4, 1, 9),
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
          startTime: DateTime(2026, 4, 16, 18),
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
    expect(find.widgetWithText(OutlinedButton, 'Leave Waitlist'), findsOneWidget);
    expect(find.text('Waitlist: 1'), findsOneWidget);

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

    expect(find.text('Admin Setup'), findsOneWidget);
    expect(find.text('Create Your First Gym'), findsOneWidget);
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

    expect(find.text('Gym Memberships'), findsOneWidget);
    expect(find.text('Current Gym'), findsOneWidget);
    expect(switchButton, findsOneWidget);
  });

  testWidgets('Role labels render for trainer accounts', (
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

    expect(find.text('Role: Trainer'), findsOneWidget);
    expect(find.byIcon(Icons.swap_horiz_rounded), findsOneWidget);
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

    expect(
      find.widgetWithText(OutlinedButton, 'Manage Gym Members'),
      findsOneWidget,
    );
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
    await tester.tap(find.widgetWithText(FilterChip, 'Athlete').last);
    await _settleApp(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save Role').last);
    await _settleApp(tester);

    expect(profileRepository.updatedManagedUser, isNotNull);
    expect(profileRepository.updatedManagedUser!.email, 'trainer@boxos.app');
    expect(profileRepository.updatedManagedUser!.availableRoles, [
      UserRole.trainer,
      UserRole.athlete,
    ]);
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

    expect(find.text('You need the Admin role to manage roles.'), findsOneWidget);
  });
}
