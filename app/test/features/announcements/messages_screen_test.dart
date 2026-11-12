import 'package:app/app.dart';
import 'package:app/core/presentation/app_side_panel.dart';
import 'package:app/features/announcements/data/repositories/api_announcement_repository.dart';
import 'package:app/features/announcements/domain/models/announcement.dart';
import 'package:app/features/announcements/domain/repositories/announcement_repository.dart';
import 'package:app/features/announcements/presentation/screens/messages_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Announcement _message(int id, String title) => Announcement(
  id: id,
  gymId: 1,
  title: title,
  description: 'Body of $title',
  imageUrl: null,
  authorName: 'Jordan Cole',
  createdAt: DateTime(2026, 11, id),
  updatedAt: DateTime(2026, 11, id),
  likeCount: 3,
  likedByMe: false,
  commentCount: 0,
  comments: const [],
  canManage: true,
);

class _FakeRepository implements AnnouncementRepository {
  @override
  Future<List<Announcement>> fetchAnnouncements() async => [
    _message(2, 'Holiday hours'),
    _message(1, 'New barbells'),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        announcementRepositoryProvider.overrideWithValue(_FakeRepository()),
      ],
      child: MaterialApp(
        theme: buildBoxOsTheme(),
        home: const Scaffold(body: MessagesScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wide: list beside the reading pane, search filters', (
    tester,
  ) async {
    await _pump(tester, const Size(1280, 800));
    expect(find.text('2 of 2 messages'), findsOneWidget);
    // The newest message is open in the reading pane.
    expect(find.text('Body of Holiday hours'), findsOneWidget);

    await tester.tap(find.text('New barbells'));
    await tester.pumpAndSettle();
    expect(find.text('Body of New barbells'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'holiday');
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 messages'), findsOneWidget);

    await tester.tap(find.byTooltip('Compose'));
    await tester.pumpAndSettle();
    expect(find.byType(AppSidePanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow: a message opens in a side panel', (tester) async {
    await _pump(tester, const Size(390, 844));
    expect(find.text('Body of Holiday hours'), findsNothing);
    await tester.tap(find.text('Holiday hours'));
    await tester.pumpAndSettle();
    expect(find.text('Body of Holiday hours'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
