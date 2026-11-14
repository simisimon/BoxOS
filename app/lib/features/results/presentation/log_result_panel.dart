import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_side_panel.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:app/features/results/data/api_results_repository.dart';
import 'package:app/features/results/domain/workout_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What happened in the panel, so the caller can refresh and say so.
enum LogResultOutcome { saved, deleted }

/// Log or edit the signed-in athlete's result on one scored WOD block.
Future<LogResultOutcome?> showLogResultPanel(
  BuildContext context, {
  required DailyWorkoutSection section,
  required String dayLabel,
}) {
  return showAppSidePanel<LogResultOutcome>(
    context,
    builder: (_) => LogResultPanel(section: section, dayLabel: dayLabel),
  );
}

String _number(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

/// One lifted set: reps and kg.
class _LiftRow {
  _LiftRow({String reps = '', String kg = ''})
    : reps = TextEditingController(text: reps),
      kg = TextEditingController(text: kg);

  final TextEditingController reps;
  final TextEditingController kg;

  void dispose() {
    reps.dispose();
    kg.dispose();
  }
}

class LogResultPanel extends ConsumerStatefulWidget {
  const LogResultPanel({
    super.key,
    required this.section,
    required this.dayLabel,
  });

  final DailyWorkoutSection section;
  final String dayLabel;

  @override
  ConsumerState<LogResultPanel> createState() => _LogResultPanelState();
}

class _LogResultPanelState extends ConsumerState<LogResultPanel> {
  WorkoutResult? get _existing => widget.section.myResult;
  bool get _isExercise => widget.section.kind == BlockKind.exercise;
  WorkoutSectionScore get _score => widget.section.scoreType;

  late final _main = TextEditingController(text: _initialMain());
  late final _reps = TextEditingController(text: _initialRoundReps());
  late final _notes = TextEditingController(text: _existing?.notes);
  late ResultDivision _division = _existing?.division ?? ResultDivision.rx;
  late bool _capped = _existing?.timeCapped ?? false;
  late final List<_LiftRow> _lifts = _initialLifts();
  bool _busy = false;
  String? _error;

  String _initialMain() {
    final existing = _existing;
    if (existing == null || _isExercise) return '';
    switch (_score) {
      case WorkoutSectionScore.time:
        return existing.timeCapped
            ? _number(existing.scoreValue)
            : existing.scoreLabel;
      case WorkoutSectionScore.roundsReps:
        return '${existing.scoreValue ~/ 1000}';
      default:
        return _number(existing.scoreValue);
    }
  }

  String _initialRoundReps() {
    final existing = _existing;
    if (existing == null || _score != WorkoutSectionScore.roundsReps) {
      return '';
    }
    return '${existing.scoreValue.toInt() % 1000}';
  }

  List<_LiftRow> _initialLifts() {
    if (!_isExercise) return [];
    final logged = _existing?.sets ?? const <ResultSet>[];
    if (logged.isNotEmpty) {
      return [
        for (final set in logged)
          _LiftRow(
            reps: '${set.reps}',
            kg: set.kg == null ? '' : _number(set.kg!),
          ),
      ];
    }
    final prescribed = widget.section.sets;
    if (prescribed.isEmpty) return [_LiftRow()];
    return [for (final set in prescribed) _LiftRow(reps: '${set.reps}')];
  }

  @override
  void dispose() {
    _main.dispose();
    _reps.dispose();
    _notes.dispose();
    for (final row in _lifts) {
      row.dispose();
    }
    super.dispose();
  }

  ResultDraft? _draft() {
    final sectionId = widget.section.id!;
    final notes = _notes.text.trim();
    if (_isExercise) {
      final sets = <ResultSet>[];
      for (final row in _lifts) {
        final reps = int.tryParse(row.reps.text.trim());
        final kg = double.tryParse(row.kg.text.trim().replaceAll(',', '.'));
        if (reps == null && kg == null) continue;
        if (reps == null || reps < 1) {
          setState(() => _error = 'Every set with a weight needs its reps.');
          return null;
        }
        sets.add(ResultSet(reps: reps, kg: kg));
      }
      if (!sets.any((set) => set.kg != null)) {
        setState(() => _error = 'Enter the weight of at least one set.');
        return null;
      }
      return ResultDraft(
        sectionId: sectionId,
        division: _division,
        sets: sets,
        notes: notes,
      );
    }
    final main = _main.text.trim();
    if (main.isEmpty) {
      setState(() => _error = 'Enter your score.');
      return null;
    }
    final score = _score == WorkoutSectionScore.roundsReps
        ? '$main+${_reps.text.trim().isEmpty ? '0' : _reps.text.trim()}'
        : main;
    return ResultDraft(
      sectionId: sectionId,
      score: score,
      division: _division,
      timeCapped: _score == WorkoutSectionScore.time && _capped,
      notes: notes,
    );
  }

  Future<void> _save() async {
    final draft = _draft();
    if (draft == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(resultsRepositoryProvider).saveResult(draft);
      if (mounted) Navigator.of(context).pop(LogResultOutcome.saved);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessageFrom(error, fallback: 'Could not save the result');
      });
    }
  }

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(resultsRepositoryProvider)
          .deleteResult(sectionId: widget.section.id!);
      if (mounted) Navigator.of(context).pop(LogResultOutcome.deleted);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessageFrom(
          error,
          fallback: 'Could not delete the result',
        );
      });
    }
  }

  Widget _scoreInput() {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final decimals = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    switch (_score) {
      case WorkoutSectionScore.time:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('result-score'),
              controller: _main,
              keyboardType: _capped
                  ? TextInputType.number
                  : TextInputType.datetime,
              inputFormatters: _capped
                  ? digits
                  : [FilteringTextInputFormatter.allow(RegExp(r'[0-9:]'))],
              decoration: InputDecoration(
                labelText: _capped ? 'Reps at the cap' : 'Time',
                hintText: _capped ? '120' : 'mm:ss',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Time capped'),
              subtitle: const Text('Not finished: log the reps you reached.'),
              value: _capped,
              onChanged: (value) => setState(() {
                _capped = value;
                _main.clear();
              }),
            ),
          ],
        );
      case WorkoutSectionScore.roundsReps:
        return Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('result-score'),
                controller: _main,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                decoration: const InputDecoration(labelText: 'Rounds'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: appSpaceMd),
              child: Text('+', style: TextStyle(color: appMutedText)),
            ),
            Expanded(
              child: TextField(
                key: const ValueKey('result-reps'),
                controller: _reps,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                decoration: const InputDecoration(labelText: 'Reps'),
              ),
            ),
          ],
        );
      default:
        final (label, suffix, formatters) = switch (_score) {
          WorkoutSectionScore.reps => ('Reps', 'reps', digits),
          WorkoutSectionScore.calories => ('Calories', 'cal', digits),
          WorkoutSectionScore.distance => ('Distance', 'm', decimals),
          _ => ('Weight', 'kg', decimals),
        };
        return TextField(
          key: const ValueKey('result-score'),
          controller: _main,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: formatters,
          decoration: InputDecoration(labelText: label, suffixText: suffix),
        );
    }
  }

  Widget _liftInput() {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final decimals = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    final prescribed = widget.section.sets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('SETS', style: appMono(fontSize: 10)),
        const SizedBox(height: appSpaceSm),
        for (var i = 0; i < _lifts.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: appSpaceSm),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '${i + 1}.',
                    style: appMono(fontSize: 12, color: appMutedText),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: TextField(
                    key: ValueKey('result-set-reps-$i'),
                    controller: _lifts[i].reps,
                    inputFormatters: digits,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(isDense: true),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: appSpaceSm),
                  child: Text('reps @', style: TextStyle(color: appMutedText)),
                ),
                SizedBox(
                  width: 84,
                  child: TextField(
                    key: ValueKey('result-set-kg-$i'),
                    controller: _lifts[i].kg,
                    inputFormatters: decimals,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(isDense: true),
                  ),
                ),
                const SizedBox(width: appSpaceSm),
                const Text('kg', style: TextStyle(color: appMutedText)),
                if (i < prescribed.length) ...[
                  const SizedBox(width: appSpaceMd),
                  Flexible(
                    child: Text(
                      formatWorkoutSet(prescribed[i], widget.section.setUnit),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: appSubtleText,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _lifts.length >= 30
                ? null
                : () => setState(() => _lifts.add(_LiftRow())),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add set'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final text = const TextStyle(color: appMutedText, height: 1.45);
    return AppSidePanel(
      title: _existing == null ? 'Log result' : 'Edit result',
      subtitle: [
        if (section.title.isNotEmpty) section.title,
        widget.dayLabel,
      ].join(' · '),
      actions: [
        if (_existing != null)
          TextButton(
            onPressed: _busy ? null : _delete,
            style: TextButton.styleFrom(foregroundColor: appDanger),
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (section.description.trim().isNotEmpty)
            Text(section.description.trim(), style: text),
          if (section.memberNotes.trim().isNotEmpty) ...[
            const SizedBox(height: appSpaceSm),
            Text(
              section.memberNotes.trim(),
              style: text.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: appSpaceLg),
          if (_isExercise) _liftInput() else _scoreInput(),
          const SizedBox(height: appSpaceLg),
          SegmentedButton<ResultDivision>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ResultDivision.rx, label: Text('Rx')),
              ButtonSegment(
                value: ResultDivision.scaled,
                label: Text('Scaled'),
              ),
            ],
            selected: {_division},
            onSelectionChanged: (s) => setState(() => _division = s.first),
          ),
          const SizedBox(height: appSpaceLg),
          TextField(
            controller: _notes,
            maxLength: 500,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              hintText: 'Scaling used, how it felt',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: appSpaceMd),
            Text(_error!, style: const TextStyle(color: appDanger)),
          ],
        ],
      ),
    );
  }
}
