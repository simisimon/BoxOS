import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/features/calendar/presentation/screens/csv_file_picker.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/repositories/programming_repository.dart';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _requiredHeaders = [
  'date',
  'title',
  'section_1_description',
  'section_1_score',
];
const _allowedStatuses = {'draft', 'published'};
const _allowedSectionScores = {'time', 'rounds_reps', 'weight'};
const _maxSectionsPerRow = 20;

final _sectionDescriptionColumnPattern =
    RegExp(r'^section_(\d+)_description$');

/// Example the user can drop into the paste box as a starting point.
const importTemplateCsv =
    'date,title,status,section_1_title,section_1_description,section_1_score,'
    'section_2_title,section_2_description,section_2_score\n'
    '2026-06-22,Murph,published,Warm Up,"500m row + dynamic stretching",time,'
    'Strength,"Back Squat 5x5 @ 75%",weight';

/// One parsed row, either ready to import ([payload] set) or rejected
/// ([error] set).
class ImportRowPreview {
  ImportRowPreview({
    required this.line,
    required this.summary,
    this.payload,
    this.error,
  });

  final int line;
  final String summary;
  final Map<String, dynamic>? payload;
  final String? error;

  bool get isValid => payload != null && error == null;
}

class CsvParseOutcome {
  CsvParseOutcome({this.headerError, this.rows = const []});

  final String? headerError;
  final List<ImportRowPreview> rows;

  int get validCount => rows.where((r) => r.isValid).length;
  int get invalidCount => rows.where((r) => !r.isValid).length;

  /// The backend import is atomic, so we only allow it when every row is valid.
  bool get canImport =>
      headerError == null && rows.isNotEmpty && invalidCount == 0;
}

