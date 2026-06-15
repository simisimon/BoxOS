import 'dart:io';

import 'package:app/features/calendar/presentation/screens/import_classes_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('committed docs/sample-classes.csv parses cleanly', () {
    final file = File('../docs/sample-classes.csv');
    expect(file.existsSync(), isTrue, reason: 'sample CSV should be committed');
    final outcome = parseClassesCsv(file.readAsStringSync());
    expect(outcome.headerError, isNull);
    expect(outcome.invalidCount, 0);
    expect(outcome.validCount, 7);
    expect(outcome.canImport, isTrue);
  });

  group('parseClassesCsv', () {
    test('parses valid rows into import payloads', () {
      const csv = 'date,start_time,title,duration_minutes,capacity,repeat,occurrences\n'
          '2099-06-20,18:00,Evening WOD,60,12,weekly,8\n'
          '2099-06-21,07:00,Morning WOD,45,10,,';
      final outcome = parseClassesCsv(csv);

      expect(outcome.headerError, isNull);
      expect(outcome.rows, hasLength(2));
      expect(outcome.validCount, 2);
      expect(outcome.invalidCount, 0);
      expect(outcome.canImport, isTrue);

      final first = outcome.rows.first.payload!;
      expect(first['title'], 'Evening WOD');
      expect(first['duration_minutes'], 60);
      expect(first['capacity'], 12);
      expect(first['recurrence_frequency'], 'weekly');
      expect(first['occurrence_count'], 8);
      expect(first['start_time'], endsWith('Z')); // ISO-8601 UTC

      // Empty repeat/occurrences default to a single non-recurring class.
      final second = outcome.rows[1].payload!;
      expect(second['recurrence_frequency'], 'none');
      expect(second['occurrence_count'], 1);
    });

    test('reports a missing required column', () {
      const csv = 'date,start_time,title,capacity\n'
          '2099-06-20,18:00,WOD,12';
      final outcome = parseClassesCsv(csv);
      expect(outcome.headerError, contains('duration_minutes'));
      expect(outcome.canImport, isFalse);
    });

    test('accepts tab-separated rows pasted from a spreadsheet', () {
      const tsv = 'date\tstart_time\ttitle\tduration_minutes\tcapacity\n'
          '2099-06-20\t18:00\tEvening WOD\t60\t12';
      final outcome = parseClassesCsv(tsv);
      expect(outcome.headerError, isNull);
      expect(outcome.validCount, 1);
      expect(outcome.rows.first.payload!['title'], 'Evening WOD');
    });

    test('flags an invalid row and blocks import', () {
      const csv = 'date,start_time,title,duration_minutes,capacity\n'
          '2099-06-20,18:00,Good,60,12\n'
          '2099-06-21,18:00,Bad,sixty,12';
      final outcome = parseClassesCsv(csv);
      expect(outcome.validCount, 1);
      expect(outcome.invalidCount, 1);
      expect(outcome.rows[1].error, contains('duration_minutes'));
      expect(outcome.canImport, isFalse);
    });

    test('collects section columns into a sections list', () {
      const csv =
          'date,start_time,title,duration_minutes,capacity,'
          'section_1_title,section_1_description,section_1_score,'
          'section_2_title,section_2_description,section_2_score\n'
          '2099-06-20,18:00,Sectioned WOD,60,12,'
          'Warm Up,Foam roll,,Strength,Back Squat 5x5,time';
      final outcome = parseClassesCsv(csv);
      expect(outcome.headerError, isNull);
      expect(outcome.validCount, 1);
      final sections =
          outcome.rows.first.payload!['sections'] as List<dynamic>;
      expect(sections, hasLength(2));
      expect(sections.first, {
        'title': 'Warm Up',
        'description': 'Foam roll',
      });
      expect(sections[1], {
        'title': 'Strength',
        'description': 'Back Squat 5x5',
        'score_type': 'time',
      });
    });

    test('omits sections key when no section columns are populated', () {
      const csv = 'date,start_time,title,duration_minutes,capacity,'
          'section_1_title,section_1_description,section_1_score\n'
          '2099-06-20,18:00,No sections,60,12,,,';
      final outcome = parseClassesCsv(csv);
      expect(outcome.validCount, 1);
      expect(outcome.rows.first.payload!.containsKey('sections'), isFalse);
    });

    test('rejects an unknown section score value', () {
      const csv = 'date,start_time,title,duration_minutes,capacity,'
          'section_1_title,section_1_score\n'
          '2099-06-20,18:00,Bad score,60,12,Strength,calories';
      final outcome = parseClassesCsv(csv);
      expect(outcome.invalidCount, 1);
      expect(outcome.rows.first.error, contains('section_1_score'));
    });
  });
}
