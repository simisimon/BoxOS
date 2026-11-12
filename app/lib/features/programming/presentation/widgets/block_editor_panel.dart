import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_side_panel.dart';
import 'package:app/features/logbook/data/repositories/api_exercise_repository.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Create / edit block panel (docs/admin-ui-reference.md §3.1). Resolves to
/// the block on save, null on cancel; saving the WOD is left to the caller.
Future<DailyWorkoutSection?> showBlockEditorPanel(
  BuildContext context, {
  DailyWorkoutSection? existing,
  required String dayLabel,
}) {
  return showAppSidePanel<DailyWorkoutSection>(
    context,
    builder: (_) => _BlockEditor(existing: existing, dayLabel: dayLabel),
  );
}

/// One editable set row; the panel always keeps one empty row at the end.
class _SetRow {
  _SetRow({String reps = '', String value = ''})
    : reps = TextEditingController(text: reps),
      value = TextEditingController(text: value);

  final TextEditingController reps;
  final TextEditingController value;

  bool get isEmpty => reps.text.trim().isEmpty && value.text.trim().isEmpty;

  /// Null when the row is empty or its reps are not a whole number.
  WorkoutSet? toSet() {
    final count = int.tryParse(reps.text.trim());
    if (count == null || count < 1) return null;
    return WorkoutSet(
      reps: count,
      value: double.tryParse(value.text.trim().replaceAll(',', '.')),
    );
  }

  void dispose() {
    reps.dispose();
    value.dispose();
  }
}