/// Parses pasted WOD data into a preview. Accepts comma- or tab-separated
/// content. Each row produces a `{ scheduled_date, title, status?, sections }`
/// payload matching `POST /programming/workouts/import`.
CsvParseOutcome parseWorkoutsCsv(String content) {
  final normalized =
      content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (normalized.isEmpty) {
    return CsvParseOutcome(headerError: 'Paste your WOD rows above.');
  }

  // Auto-detect the delimiter from the header line: tabs win when a spreadsheet
  // range was copied, otherwise default to comma.
  final firstLine = normalized.split('\n').first;
  final tabs = '\t'.allMatches(firstLine).length;
  final commas = ','.allMatches(firstLine).length;
  final delimiter = tabs > 0 && tabs >= commas ? '\t' : ',';

  final table = CsvToListConverter(
    eol: '\n',
    fieldDelimiter: delimiter,
    shouldParseNumbers: false,
  ).convert(normalized);
  if (table.isEmpty) {
    return CsvParseOutcome(headerError: 'Paste your WOD rows above.');
  }

  final header =
      table.first.map((c) => c.toString().trim().toLowerCase()).toList();
  final indexOf = <String, int>{};
  for (var i = 0; i < header.length; i++) {
    indexOf[header[i]] = i;
  }
  final missing =
      _requiredHeaders.where((h) => !indexOf.containsKey(h)).toList();
  if (missing.isNotEmpty) {
    return CsvParseOutcome(
      headerError: 'Missing required column(s): ${missing.join(', ')}. '
          'The first row must be the header.',
    );
  }

  String cell(List<dynamic> row, String name) {
    final i = indexOf[name];
    if (i == null || i >= row.length) return '';
    return row[i].toString().trim();
  }

  // Detect which section indices (1-based) the header carries by scanning the
  // section_N_description columns. Section_1 is required (enforced via the
  // header check above), additional sections are opt-in per WOD.
  final sectionIndices = <int>[];
  for (final column in indexOf.keys) {
    final match = _sectionDescriptionColumnPattern.firstMatch(column);
    if (match == null) continue;
    final parsed = int.tryParse(match.group(1) ?? '');
    if (parsed == null || parsed < 1 || parsed > _maxSectionsPerRow) continue;
    if (!sectionIndices.contains(parsed)) sectionIndices.add(parsed);
  }
  sectionIndices.sort();

  final previews = <ImportRowPreview>[];
  for (var r = 1; r < table.length; r++) {
    final row = table[r];
    if (row.every((c) => c.toString().trim().isEmpty)) {
      continue;
    }
    final line = r + 1;
    final dateStr = cell(row, 'date');
    final title = cell(row, 'title');
    final summary = '$dateStr · ${title.isEmpty ? '(no title)' : title}';
    try {
      if (DateTime.tryParse(dateStr) == null) {
        throw const FormatException('date must be YYYY-MM-DD');
      }
      if (title.isEmpty) {
        throw const FormatException('title is required');
      }
      final statusCell = cell(row, 'status').toLowerCase();
      final status = statusCell.isEmpty ? 'draft' : statusCell;
      if (!_allowedStatuses.contains(status)) {
        throw const FormatException('status must be draft or published');
      }
      final sections = <Map<String, dynamic>>[];
      for (final sectionIndex in sectionIndices) {
        final description =
            cell(row, 'section_${sectionIndex}_description');
        final scoreRaw =
            cell(row, 'section_${sectionIndex}_score').toLowerCase();
        if (description.isEmpty && scoreRaw.isEmpty) continue;
        if (description.isEmpty) {
          throw FormatException(
            'section_${sectionIndex}_description is required when '
            'section_${sectionIndex}_score is set',
          );
        }
        if (scoreRaw.isEmpty) {
          throw FormatException(
            'section_${sectionIndex}_score is required when '
            'section_${sectionIndex}_description is set',
          );
        }
        if (!_allowedSectionScores.contains(scoreRaw)) {
          throw FormatException(
            'section_${sectionIndex}_score must be time, rounds_reps, or weight',
          );
        }
        sections.add({
          'title': cell(row, 'section_${sectionIndex}_title'),
          'description': description,
          'score_type': scoreRaw,
        });
      }
      if (sections.isEmpty) {
        throw const FormatException(
          'A WOD needs at least one filled section',
        );
      }
      previews.add(
        ImportRowPreview(
          line: line,
          summary: '$summary · ${sections.length} section'
              '${sections.length == 1 ? '' : 's'}',
          payload: {
            'scheduled_date': dateStr,
            'title': title,
            'status': status,
            'sections': sections,
          },
        ),
      );
    } on FormatException catch (error) {
      previews.add(
        ImportRowPreview(line: line, summary: summary, error: error.message),
      );
    }
  }

  if (previews.isEmpty) {
    return CsvParseOutcome(
      headerError: 'No data rows found below the header.',
    );
  }
  return CsvParseOutcome(rows: previews);
}

/// Dialog to bulk-import WODs by pasting CSV / spreadsheet rows. Parses and
/// previews locally, then sends valid rows to the atomic backend endpoint.
class ImportWorkoutsDialog extends ConsumerStatefulWidget {
  const ImportWorkoutsDialog({super.key, this.debugInitialText});

  /// Pre-fills the paste box — for tests/screenshots.
  @visibleForTesting
  final String? debugInitialText;

  @override
  ConsumerState<ImportWorkoutsDialog> createState() =>
      _ImportWorkoutsDialogState();
}

