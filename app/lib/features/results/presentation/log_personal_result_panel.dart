import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_form_dialog.dart';
import 'package:app/core/presentation/app_side_panel.dart';
import 'package:app/features/programming/data/repositories/api_programming_lookup.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:app/features/programming/presentation/widgets/block_editor_panel.dart';
import 'package:app/features/results/data/api_results_repository.dart';
import 'package:app/features/results/domain/workout_result.dart';
import 'package:app/features/results/presentation/log_result_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Log (or, with [existing], edit) a result in the athlete's own logbook:
/// a benchmark, a lift, or a workout of their own. Personal results count
/// for history and PRs but never show on a gym leaderboard.
Future<LogResultOutcome?> showLogPersonalResultPanel(
  BuildContext context, {
  WorkoutResult? existing,
}) {
  return showAppSidePanel<LogResultOutcome>(
    context,
    builder: (_) => LogPersonalResultPanel(existing: existing),
  );
}

String _number(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

const _customScores = [
  WorkoutSectionScore.time,
  WorkoutSectionScore.roundsReps,
  WorkoutSectionScore.reps,
  WorkoutSectionScore.weight,
  WorkoutSectionScore.calories,
  WorkoutSectionScore.distance,
];

class _SetRow {
  _SetRow({String reps = '', String kg = ''})
    : reps = TextEditingController(text: reps),
      kg = TextEditingController(text: kg);

  final TextEditingController reps;
  final TextEditingController kg;

  void dispose() {
    reps.dispose();
    kg.dispose();
  }
}

class LogPersonalResultPanel extends ConsumerStatefulWidget {
  const LogPersonalResultPanel({super.key, this.existing});

  final WorkoutResult? existing;

  @override
  ConsumerState<LogPersonalResultPanel> createState() =>
      _LogPersonalResultPanelState();
}

class _LogPersonalResultPanelState
    extends ConsumerState<LogPersonalResultPanel> {
  WorkoutResult? get _existing => widget.existing;

  late PersonalKind _kind = _initialKind();
  String? _benchmarkId;
  bool _benchmarkMatched = false;
  late final _movement = TextEditingController(
    text: _kind == PersonalKind.movement ? _existing?.sectionTitle : '',
  );
  final _movementFocus = FocusNode();
  late final _title = TextEditingController(
    text: _kind == PersonalKind.custom ? _existing?.sectionTitle : '',
  );
  late final _description = TextEditingController(
    text: _kind == PersonalKind.custom ? _existing?.description : '',
  );
  late WorkoutSectionScore _customScore = _kind == PersonalKind.custom
      ? parseWorkoutSectionScore(_existing?.scoreType)
      : WorkoutSectionScore.time;
  late DateTime _day =
      _existing?.performedOn ?? DateUtils.dateOnly(DateTime.now());
  late final _main = TextEditingController();
  late final _reps = TextEditingController();
  late final _notes = TextEditingController(text: _existing?.notes);
  late ResultDivision _division = _existing?.division ?? ResultDivision.rx;
  late bool _capped = _existing?.timeCapped ?? false;
  late final List<_SetRow> _sets = _initialSets();
  bool _busy = false;
  String? _error;

  PersonalKind _initialKind() {
    final existing = _existing;
    if (existing == null) return PersonalKind.benchmark;
    if (existing.movementId != null) return PersonalKind.movement;
    // A benchmark or the athlete's own; settled once the catalog loads.
    return existing.description.isEmpty
        ? PersonalKind.custom
        : PersonalKind.benchmark;
  }

  List<_SetRow> _initialSets() {
    final logged = _existing?.sets ?? const <ResultSet>[];
    if (logged.isEmpty) return [_SetRow()];
    return [
      for (final set in logged)
        _SetRow(
          reps: '${set.reps}',
          kg: set.kg == null ? '' : _number(set.kg!),
        ),
    ];
  }

  @override
  void initState() {
    super.initState();
    final existing = _existing;
    if (existing != null && existing.movementId == null) {
      final score = parseWorkoutSectionScore(existing.scoreType);
      if (existing.timeCapped || score != WorkoutSectionScore.time) {
        _main.text = score == WorkoutSectionScore.roundsReps
            ? '${existing.scoreValue ~/ 1000}'
            : _number(existing.scoreValue);
      } else {
        _main.text = existing.scoreLabel;
      }
      if (score == WorkoutSectionScore.roundsReps) {
        _reps.text = '${existing.scoreValue.toInt() % 1000}';
      }
    }
  }

  @override
  void dispose() {
    _movement.dispose();
    _movementFocus.dispose();
    _title.dispose();
    _description.dispose();
    _main.dispose();
    _reps.dispose();
    _notes.dispose();
    for (final row in _sets) {
      row.dispose();
    }
    super.dispose();
  }

  /// Once the catalog is in: the benchmark an edited result was, or the
  /// athlete's own workout when no benchmark has its name.
  void _matchExisting(List<Benchmark> benchmarks) {
    if (_benchmarkMatched) return;
    _benchmarkMatched = true;
    final existing = _existing;
    if (existing == null || existing.movementId != null) return;
    final name = existing.workoutName.toLowerCase();
    final match = benchmarks.where((b) => b.name.toLowerCase() == name);
    if (match.isNotEmpty) {
      _kind = PersonalKind.benchmark;
      _benchmarkId = match.first.id;
    } else if (_kind == PersonalKind.benchmark) {
      _kind = PersonalKind.custom;
      _title.text = existing.sectionTitle;
      _description.text = existing.description;
      _customScore = parseWorkoutSectionScore(existing.scoreType);
    }
  }

  WorkoutSectionScore? _scoreType(List<Benchmark> benchmarks) {
    switch (_kind) {
      case PersonalKind.movement:
        return null;
      case PersonalKind.custom:
        return _customScore;
      case PersonalKind.benchmark:
        final benchmark = benchmarks.where((b) => b.id == _benchmarkId);
        if (benchmark.isEmpty) return null;
        return parseWorkoutSectionScore(benchmark.first.scoreType);
    }
  }

  PersonalResultDraft? _draft(List<Benchmark> benchmarks) {
    final notes = _notes.text.trim();
    switch (_kind) {
      case PersonalKind.movement:
        final name = _movement.text.trim();
        if (name.isEmpty) return _fail('Pick a movement.');
        final sets = <ResultSet>[];
        for (final row in _sets) {
          final reps = int.tryParse(row.reps.text.trim());
          final kg = double.tryParse(row.kg.text.trim().replaceAll(',', '.'));
          if (reps == null && kg == null) continue;
          if (reps == null || reps < 1) {
            return _fail('Every set with a weight needs its reps.');
          }
          sets.add(ResultSet(reps: reps, kg: kg));
        }
        if (!sets.any((set) => set.kg != null)) {
          return _fail('Enter the weight of at least one set.');
        }
        return PersonalResultDraft(
          kind: _kind,
          performedOn: _day,
          movementName: name,
          division: _division,
          sets: sets,
          notes: notes,
        );
      case PersonalKind.benchmark:
      case PersonalKind.custom:
        final scoreType = _scoreType(benchmarks);
        if (_kind == PersonalKind.benchmark && scoreType == null) {
          return _fail('Pick a benchmark.');
        }
        if (_kind == PersonalKind.custom && _title.text.trim().isEmpty) {
          return _fail('Give your workout a name.');
        }
        final score = ResultScoreFields.typed(scoreType!, _main, _reps);
        if (score == null) return _fail('Enter your score.');
        return PersonalResultDraft(
          kind: _kind,
          performedOn: _day,
          benchmarkId: _kind == PersonalKind.benchmark ? _benchmarkId : null,
          title: _kind == PersonalKind.custom ? _title.text.trim() : null,
          description: _kind == PersonalKind.custom
              ? _description.text.trim()
              : null,
          scoreType: _kind == PersonalKind.custom
              ? workoutSectionScoreToWire(scoreType)
              : null,
          score: score,
          division: _division,
          timeCapped: scoreType == WorkoutSectionScore.time && _capped,
          notes: notes,
        );
    }
  }

  PersonalResultDraft? _fail(String message) {
    setState(() => _error = message);
    return null;
  }

  Future<void> _save(List<Benchmark> benchmarks) async {
    final draft = _draft(benchmarks);
    if (draft == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await ref
          .read(resultsRepositoryProvider)
          .savePersonalResult(draft, resultId: _existing?.id);
      if (mounted) {
        Navigator.of(
          context,
        ).pop(saved.isPr ? LogResultOutcome.savedPr : LogResultOutcome.saved);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessageFrom(error, fallback: 'Could not save the result');
      });
    }
  }

  Future<void> _delete() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Delete this result?',
      message: 'It leaves your logbook, history and PRs.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(resultsRepositoryProvider)
          .deletePersonalResult(_existing!.id);
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

  Future<void> _pickDay() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _day.isAfter(today) ? today : _day,
      firstDate: DateTime(2000),
      lastDate: today,
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<Iterable<String>> _searchMovements(String query) async {
    if (query.trim().length < 2) return const [];
    try {
      return await ref
          .read(programmingLookupProvider)
          .movementNames(query.trim());
    } catch (_) {
      return const [];
    }
  }

  Widget _benchmarkPicker(List<Benchmark> benchmarks) {
    final selected = benchmarks.where((b) => b.id == _benchmarkId).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('benchmark-$_benchmarkId'),
          initialValue: selected?.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Benchmark'),
          items: [
            for (final benchmark in benchmarks)
              DropdownMenuItem(
                value: benchmark.id,
                child: Text('${benchmark.name} · ${benchmark.categoryLabel}'),
              ),
          ],
          onChanged: (id) => setState(() {
            if (id == _benchmarkId) return;
            _benchmarkId = id;
            _main.clear();
            _reps.clear();
            _capped = false;
            _error = null;
          }),
        ),
        if (selected != null && selected.description.isNotEmpty) ...[
          const SizedBox(height: appSpaceSm),
          Text(
            selected.description,
            style: const TextStyle(color: appMutedText, height: 1.45),
          ),
        ],
      ],
    );
  }

  Widget _customFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('personal-title'),
          controller: _title,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'e.g. Hotel Chain, Row test',
            helperText: 'Workouts with the same name are compared.',
            counterText: '',
          ),
        ),
        const SizedBox(height: appSpaceMd),
        TextField(
          controller: _description,
          maxLength: 2000,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Workout (optional)',
            hintText: '5 rounds\n400 m run\n20 burpees',
            alignLabelWithHint: true,
            counterText: '',
          ),
        ),
        const SizedBox(height: appSpaceMd),
        DropdownButtonFormField<WorkoutSectionScore>(
          key: ValueKey(_customScore),
          initialValue: _customScore,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Score'),
          items: [
            for (final score in _customScores)
              DropdownMenuItem(
                value: score,
                child: Text(workoutSectionScoreLabel(score)),
              ),
          ],
          onChanged: (score) => setState(() {
            if (score == null || score == _customScore) return;
            _customScore = score;
            _main.clear();
            _reps.clear();
            _capped = false;
          }),
        ),
      ],
    );
  }

  Widget _setsInput() {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final decimals = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('SETS', style: appMono(fontSize: 10)),
        const SizedBox(height: appSpaceSm),
        for (var i = 0; i < _sets.length; i++)
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
                    key: ValueKey('personal-set-reps-$i'),
                    controller: _sets[i].reps,
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
                    key: ValueKey('personal-set-kg-$i'),
                    controller: _sets[i].kg,
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
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _sets.length >= 30
                ? null
                : () => setState(() => _sets.add(_SetRow())),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add set'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final benchmarksAsync = ref.watch(benchmarksProvider);
    final benchmarks = benchmarksAsync.value ?? const <Benchmark>[];
    if (benchmarksAsync.hasValue) _matchExisting(benchmarks);
    final scoreType = _scoreType(benchmarks);
    final localizations = MaterialLocalizations.of(context);
    return AppSidePanel(
      title: _existing == null ? 'Log workout' : 'Edit workout',
      subtitle: 'Your logbook · not on gym leaderboards',
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
          onPressed: _busy ? null : () => _save(benchmarks),
          child: const Text('Save'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<PersonalKind>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: PersonalKind.benchmark,
                label: Text('Benchmark'),
              ),
              ButtonSegment(value: PersonalKind.movement, label: Text('Lift')),
              ButtonSegment(
                value: PersonalKind.custom,
                label: Text('Own workout'),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() {
              _kind = s.first;
              _main.clear();
              _reps.clear();
              _capped = false;
              _error = null;
            }),
          ),
          const SizedBox(height: appSpaceLg),
          InkWell(
            onTap: _pickDay,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Day',
                suffixIcon: Icon(Icons.event_rounded),
              ),
              child: Text(localizations.formatMediumDate(_day)),
            ),
          ),
          const SizedBox(height: appSpaceLg),
          switch (_kind) {
            PersonalKind.benchmark =>
              benchmarksAsync.hasError
                  ? const Text(
                      'Could not load the benchmarks.',
                      style: TextStyle(color: appDanger),
                    )
                  : benchmarksAsync.hasValue
                  ? _benchmarkPicker(benchmarks)
                  : const LinearProgressIndicator(),
            PersonalKind.movement => SuggestionField(
              controller: _movement,
              focusNode: _movementFocus,
              search: _searchMovements,
              labelText: 'Movement',
              hintText: 'Search movements, e.g. Back Squat',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
            ),
            PersonalKind.custom => _customFields(),
          },
          const SizedBox(height: appSpaceLg),
          if (_kind == PersonalKind.movement)
            _setsInput()
          else if (scoreType != null)
            ResultScoreFields(
              score: scoreType,
              main: _main,
              reps: _reps,
              capped: _capped,
              onCappedChanged: (value) => setState(() => _capped = value),
            ),
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