String _number(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

class _BlockEditor extends ConsumerStatefulWidget {
  const _BlockEditor({required this.existing, required this.dayLabel});

  final DailyWorkoutSection? existing;
  final String dayLabel;

  @override
  ConsumerState<_BlockEditor> createState() => _BlockEditorState();
}

class _BlockEditorState extends ConsumerState<_BlockEditor> {
  late final _name = TextEditingController(text: widget.existing?.title);
  late final _text = TextEditingController(
    text: widget.existing?.kind == BlockKind.workout
        ? widget.existing?.description
        : '',
  );
  late final _exercise = TextEditingController(
    text: widget.existing?.exerciseName,
  );
  late final _coachNotes = TextEditingController(
    text: widget.existing?.coachNotes,
  );
  late final _memberNotes = TextEditingController(
    text: widget.existing?.memberNotes,
  );
  final _magic = TextEditingController();
  final _exerciseFocus = FocusNode();
  late BlockKind _kind = widget.existing?.kind ?? BlockKind.workout;
  late SetUnit _unit = widget.existing?.setUnit ?? SetUnit.percent;
  late WorkoutSectionScore _score =
      widget.existing?.scoreType ?? WorkoutSectionScore.time;
  late bool _showCoachNotes = _coachNotes.text.isNotEmpty;
  late bool _showMemberNotes = _memberNotes.text.isNotEmpty;
  bool _showMagic = false;
  String? _error;
  late final List<_SetRow> _rows = [
    for (final set in widget.existing?.sets ?? const <WorkoutSet>[])
      _SetRow(
        reps: '${set.reps}',
        value: set.value == null ? '' : _number(set.value!),
      ),
    _SetRow(),
  ];

  @override
  void dispose() {
    for (final c in [_name, _text, _exercise, _coachNotes, _memberNotes]) {
      c.dispose();
    }
    _magic.dispose();
    _exerciseFocus.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  /// Keeps exactly one empty row at the end, like the reference's `→` row.
  void _onRowChanged() {
    setState(() {
      if (!_rows.last.isEmpty) _rows.add(_SetRow());
    });
  }

  void _removeRow(int index) => setState(() => _rows.removeAt(index).dispose());

  void _buildSets() {
    final sets = parseSetShorthand(_magic.text);
    if (sets == null) {
      setState(
        () => _error = 'Try something like 5x5 @ 80% or 3x3@85, 2x1@90.',
      );
      return;
    }
    setState(() {
      if (shorthandUsesRpe(_magic.text)) _unit = SetUnit.rpe;
      for (final row in _rows) {
        row.dispose();
      }
      _rows
        ..clear()
        ..addAll([
          for (final set in sets)
            _SetRow(
              reps: '${set.reps}',
              value: set.value == null ? '' : _number(set.value!),
            ),
          _SetRow(),
        ]);
      _showMagic = false;
      _magic.clear();
      _error = null;
    });
  }

  /// The server's limits, checked here so a rejected save never loses the
  /// block (the panel closes before the WOD is saved).
  String? _limitError(List<WorkoutSet> sets) {
    if (sets.length > 30) return 'A block can have at most 30 sets.';
    if (sets.any((s) => s.reps > 999)) return 'Reps go up to 999.';
    if (sets.any((s) => (s.value ?? 0) > 1000)) {
      return 'Values go up to 1000.';
    }
    final long = [
      _exercise.text,
      _coachNotes.text,
      _memberNotes.text,
    ].any((text) => text.trim().length > 2000);
    if (long) return 'Names and notes are limited to 2000 characters.';
    if (_text.text.trim().length > 4000) {
      return 'The workout text is limited to 4000 characters.';
    }
    return null;
  }

  void _save() {
    final coachNotes = _showCoachNotes ? _coachNotes.text.trim() : '';
    final memberNotes = _showMemberNotes ? _memberNotes.text.trim() : '';
    if (_kind == BlockKind.workout) {
      final text = _text.text.trim();
      final limit = _limitError(const []);
      if (text.isEmpty || limit != null) {
        setState(() => _error = limit ?? 'Describe the workout.');
        return;
      }
      Navigator.of(context).pop(
        DailyWorkoutSection(
          title: _name.text.trim(),
          description: text,
          scoreType: _score,
          coachNotes: coachNotes,
          memberNotes: memberNotes,
        ),
      );
      return;
    }
    final exercise = _exercise.text.trim();
    final sets = [
      for (final row in _rows)
        if (row.toSet() != null) row.toSet()!,
    ];
    final limit = _limitError(sets);
    if (exercise.isEmpty || sets.isEmpty || limit != null) {
      setState(
        () => _error = limit ?? 'Pick an exercise and add at least one set.',
      );
      return;
    }
    Navigator.of(context).pop(
      DailyWorkoutSection(
        title: _name.text.trim().isEmpty ? exercise : _name.text.trim(),
        // Readable text for every reader (athletes, logbook).
        description: [
          exercise,
          for (var i = 0; i < sets.length; i++)
            '${i + 1}. ${formatWorkoutSet(sets[i], _unit)}',
        ].join('\n'),
        scoreType: WorkoutSectionScore.weight,
        kind: BlockKind.exercise,
        exerciseName: exercise,
        setUnit: _unit,
        sets: sets,
        coachNotes: coachNotes,
        memberNotes: memberNotes,
      ),
    );
  }

  Future<Iterable<String>> _searchExercises(String query) async {
    if (query.trim().length < 2) return const [];
    try {
      final found = await ref
          .read(exerciseRepositoryProvider)
          .fetchExercises(query: query.trim(), limit: 8);
      return found.map((e) => e.name);
    } catch (_) {
      // The library is a help, not a requirement: free text still works.
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final decimals = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return AppSidePanel(
      title: widget.existing == null ? 'New block' : 'Edit block',
      subtitle: widget.dayLabel,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Block name',
              hintText: 'e.g. Strength, Metcon, Accessory',
              counterText: '',
            ),
          ),
          const SizedBox(height: appSpaceLg),
          SegmentedButton<BlockKind>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: BlockKind.workout, label: Text('Workout')),
              ButtonSegment(value: BlockKind.exercise, label: Text('Exercise')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() {
              _kind = s.first;
              _error = null;
            }),
          ),
          const SizedBox(height: appSpaceLg),
          if (_kind == BlockKind.workout) ...[
            TextField(
              controller: _text,
              minLines: 4,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: 'Workout',
                hintText: '10 rounds\n10 Burpees over rower\n500m row',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: appSpaceMd),
            DropdownButtonFormField<WorkoutSectionScore>(
              initialValue: _score,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Score'),
              items: [
                for (final score in WorkoutSectionScore.values)
                  DropdownMenuItem(
                    value: score,
                    child: Text(workoutSectionScoreLabel(score)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _score = value);
              },
            ),
          ] else ...[
            // Suggestions from the movement library; free text works too.
            RawAutocomplete<String>(
              textEditingController: _exercise,
              focusNode: _exerciseFocus,
              optionsBuilder: (value) => _searchExercises(value.text),
              // Close the suggestions once one is picked.
              onSelected: (_) => _exerciseFocus.unfocus(),
              fieldViewBuilder: (context, controller, focus, onSubmit) =>
                  TextField(
                    controller: controller,
                    focusNode: focus,
                    decoration: const InputDecoration(
                      labelText: 'Exercise name',
                      hintText: 'Search the movement library',
                      prefixIcon: Icon(Icons.search_rounded, size: 18),
                    ),
                  ),
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  color: appSurfaceElevated,
                  elevation: 4,
                  borderRadius: BorderRadius.circular(appRadiusMd),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 280,
                      maxWidth: 420,
                    ),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: [
                        for (final name in options)
                          ListTile(
                            dense: true,
                            title: Text(name),
                            onTap: () => onSelected(name),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: appSpaceLg),
            Row(
              children: [
                Text('SETS', style: appMono(fontSize: 10)),
                const Spacer(),
                SegmentedButton<SetUnit>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(value: SetUnit.rpe, label: Text('RPE')),
                    ButtonSegment(value: SetUnit.percent, label: Text('%')),
                  ],
                  selected: {_unit},
                  onSelectionChanged: (s) => setState(() => _unit = s.first),
                ),
              ],
            ),
            const SizedBox(height: appSpaceSm),
            for (var i = 0; i < _rows.length; i++)
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
                        controller: _rows[i].reps,
                        inputFormatters: digits,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        onChanged: (_) => _onRowChanged(),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '5',
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: appSpaceSm),
                      child: Text(
                        'reps @',
                        style: TextStyle(color: appMutedText),
                      ),
                    ),
                    SizedBox(
                      width: 72,
                      child: TextField(
                        controller: _rows[i].value,
                        inputFormatters: decimals,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.center,
                        onChanged: (_) => _onRowChanged(),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: _unit == SetUnit.rpe ? '8' : '80',
                        ),
                      ),
                    ),
                    const SizedBox(width: appSpaceSm),
                    Text(
                      _unit == SetUnit.rpe ? 'RPE' : '%',
                      style: const TextStyle(color: appMutedText),
                    ),
                    const Spacer(),
                    if (i < _rows.length - 1)
                      IconButton(
                        tooltip: 'Remove set',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _removeRow(i),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: appSubtleText,
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.all(appSpaceSm),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: appSubtleText,
                        ),
                      ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: appSpaceLg),
          Text('SETTINGS', style: appMono(fontSize: 10)),
          const SizedBox(height: appSpaceSm),
          Wrap(
            spacing: appSpaceSm,
            children: [
              FilterChip(
                label: const Text('Coach notes'),
                selected: _showCoachNotes,
                onSelected: (v) => setState(() => _showCoachNotes = v),
              ),
              FilterChip(
                label: const Text('Member notes'),
                selected: _showMemberNotes,
                onSelected: (v) => setState(() => _showMemberNotes = v),
              ),
            ],
          ),
          if (_showCoachNotes) ...[
            const SizedBox(height: appSpaceMd),
            TextField(
              controller: _coachNotes,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Coach notes',
                helperText: 'Only owners and trainers see these.',
              ),
            ),
          ],
          if (_showMemberNotes) ...[
            const SizedBox(height: appSpaceMd),
            TextField(
              controller: _memberNotes,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Member notes',
                helperText: 'Shown to members in the app.',
              ),
            ),
          ],
          if (_kind == BlockKind.exercise) ...[
            const SizedBox(height: appSpaceLg),
            if (!_showMagic)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showMagic = true),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text('Try the Magic Set Builder'),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _magic,
                      autofocus: true,
                      onSubmitted: (_) => _buildSets(),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Magic Set Builder',
                        hintText: '5x5 @ 80%  ·  3x3@85, 2x1@90',
                      ),
                    ),
                  ),
                  const SizedBox(width: appSpaceSm),
                  TextButton(
                    onPressed: _buildSets,
                    child: const Text('Build sets'),
                  ),
                ],
              ),
          ],
          if (_error != null) ...[
            const SizedBox(height: appSpaceMd),
            Text(_error!, style: const TextStyle(color: appDanger)),
          ],
        ],
      ),
    );
  }
}
