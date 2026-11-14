import 'package:app/app.dart';
import 'package:app/features/results/data/api_follows_repository.dart';
import 'package:app/features/results/domain/workout_result.dart';
import 'package:app/features/results/presentation/friends_feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFollows implements FollowsRepository {
  var overview = const FollowOverview(
    inviteCode: 'K7QM2XPA',
    requests: [FollowPerson(userId: 4, name: 'Ben', gymName: 'Other Box')],
    following: [FollowPerson(userId: 5, name: 'Cleo')],
  );
  final accepted = <int>[];
  final declined = <int>[];
  final unfollowed = <int>[];
  final followed = <(int?, String?)>[];
  FeedPage feed = FeedPage(
    entries: [
      FeedEntry(
        result: WorkoutResult(
          id: 21,
          sectionId: null,
          performedOn: DateTime(2026, 11, 13),
          scoreLabel: '3:58',
          scoreValue: 238,
          division: ResultDivision.rx,
          sectionTitle: 'Fran',
          isPersonal: true,
          isPr: true,
        ),
        userId: 5,
        name: 'Cleo',
        bumpCount: 2,
        commentCount: 1,
      ),
      FeedEntry(
        result: WorkoutResult(
          id: 22,
          sectionId: 3,
          performedOn: DateTime(2026, 11, 12),
          scoreLabel: '7+14',
          scoreValue: 7014,
          division: ResultDivision.scaled,
          sectionTitle: 'Cindy',
        ),
        userId: 5,
        name: 'Cleo',
        gymName: 'Cleo Box',
      ),
    ],
  );

  @override
  Future<FollowOverview> fetchOverview() async => overview;

  @override
  Future<List<FollowPerson>> search(String query) async => [
    const FollowPerson(userId: 9, name: 'Mia Mate'),
  ];

  @override
  Future<FollowStatus> follow({int? userId, String? inviteCode}) async {
    followed.add((userId, inviteCode));
    return FollowStatus.pending;
  }

  @override
  Future<void> accept(int followerId) async {
    accepted.add(followerId);
    overview = FollowOverview(
      inviteCode: overview.inviteCode,
      following: overview.following,
      followers: [overview.requests.first],
    );
  }

  @override
  Future<void> removeFollower(int followerId) async => declined.add(followerId);

  @override
  Future<void> unfollow(int followeeId) async => unfollowed.add(followeeId);

  @override
  Future<FeedPage> fetchFeed({int offset = 0}) async =>
      offset == 0 ? feed : const FeedPage(entries: []);
}

Future<void> _pump(
  WidgetTester tester,
  _FakeFollows fake, {
  String? followCode,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 1000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [followsRepositoryProvider.overrideWithValue(fake)],
      child: MaterialApp(
        theme: buildBoxOsTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: FriendsFeed(followCode: followCode),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the feed lists friends\' results', (tester) async {
    await _pump(tester, _FakeFollows());
    expect(find.text('Fran'), findsOneWidget);
    expect(find.text('3:58'), findsOneWidget);
    expect(find.text('PR'), findsOneWidget);
    expect(find.textContaining('Logbook'), findsOneWidget);
    expect(find.textContaining('Cleo Box'), findsOneWidget);
    expect(find.text('Friends (1)'), findsOneWidget);
  });

  testWidgets('an empty feed explains how to follow', (tester) async {
    final fake = _FakeFollows()..feed = const FeedPage(entries: []);
    await _pump(tester, fake);
    expect(find.textContaining('Nothing here yet.'), findsOneWidget);
  });

  testWidgets('requests are accepted and people followed in the panel', (
    tester,
  ) async {
    final fake = _FakeFollows();
    await _pump(tester, fake);
    await tester.tap(find.byKey(const ValueKey('open-friends')));
    await tester.pumpAndSettle();
    expect(find.text('K7QM2XPA'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(fake.accepted, [4]);
    expect(find.text('Ben now follows you.'), findsOneWidget);
    expect(find.text('FOLLOWERS (1)'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('friends-search')), 'mia');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Follow'));
    await tester.pumpAndSettle();
    expect(fake.followed, [(9, null)]);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('following-5')),
        matching: find.text('Unfollow'),
      ),
    );
    await tester.pumpAndSettle();
    expect(fake.unfollowed, [5]);
  });

  testWidgets('an invite link opens the panel with the code', (tester) async {
    final fake = _FakeFollows();
    await _pump(tester, fake, followCode: 'ABCD2345');
    expect(find.text('Follow athletes at any gym'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Follow'));
    await tester.pumpAndSettle();
    expect(fake.followed, [(null, 'ABCD2345')]);
    expect(find.textContaining('Request sent.'), findsOneWidget);
  });
}
