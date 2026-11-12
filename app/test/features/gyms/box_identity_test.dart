import 'package:app/app.dart';
import 'package:app/features/gyms/data/repositories/api_gym_repository.dart';
import 'package:app/features/gyms/domain/models/gym_update_result.dart';
import 'package:app/features/gyms/domain/repositories/gym_repository.dart';
import 'package:app/features/gyms/presentation/screens/box_settings_screen.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/domain/models/gym_membership.dart';
import 'package:app/features/profile/domain/models/gym_summary.dart';
import 'package:app/features/profile/domain/models/notification_preferences.dart';
import 'package:app/features/profile/domain/models/user_profile.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _gym = GymSummary(
  id: 1,
  name: 'Test Box',
  slug: 'test-box',
  logoUrl: '',
  timezone: 'Europe/Berlin',
);

UserProfile _profile(GymSummary gym, {UserRole role = UserRole.admin}) =>
    UserProfile(
      email: 'owner@boxos.app',
      accountType: AccountType.admin,
      role: role,
      availableRoles: const [UserRole.admin, UserRole.athlete],
      displayName: 'Box Owner',
      nickname: 'owner',
      notificationPreferences: const NotificationPreferences(
        bookingConfirmations: true,
        waitlistPromotions: true,
        paymentIssues: true,
        wodPosted: true,
        prAchievements: true,
        announcementActivity: true,
      ),
      activeGym: gym,
      memberships: [
        GymMembership(
          gym: gym,
          role: role,
          availableRoles: const [UserRole.admin, UserRole.athlete],
          status: 'active',
        ),
      ],
    );

class _FakeGymRepository implements GymRepository {
  GymSummary gym = _gym;
  final List<Map<String, String?>> updates = [];

  @override
  Future<GymUpdateResult> updateCurrentGym({
    String? name,
    String? logoUrl,
    String? timezone,
  }) async {
    updates.add({'name': name, 'logo_url': logoUrl, 'timezone': timezone});
    gym = GymSummary(
      id: gym.id,
      name: name ?? gym.name,
      slug: gym.slug,
      logoUrl: logoUrl ?? gym.logoUrl,
      timezone: timezone ?? gym.timezone,
    );
    return GymUpdateResult(
      gym: gym,
      detachedSessions: timezone == null ? 0 : 2,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeGymRepository> _pump(
  WidgetTester tester, {
  UserRole role = UserRole.admin,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(430, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repository = _FakeGymRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentProfileProvider.overrideWith(
          (ref) async => _profile(repository.gym, role: role),
        ),
        gymRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: buildBoxOsTheme(),
        // Box settings is a shell tab; the shell supplies the Scaffold.
        home: const Scaffold(body: BoxSettingsScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

Future<void> _openIdentity(WidgetTester tester) async {
  await tester.tap(find.text('Gym profile'));
  await tester.pumpAndSettle();
}

Finder _saveButton() => find.widgetWithText(FilledButton, 'Save changes');

void main() {
  testWidgets('owner renames the box; only the changed field is sent', (
    tester,
  ) async {
    final repository = await _pump(tester);
    await _openIdentity(tester);

    expect(tester.widget<FilledButton>(_saveButton()).onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Box name'),
      'Renamed Box',
    );
    await tester.pump();
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();

    expect(repository.updates, [
      {'name': 'Renamed Box', 'logo_url': null, 'timezone': null},
    ]);
    expect(find.text('Box identity saved.'), findsOneWidget);
    // The form reloads from the refreshed profile and is clean again.
    expect(find.text('Renamed Box'), findsOneWidget);
    expect(tester.widget<FilledButton>(_saveButton()).onPressed, isNull);
  });

  testWidgets('changing the timezone asks for confirmation first', (
    tester,
  ) async {
    final repository = await _pump(tester);
    await _openIdentity(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Timezone'),
      'America/New_York',
    );
    await tester.pump();
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();

    expect(find.text('Change timezone?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.updates, isEmpty);

    await tester.tap(_saveButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change timezone'));
    await tester.pumpAndSettle();

    expect(repository.updates, [
      {'name': null, 'logo_url': null, 'timezone': 'America/New_York'},
    ]);
    expect(find.textContaining('2 booked classes keep'), findsOneWidget);
  });

  testWidgets('a blank name is rejected before calling the server', (
    tester,
  ) async {
    final repository = await _pump(tester);
    await _openIdentity(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Box name'), ' ');
    await tester.pump();
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();

    expect(find.text('Box name is required'), findsOneWidget);
    expect(repository.updates, isEmpty);
  });

  testWidgets('non-owners do not get the settings', (tester) async {
    await _pump(tester, role: UserRole.athlete);
    expect(find.text('Owner access required'), findsOneWidget);
    expect(find.text('Gym profile'), findsNothing);
  });
}
