import 'package:app/app.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/app_notification.dart';
import 'package:app/features/profile/presentation/widgets/notifications_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AppNotification _n(int id, String title, DateTime at, {bool read = false}) =>
    AppNotification(
      id: id,
      type: 'announcement_liked',
      title: title,
      body: '',
      entityType: 'announcement',
      entityId: 1,
      readAt: read ? at : null,
      createdAt: at,
    );

void main() {
  for (final size in const [Size(1280, 800), Size(390, 844)]) {
    testWidgets('panel groups, filters unread and opens an item at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      AppNotification? opened;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationInboxProvider.overrideWith(
              (ref) async => NotificationInbox(
                unreadCount: 1,
                notifications: [
                  _n(1, 'Someone liked your post', now),
                  _n(
                    2,
                    'Old news',
                    now.subtract(const Duration(days: 3)),
                    read: true,
                  ),
                ],
              ),
            ),
          ],
          child: MaterialApp(
            theme: buildBoxOsTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showNotificationsPanel(
                    context,
                    onOpen: (n) => opened = n,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('EARLIER'), findsOneWidget);
      await tester.tap(find.text('Unread 1'));
      await tester.pumpAndSettle();
      expect(find.text('Old news'), findsNothing);

      await tester.tap(find.text('Someone liked your post'));
      await tester.pumpAndSettle();
      expect(opened?.id, 1);
      expect(find.text('Notifications'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