class _ImportWorkoutsDialogState extends ConsumerState<ImportWorkoutsDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.debugInitialText ?? '');
  CsvParseOutcome? _outcome;
  bool _importing = false;
  List<WorkoutImportError> _serverErrors = const [];

  @override
  void initState() {
    super.initState();
    if (_controller.text.trim().isNotEmpty) {
      _outcome = parseWorkoutsCsv(_controller.text);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {
      _serverErrors = const [];
      _outcome = value.trim().isEmpty ? null : parseWorkoutsCsv(value);
    });
  }

  void _insertTemplate() {
    _controller.text = importTemplateCsv;
    _onChanged(_controller.text);
  }

  Future<void> _uploadFile() async {
    try {
      final content = await pickCsvFileContent();
      if (content == null || !mounted) {
        return;
      }
      _controller.text = content;
      _onChanged(content);
    } catch (error) {
      if (mounted) {
        _showSnackBar(
          errorMessageFrom(error, fallback: 'Could not read the file.'),
        );
      }
    }
  }

  Future<void> _import() async {
    final outcome = _outcome;
    if (outcome == null || !outcome.canImport || _importing) {
      return;
    }
    final payloads = [
      for (final row in outcome.rows)
        if (row.isValid) row.payload!,
    ];
    setState(() {
      _importing = true;
      _serverErrors = const [];
    });
    try {
      final result = await ref
          .read(programmingRepositoryProvider)
          .importWorkouts(payloads);
      if (!mounted) {
        return;
      }
      if (result.hasErrors) {
        setState(() => _serverErrors = result.errors);
        return;
      }
      ref.invalidate(programmingListProvider);
      Navigator.of(context).pop(true);
      _showSnackBar('Imported ${result.createdCount} WODs.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(errorMessageFrom(error, fallback: 'Import failed.'));
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outcome = _outcome;
    return AlertDialog(
      scrollable: true,
      backgroundColor: appSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: appBorder),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Import WODs',
              style: theme.textTheme.titleLarge?.copyWith(
                color: appText,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.close_rounded, color: appText),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Upload a .csv file or paste rows from a spreadsheet '
              '(Google Sheets / Excel). Comma- and tab-separated are both '
              'accepted. Required columns: date, title, section_1_description, '
              'section_1_score. Optional: status (draft/published), additional '
              'section_N_title / section_N_description / section_N_score '
              '(N = 1..20, score = time, rounds_reps, or weight). The file is '
              'checked before anything is imported.',
              style: theme.textTheme.bodySmall?.copyWith(color: appSubtleText),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              onChanged: _onChanged,
              minLines: 5,
              maxLines: 8,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                color: appText,
              ),
              decoration: const InputDecoration(
                hintText: 'date,title,section_1_description,section_1_score\n'
                    '2026-06-22,Murph,"21-15-9 thrusters/pull-ups",time',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                children: [
                  if (canUploadCsv)
                    FilledButton.tonalIcon(
                      onPressed: _uploadFile,
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: const Text('Upload CSV file'),
                    ),
                  TextButton.icon(
                    onPressed: _insertTemplate,
                    icon: const Icon(Icons.playlist_add_rounded, size: 18),
                    label: const Text('Insert example'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        const ClipboardData(text: importTemplateCsv),
                      );
                      _showSnackBar('Template copied to clipboard.');
                    },
                    icon: const Icon(Icons.content_copy_rounded, size: 18),
                    label: const Text('Copy template'),
                  ),
                ],
              ),
            ),
            if (outcome?.headerError != null)
              _MessageCard(
                icon: Icons.error_outline_rounded,
                color: appDanger,
                message: outcome!.headerError!,
              )
            else if (outcome != null) ...[
              const SizedBox(height: 4),
              Text(
                '${outcome.validCount} ready to import'
                '${outcome.invalidCount > 0 ? ' · ${outcome.invalidCount} with errors' : ''}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: appText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              for (final row in outcome.rows) ...[
                _RowTile(row: row),
                const SizedBox(height: 6),
              ],
            ],
            if (_serverErrors.isNotEmpty)
              _MessageCard(
                icon: Icons.error_outline_rounded,
                color: appDanger,
                message: _serverErrors
                    .map((e) => 'Row ${e.row}: ${e.message}')
                    .join('\n'),
              ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      actions: [
        TextButton(
          onPressed: _importing
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (outcome?.canImport ?? false) && !_importing
              ? _import
              : null,
          child: _importing
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  outcome == null
                      ? 'Import'
                      : 'Import ${outcome.validCount} WODs',
                ),
        ),
      ],
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row});

  final ImportRowPreview row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valid = row.isValid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: appSurfaceAlt,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: appBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            valid ? Icons.check_circle_rounded : Icons.error_rounded,
            size: 18,
            color: valid ? appSuccess : appDanger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.summary,
                  style: theme.textTheme.bodyMedium?.copyWith(color: appText),
                ),
                if (!valid && row.error != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Line ${row.line}: ${row.error}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: appDanger,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: appSurfaceAlt,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: appText),
            ),
          ),
        ],
      ),
    );
  }
}
