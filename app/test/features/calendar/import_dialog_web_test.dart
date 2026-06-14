@TestOn('browser')
library;

import 'package:app/features/calendar/presentation/screens/import_classes_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ImportClassesDialog builds and parses on web', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ImportClassesDialog())),
      ),
    );
    await tester.pump();
    expect(find.text('Import classes'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'date,start_time,title,duration_minutes,capacity\n'
      '2099-06-20,18:00,Alpha,60,12',
    );
    await tester.pump();
    expect(find.textContaining('ready to import'), findsOneWidget);
  });
}
