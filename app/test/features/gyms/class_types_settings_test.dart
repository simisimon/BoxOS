import 'package:app/app.dart';
import 'package:app/features/calendar/data/repositories/class_types_repository.dart';
import 'package:app/features/calendar/domain/models/class_type.dart';
import 'package:app/features/gyms/presentation/screens/box_settings_screen.dart';
import 'package:app/features/memberships/domain/membership_models.dart';
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

final _profile = UserProfile(
  email: 'owner@boxos.app',
  accountType: AccountType.admin,
  role: UserRole.admin,
  availableRoles: const [UserRole.admin],
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
  activeGym: _gym,
  memberships: const [
    GymMembership(
      gym: _gym,
      role: UserRole.admin,
      availableRoles: [UserRole.admin],
      status: 'active',
    ),
  ],
);

class _FakeClassTypesRepository implements ClassTypesRepository {
  final List<ClassType> types = [];

  @override
  Future<List<ClassType>> fetch() async => [...types];

  @override
  Future<List<ClassType>> create({
    required String name,
    required String colorKey,
    required int defaultCapacity,
  }) async {
    types.add(
      ClassType(
        name,
        name,
        colorKey: colorKey,
        defaultCapacity: defaultCapacity,
        id: types.length + 1,
      ),
    );
    return [...types];
  }

  @override
  Future<List<ClassType>> delete(int id) async {
    types.removeWhere((type) => type.id == id);
    return [...types];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeClassTypesRepository> _pump(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => ClassType.registerCustom(const []));
  final repository = _FakeClassTypesRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentProfileProvider.overrideWith((ref) async => _profile),
        classTypesRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: buildBoxOsTheme(),
        home: const Scaffold(
          body: BoxSettingsScreen(section: SettingsSection.classTypes),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  for (final size in const [Size(1280, 800), Size(390, 844)]) {
    testWidgets('owner creates and deletes a class type at ${size.width}', (
      tester,
    ) async {
      final repository = await _pump(tester, size);
      expect(find.text('WOD'), findsOneWidget);
      expect(find.text('BUILT-IN'), findsNWidgets(4));

      await tester.tap(find.text('Create class type'));
      await tester.pumpAndSettle();
      // Built-in names are taken, ignoring case.
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'wod');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.text('That type already exists'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'Hyrox',
      );
      await tester.tap(find.bySemanticsLabel('Colour Red'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Default limit'),
        '16',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(repository.types.single.colorKey, 'danger');
      expect(find.text('Hyrox'), findsOneWidget);
      expect(find.text('16 participants'), findsOneWidget);
      // Pickers and plans see the new type.
      expect(ClassType.values.last.wireValue, 'Hyrox');
      expect(planClassTypes.last, 'Hyrox');
      expect(ClassType.fromWire('Hyrox').defaultCapacity, 16);

      await tester.tap(find.byTooltip('Delete Hyrox'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(repository.types, isEmpty);
      expect(find.text('Hyrox'), findsNothing);
    });
  }

  test('an unregistered type keeps its name instead of becoming a WOD', () {
    expect(ClassType.fromWire('Yoga').label, 'Yoga');
    expect(ClassType.fromWire('Yoga').showsWod, isFalse);
    expect(ClassType.fromWire(''), ClassType.wod);
  });
}
