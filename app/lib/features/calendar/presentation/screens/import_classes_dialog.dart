import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/repositories/schedule_repository.dart';
import 'package:app/features/calendar/presentation/screens/csv_file_picker.dart';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _requiredHeaders = [
  'date',
  'start_time',
  'title',
  'duration_minutes',
  'capacity',
];
const _allowedRepeats = {'none', 'daily', 'weekly', 'monthly'};

/// Example the user can drop into the paste box as a starting point.
const importTemplateCsv =
    'date,start_time,title,duration_minutes,capacity,trainer_email,wod_description,repeat,occurrences\n'
    '2026-06-22,18:00,Evening WOD,60,12,coach@yourbox.app,"Fran 21-15-9",weekly,8';

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

/// Parses pasted class data into a preview. Accepts comma-separated (CSV) or
/// tab-separated (e.g. cells copied from Google Sheets / Excel) content. Each
/// row's date+time are read in the device's local zone and serialized to UTC
/// (matching the manual create form).
CsvParseOutcome parseClassesCsv(String content) {
  final normalized =
      content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (normalized.isEmpty) {
    return CsvParseOutcome(headerError: 'Paste your class rows above.');
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
    return CsvParseOutcome(headerError: 'Paste your class rows above.');
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

  final previews = <ImportRowPreview>[];
  for (var r = 1; r < table.length; r++) {
    final row = table[r];
    if (row.every((c) => c.toString().trim().isEmpty)) {
      continue;
    }
    final line = r + 1;
    final dateStr = cell(row, 'date');
    final timeStr = cell(row, 'start_time');
    final title = cell(row, 'title');
    final summary =
        '$dateStr $timeStr · ${title.isEmpty ? '(no title)' : title}';
    try {
      final start = _parseLocalDateTime(dateStr, timeStr);
      if (title.isEmpty) {
        throw const FormatException('title is required');
      }
      final duration = int.tryParse(cell(row, 'duration_minutes'));
      if (duration == null) {
        throw const FormatException('duration_minutes must be a whole number');
      }
      final capacity = int.tryParse(cell(row, 'capacity'));
      if (capacity == null) {
        throw const FormatException('capacity must be a whole number');
      }
      final repeatCell = cell(row, 'repeat').toLowerCase();
      final repeat = repeatCell.isEmpty ? 'none' : repeatCell;
      if (!_allowedRepeats.contains(repeat)) {
        throw const FormatException(
          'repeat must be none, daily, weekly, or monthly',
        );
      }
      final occCell = cell(row, 'occurrences');
      final occurrences = repeat == 'none'
          ? 1
          : int.tryParse(occCell.isEmpty ? '1' : occCell);
      if (occurrences == null) {
        throw const FormatException('occurrences must be a whole number');
      }
      final classType = cell(row, 'class_type');
      previews.add(
        ImportRowPreview(
          line: line,
          summary: summary,
          payload: {
            'start_time': start.toUtc().toIso8601String(),
            'title': title,
            if (classType.isNotEmpty) 'class_type': classType,
            'duration_minutes': duration,
            'capacity': capacity,
            if (cell(row, 'trainer_email').isNotEmpty)
              'trainer_email': cell(row, 'trainer_email'),
            'wod_description': cell(row, 'wod_description'),
            'recurrence_frequency': repeat,
            'occurrence_count': occurrences,
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

DateTime _parseLocalDateTime(String date, String time) {
  final day = DateTime.tryParse(date);
  if (day == null) {
    throw const FormatException('date must be YYYY-MM-DD');
  }
  final parts = time.split(':');
  final hour = parts.isEmpty ? null : int.tryParse(parts[0].trim());
  final minute = parts.length < 2 ? null : int.tryParse(parts[1].trim());
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    throw const FormatException('start_time must be HH:MM (24h)');
  }
  return DateTime(day.year, day.month, day.day, hour, minute);
}

/// Dialog to bulk-import classes by pasting CSV / spreadsheet rows. Parses and
/// previews locally, then sends valid rows to the atomic backend endpoint.
/// Plugin-free (no file picker) so it works the same on web, desktop and mobile.
class ImportClassesDialog extends ConsumerStatefulWidget {
  const ImportClassesDialog({super.key, this.debugInitialText});

  /// Pre-fills the paste box — for tests/screenshots.
  @visibleForTesting
  final String? debugInitialText;

  @override
  ConsumerState<ImportClassesDialog> createState() =>
      _ImportClassesDialogState();
}

class _ImportClassesDialogState extends ConsumerState<ImportClassesDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.debugInitialText ?? '');
  CsvParseOutcome? _outcome;
  bool _importing = false;
  List<ScheduleImportError> _serverErrors = const [];

  @override
  void initState() {
    super.initState();
    if (_controller.text.trim().isNotEmpty) {
      _outcome = parseClassesCsv(_controller.text);
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
      _outcome = value.trim().isEmpty ? null : parseClassesCsv(value);
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
      final result =
          await ref.read(scheduleRepositoryProvider).importClasses(payloads);
      if (!mounted) {
        return;
      }
      if (result.hasErrors) {
        setState(() => _serverErrors = result.errors);
        return;
      }
      ref.invalidate(scheduleListProvider);
      Navigator.of(context).pop(true);
      _showSnackBar('Imported ${result.createdCount} classes.');
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
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outcome = _outcome;
    return AlertDialog(
      scrollable: true,
      backgroundColor: appSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: appBorder),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Import classes',
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
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Upload a .csv file or paste rows from a spreadsheet '
              '(Google Sheets / Excel). Comma- and tab-separated are both '
              'accepted. Required columns: date, start_time, title, '
              'duration_minutes, capacity. Optional: class_type, trainer_email, '
              'wod_description, repeat, occurrences. The file is checked against '
              'this schema before anything is imported.',
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
                hintText: 'date,start_time,title,duration_minutes,capacity\n'
                    '2026-06-22,18:00,Evening WOD,60,12',
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
          onPressed:
              _importing ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              (outcome?.canImport ?? false) && !_importing ? _import : null,
          child: _importing
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  outcome == null
                      ? 'Import'
                      : 'Import ${outcome.validCount} classes',
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
        borderRadius: BorderRadius.circular(12),
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
                    style: theme.textTheme.bodySmall?.copyWith(color: appDanger),
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
        borderRadius: BorderRadius.circular(12),
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
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: appText),
            ),
          ),
        ],
      ),
    );
  }
}
