import 'dart:io';

import 'package:app/features/programming/presentation/screens/import_workouts_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('committed docs/sample-wods.csv parses cleanly', () {
    final file = File('../docs/sample-wods.csv');
    expect(file.existsSync(), isTrue, reason: 'sample CSV should be committed');
    final outcome = parseWorkoutsCsv(file.readAsStringSync());
    expect(outcome.headerError, isNull);
    expect(outcome.invalidCount, 0);
    expect(outcome.validCount, 3);
    expect(outcome.canImport, isTrue);
  });

  group('parseWorkoutsCsv', () {
    test('parses valid rows into import payloads', () {
      const csv =
          'date,title,status,section_1_title,section_1_description,section_1_score,'
          'section_2_title,section_2_description,section_2_score\n'
          '2099-06-20,Evening WOD,published,Strength,"Back Squat 5x5",weight,'
          'Metcon,"21-15-9",time\n'
          '2099-06-21,Morning WOD,,Warm Up,"500m row",time,,,';
      final outcome = parseWorkoutsCsv(csv);

      expect(outcome.headerError, isNull);
      expect(outcome.rows, hasLength(2));
      expect(outcome.validCount, 2);
      expect(outcome.invalidCount, 0);
      expect(outcome.canImport, isTrue);

      final first = outcome.rows.first.payload!;
      expect(first['scheduled_date'], '2099-06-20');
      expect(first['title'], 'Evening WOD');
      expect(first['status'], 'published');
      final sections = first['sections'] as List<Map<String, dynamic>>;
      expect(sections, hasLength(2));
      expect(sections.first['title'], 'Strength');
      expect(sections.first['description'], 'Back Squat 5x5');
      expect(sections.first['score_type'], 'weight');

      // An empty status defaults to draft, and blank section columns are
      // skipped instead of producing an empty section.
      final second = outcome.rows[1].payload!;
      expect(second['status'], 'draft');
      expect(second['sections'], hasLength(1));
    });

    test('reports a missing required column', () {
      const csv =
          'date,title,section_1_description\n'
          '2099-06-20,WOD,"500m row"';
      final outcome = parseWorkoutsCsv(csv);
      expect(outcome.headerError, contains('section_1_score'));
      expect(outcome.canImport, isFalse);
    });

    test('rejects an unknown score type', () {
      const csv =
          'date,title,section_1_description,section_1_score\n'
          '2099-06-20,WOD,"21-15-9",stopwatch';
      final outcome = parseWorkoutsCsv(csv);

      expect(outcome.headerError, isNull);
      expect(outcome.validCount, 0);
      expect(outcome.invalidCount, 1);
      expect(outcome.canImport, isFalse);
      expect(
        outcome.rows.first.error,
        contains('time, rounds_reps, or weight'),
      );
    });

    test('rejects an unparseable date and a missing title', () {
      const csv =
          'date,title,section_1_description,section_1_score\n'
          '20-06-2099,WOD,"500m row",time\n'
          '2099-06-21,,"500m row",time';
      final outcome = parseWorkoutsCsv(csv);

      expect(outcome.invalidCount, 2);
      expect(outcome.rows.first.error, contains('YYYY-MM-DD'));
      expect(outcome.rows[1].error, contains('title is required'));
    });

    test('rejects a row whose sections are all blank', () {
      const csv =
          'date,title,section_1_description,section_1_score\n'
          '2099-06-20,WOD,,';
      final outcome = parseWorkoutsCsv(csv);

      expect(outcome.invalidCount, 1);
      expect(outcome.rows.first.error, contains('at least one filled section'));
    });

    test('requires description and score to be set together', () {
      const csv =
          'date,title,section_1_description,section_1_score\n'
          '2099-06-20,WOD,,time';
      final outcome = parseWorkoutsCsv(csv);

      expect(outcome.invalidCount, 1);
      expect(
        outcome.rows.first.error,
        contains('section_1_description is required'),
      );
    });

    test('accepts tab-separated rows pasted from a spreadsheet', () {
      const tsv =
          'date\ttitle\tsection_1_description\tsection_1_score\n'
          '2099-06-20\tEvening WOD\t500m row\ttime';
      final outcome = parseWorkoutsCsv(tsv);

      expect(outcome.headerError, isNull);
      expect(outcome.validCount, 1);
      expect(outcome.canImport, isTrue);
    });

    test('reports an empty paste box and a header without data rows', () {
      expect(parseWorkoutsCsv('   ').headerError, contains('Paste your WOD'));
      expect(
        parseWorkoutsCsv(
          'date,title,section_1_description,section_1_score',
        ).headerError,
        contains('No data rows'),
      );
    });
  });
}
