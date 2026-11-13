import 'package:app/app.dart';
import 'package:app/features/calendar/domain/models/class_type.dart';
import 'package:app/features/members/domain/member_booking.dart';
import 'package:app/features/memberships/data/membership_repository.dart';
import 'package:app/features/profile/presentation/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

MemberBooking _booking(String title, int days, String status) {
  final start = DateTime.now().add(Duration(days: days));
  return MemberBooking(
    classId: title.hashCode,
    title: title,
    type: ClassType.wod,
    start: start,
    end: start.add(const Duration(hours: 1)),
    trainerName: 'Coach Alex',
    status: status,
    cancelledAt: status == 'cancelled' ? DateTime.now() : null,
  );
}

void main() {
  for (final size in const [Size(1280, 900), Size(390, 844)]) {
    testWidgets('Bookings splits upcoming, past and cancelled at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Newest class first, as the server sends them.
            myBookingsProvider.overrideWith(
              (ref) async => [
                _booking('Friday WOD', 3, 'booked'),
                _booking('Skipped WOD', 2, 'cancelled'),
                _booking('Monday WOD', -4, 'attended'),
              ],
            ),
          ],
          child: MaterialApp(
            theme: buildBoxOsTheme(),
            home: const Scaffold(
              body: SingleChildScrollView(child: MyBookingsSection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Upcoming 1'), findsOneWidget);
      expect(find.text('Friday WOD'), findsOneWidget);
      expect(find.text('REGISTERED'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);

      await tester.tap(find.text('Past 1'));
      await tester.pumpAndSettle();
      expect(find.text('Monday WOD'), findsOneWidget);
      expect(find.text('ATTENDED'), findsOneWidget);

      await tester.tap(find.text('Cancelled 1'));
      await tester.pumpAndSettle();
      expect(find.text('Skipped WOD'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
