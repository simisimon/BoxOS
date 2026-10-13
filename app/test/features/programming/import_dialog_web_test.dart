@TestOn('browser')
library;

import 'package:app/features/programming/presentation/screens/import_workouts_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ImportWorkoutsDialog builds and parses on web', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ImportWorkoutsDialog())),
      ),
    );
    await tester.pump();
    expect(find.text('Import WODs'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'date,title,section_1_description,section_1_score\n'
      '2099-06-20,Alpha,"500m row",time',
    );
    await tester.pump();
    expect(find.textContaining('ready to import'), findsOneWidget);
  });
}
