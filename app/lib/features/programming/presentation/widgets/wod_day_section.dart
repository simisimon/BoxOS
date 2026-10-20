import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_form_dialog.dart';
import 'package:app/features/logbook/data/repositories/api_logbook_repository.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Owner-facing WOD section for a given day. Self-contained: watches
/// [programmingListProvider], finds the workout for [date], renders either the
/// workout card (with edit/publish/duplicate actions for [canManage]) or an
/// empty-state with an "Add WOD" CTA. Mutations refresh the provider so the
/// surrounding screen does not have to manage WOD state.
class WodDaySection extends ConsumerWidget {
  const WodDaySection({super.key, required this.date, required this.canManage});

  final DateTime date;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncWorkouts = ref.watch(programmingListProvider);
    return asyncWorkouts.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _WodErrorCard(error: error),
      data: (workouts) {
        DailyWorkout? workout;
        for (final w in workouts) {
          if (_sameDay(w.scheduledDate, date)) {
            workout = w;
            break;
          }
        }
        if (workout == null) {
          return _WodEmptyState(date: date, canManage: canManage);
        }
        return _WorkoutCard(workout: workout, canManage: canManage);
      },
    );
  }
}

/// Opens the WOD editor for [date] (or for [existing]) and refreshes the
/// programming list on save. Returns true when something was saved.
Future<bool> showWodEditorDialog(
  BuildContext context,
  WidgetRef ref, {
  required DateTime date,
  DailyWorkout? existing,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _WorkoutEditorDialog(existing: existing, prefillDate: date),
  );
  if (saved == true) {
    ref.invalidate(programmingListProvider);
    return true;
  }
  return false;
}

/// The full WOD card for [date] (sections, publish/duplicate menu,
/// whiteboard) in a dialog, for views that only show a summary.
Future<void> showWodDetailsDialog(
  BuildContext context, {
  required DateTime date,
  required bool canManage,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: appSurface,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: WodDaySection(date: date, canManage: canManage),
        ),
      ),
    ),
  );
}

class _WodErrorCard extends StatelessWidget {
  const _WodErrorCard({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: appBorder),
      ),
      child: Text(
        errorMessageFrom(error, fallback: 'Failed to load WOD'),
        style: theme.textTheme.bodyMedium?.copyWith(color: appSubtleText),
      ),
    );
  }
}

class _WodEmptyState extends ConsumerWidget {
  const _WodEmptyState({required this.date, required this.canManage});

  final DateTime date;
  final bool canManage;

  bool get _isPast => _dateOnly(date).isBefore(_dateOnly(DateTime.now()));

  Future<void> _openEditor(BuildContext context, WidgetRef ref) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _WorkoutEditorDialog(existing: null, prefillDate: date),
    );
    if (saved == true) {
      ref.invalidate(programmingListProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: appPrimary.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Icon(
                  Icons.local_fire_department_outlined,
                  size: 18,
                  color: appPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'WOD',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: appPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      canManage
                          ? 'No WOD programmed yet'
                          : 'No WOD published yet',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (canManage && !_isPast) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _openEditor(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Add WOD'),
              ),
            ),
          ] else if (canManage && _isPast) ...[
            const SizedBox(height: 8),
            Text(
              'Past dates are read-only.',
              style: theme.textTheme.bodySmall?.copyWith(color: appSubtleText),
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkoutCard extends ConsumerWidget {
  const _WorkoutCard({required this.workout, required this.canManage});

  final DailyWorkout workout;
  final bool canManage;

  Future<void> _openEditor(BuildContext context, WidgetRef ref) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _WorkoutEditorDialog(
        existing: workout,
        prefillDate: workout.scheduledDate,
      ),
    );
    if (saved == true) {
      ref.invalidate(programmingListProvider);
    }
  }

  Future<void> _publish(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(programmingRepositoryProvider)
          .publishWorkout(id: workout.id);
      ref.invalidate(programmingListProvider);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to publish workout'),
          ),
        ),
      );
    }
  }

  Future<void> _unpublish(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(programmingRepositoryProvider)
          .unpublishWorkout(id: workout.id);
      ref.invalidate(programmingListProvider);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to unpublish workout'),
          ),
        ),
      );
    }
  }

  Future<void> _duplicate(BuildContext context, WidgetRef ref) async {
    final target = await showDatePicker(
      context: context,
      initialDate: workout.scheduledDate.add(const Duration(days: 7)),
      firstDate: _dateOnly(DateTime.now()),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (target == null) return;
    try {
      await ref
          .read(programmingRepositoryProvider)
          .duplicateWorkout(
            sourceDate: workout.scheduledDate,
            targetDate: target,
          );
      ref.invalidate(programmingListProvider);
      if (!context.mounted) return;
      final formatted =
          '${target.year}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Duplicated to $formatted (as draft).')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to duplicate workout'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: appBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: appPrimary.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'WOD',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: appPrimary,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (canManage) _StatusBadge(status: workout.status),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      workout.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (canManage)
                PopupMenuButton<String>(
                  tooltip: 'Workout actions',
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        _openEditor(context, ref);
                        break;
                      case 'publish':
                        _publish(context, ref);
                        break;
                      case 'unpublish':
                        _unpublish(context, ref);
                        break;
                      case 'duplicate':
                        _duplicate(context, ref);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    if (!workout.isPublished)
                      const PopupMenuItem(
                        value: 'publish',
                        child: Text('Publish'),
                      ),
                    if (workout.isPublished)
                      const PopupMenuItem(
                        value: 'unpublish',
                        child: Text('Unpublish'),
                      ),
                    const PopupMenuItem(
                      value: 'duplicate',
                      child: Text('Duplicate to…'),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < workout.sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _SectionRow(index: i, section: workout.sections[i]),
          ],
          if (workout.isPublished) ...[
            const SizedBox(height: 16),
            _PanelSection(child: _WhiteboardSection(workout: workout)),
            const SizedBox(height: 12),
            _PanelSection(child: _WorkoutLogSection(workout: workout)),
          ],
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.index, required this.section});

  final int index;
  final DailyWorkoutSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = section.title.isNotEmpty
        ? section.title
        : 'Section ${index + 1}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: appPrimary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: appPrimary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                (index + 1).toString().padLeft(2, '0'),
                style: appMono(fontSize: 11, color: appPrimary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: appPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              _ScoreBadge(score: section.scoreType),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            section.description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: appText,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});

  final WorkoutSectionScore score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: appPrimary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: appPrimary.withValues(alpha: 0.35)),
      ),
      child: Text(
        workoutSectionScoreLabel(score).toUpperCase(),
        style: appMono(fontSize: 9, letterSpacing: 1.1, color: appText),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final DailyWorkoutStatus status;

  @override
  Widget build(BuildContext context) {
    final isPublished = status == DailyWorkoutStatus.published;
    final color = isPublished ? appPrimary : appMutedText;
    final label = isPublished ? 'PUBLISHED' : 'DRAFT';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _PanelSection extends StatelessWidget {
  const _PanelSection({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: appSurfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: appBorder),
      ),
      child: child,
    );
  }
}

String _whiteboardScoreLabel(String value) {
  switch (value) {
    case 'time':
      return 'For time';
    case 'reps':
      return 'Reps';
    case 'load':
      return 'Load';
    default:
      return value;
  }
}

class _WhiteboardSection extends ConsumerWidget {
  const _WhiteboardSection({required this.workout});
  final DailyWorkout workout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Whiteboard',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: appText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final updated = await showDialog<bool>(
                  context: context,
                  builder: (_) => _WhiteboardResultDialog(workout: workout),
                );
                if (updated == true) {
                  ref.invalidate(programmingListProvider);
                }
              },
              icon: const Icon(Icons.emoji_events_outlined),
              // Theme buttons are full-width; next to the title in a Row
              // they need a finite minimum width.
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
              label: Text(
                workout.myWhiteboardResult == null ? 'Submit' : 'Update',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (workout.myWhiteboardResult != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: appSurface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'My result: ${workout.myWhiteboardResult!.scoreLabel} '
              '(${_whiteboardScoreLabel(workout.myWhiteboardResult!.scoreType)})'
              '${workout.myWhiteboardResult!.notesText.isEmpty ? '' : '\n${workout.myWhiteboardResult!.notesText}'}',
              style: theme.textTheme.bodyMedium?.copyWith(color: appText),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (workout.whiteboardResults.isEmpty)
          Text(
            'No whiteboard results yet.',
            style: theme.textTheme.bodySmall?.copyWith(color: appSubtleText),
          )
        else
          Column(
            children: [
              for (final result in workout.whiteboardResults)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: const Color(0xFF1E2A43),
                        child: Text(
                          '${result.rank}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: appText,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          result.athleteName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: appText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        result.scoreLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: appPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _WorkoutLogSection extends ConsumerWidget {
  const _WorkoutLogSection({required this.workout});
  final DailyWorkout workout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'My log',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: appText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final updated = await showDialog<bool>(
                  context: context,
                  builder: (_) => _WorkoutLogDialog(workout: workout),
                );
                if (updated == true) {
                  ref.invalidate(programmingListProvider);
                }
              },
              icon: const Icon(Icons.edit_note_outlined),
              // Theme buttons are full-width; next to the title in a Row
              // they need a finite minimum width.
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
              label: Text(workout.myWorkoutLog == null ? 'Log' : 'Update'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (workout.myWorkoutLog == null)
          Text(
            'No personal workout log yet.',
            style: theme.textTheme.bodySmall?.copyWith(color: appSubtleText),
          )
        else
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: appSurface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${workout.myWorkoutLog!.scoreLabel} '
                    '(${_whiteboardScoreLabel(workout.myWorkoutLog!.scoreType)})'
                    '${workout.myWorkoutLog!.notesText.isEmpty ? '' : '\n${workout.myWorkoutLog!.notesText}'}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: appText),
                  ),
                ),
                if (workout.myWorkoutLog!.isPr) const Chip(label: Text('PR')),
              ],
            ),
          ),
      ],
    );
  }
}

/// Mutable draft of a section while the editor dialog is open.
class _SectionDraft {
  _SectionDraft({
    required this.titleController,
    required this.descriptionController,
    required this.scoreType,
  });

  factory _SectionDraft.empty() => _SectionDraft(
    titleController: TextEditingController(),
    descriptionController: TextEditingController(),
    scoreType: WorkoutSectionScore.time,
  );

  factory _SectionDraft.from(DailyWorkoutSection section) => _SectionDraft(
    titleController: TextEditingController(text: section.title),
    descriptionController: TextEditingController(text: section.description),
    scoreType: section.scoreType,
  );

  final TextEditingController titleController;
  final TextEditingController descriptionController;
  WorkoutSectionScore scoreType;

  DailyWorkoutSection toSection() => DailyWorkoutSection(
    title: titleController.text.trim(),
    description: descriptionController.text.trim(),
    scoreType: scoreType,
  );

  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
  }
}

class _WorkoutEditorDialog extends ConsumerStatefulWidget {
  const _WorkoutEditorDialog({this.existing, required this.prefillDate});

  final DailyWorkout? existing;
  final DateTime prefillDate;

  @override
  ConsumerState<_WorkoutEditorDialog> createState() =>
      _WorkoutEditorDialogState();
}

class _WorkoutEditorDialogState extends ConsumerState<_WorkoutEditorDialog> {
  static const int _maxSections = 20;

  final _formKey = GlobalKey<FormState>();
  late DateTime _selectedDate;
  late TextEditingController _titleController;
  late List<_SectionDraft> _sections;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final initialDate = widget.existing?.scheduledDate ?? widget.prefillDate;
    final today = _dateOnly(DateTime.now());
    _selectedDate = initialDate.isBefore(today)
        ? today
        : _dateOnly(initialDate);
    _titleController = TextEditingController(
      text: widget.existing?.title ?? 'Daily WOD',
    );
    final existingSections =
        widget.existing?.sections ?? const <DailyWorkoutSection>[];
    _sections = existingSections.isEmpty
        ? [_SectionDraft.empty()]
        : [for (final section in existingSections) _SectionDraft.from(section)];
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final section in _sections) {
      section.dispose();
    }
    super.dispose();
  }

  void _addSection() {
    if (_sections.length >= _maxSections) return;
    setState(() => _sections.add(_SectionDraft.empty()));
  }

  void _removeSection(int index) {
    if (_sections.length <= 1) return;
    setState(() {
      _sections.removeAt(index).dispose();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDate = _dateOnly(picked));
    }
  }

  Future<void> _submit({required DailyWorkoutStatus statusOnCreate}) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final sections = [for (final draft in _sections) draft.toSection()];
    setState(() => _isSaving = true);
    try {
      final repository = ref.read(programmingRepositoryProvider);
      if (widget.existing == null) {
        await repository.createWorkout(
          scheduledDate: _selectedDate,
          title: _titleController.text.trim(),
          sections: sections,
          status: statusOnCreate,
        );
      } else {
        await repository.updateWorkout(
          id: widget.existing!.id,
          scheduledDate: _selectedDate,
          title: _titleController.text.trim(),
          sections: sections,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to save workout'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = MaterialLocalizations.of(
      context,
    ).formatFullDate(_selectedDate);
    final isCreating = widget.existing == null;
    return AppFormDialog(
      title: isCreating ? 'New WOD' : 'Edit WOD',
      subtitle: dateLabel,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: _isSaving ? null : _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(dateLabel),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Enter a workout title' : null,
            ),
            const SizedBox(height: 18),
            _SectionsEditor(
              sections: _sections,
              isSaving: _isSaving,
              canRemove: _sections.length > 1,
              onAdd: _sections.length >= _maxSections ? null : _addSection,
              onRemove: _removeSection,
              onScoreChanged: (index, value) {
                setState(() => _sections[index].scoreType = value);
              },
              maxSections: _maxSections,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        if (isCreating) ...[
          OutlinedButton(
            onPressed: _isSaving
                ? null
                : () => _submit(statusOnCreate: DailyWorkoutStatus.draft),
            child: const Text('Save as Draft'),
          ),
          FilledButton(
            onPressed: _isSaving
                ? null
                : () => _submit(statusOnCreate: DailyWorkoutStatus.published),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save & Publish'),
          ),
        ] else
          FilledButton(
            onPressed: _isSaving
                ? null
                : () => _submit(statusOnCreate: DailyWorkoutStatus.draft),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
      ],
    );
  }
}

class _SectionsEditor extends StatelessWidget {
  const _SectionsEditor({
    required this.sections,
    required this.isSaving,
    required this.canRemove,
    required this.onAdd,
    required this.onRemove,
    required this.onScoreChanged,
    required this.maxSections,
  });

  final List<_SectionDraft> sections;
  final bool isSaving;
  final bool canRemove;
  final VoidCallback? onAdd;
  final void Function(int index) onRemove;
  final void Function(int index, WorkoutSectionScore value) onScoreChanged;
  final int maxSections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Sections',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: appText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '${sections.length}/$maxSections',
              style: theme.textTheme.labelSmall?.copyWith(color: appSubtleText),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Break the WOD into blocks (Warm Up, Strength, MetCon …). Each '
          'section needs a description and a score unit.',
          style: theme.textTheme.bodySmall?.copyWith(color: appSubtleText),
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < sections.length; index++) ...[
          _SectionCard(
            index: index,
            draft: sections[index],
            canRemove: canRemove,
            isSaving: isSaving,
            onRemove: () => onRemove(index),
            onScoreChanged: (value) => onScoreChanged(index, value),
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton.icon(
          onPressed: isSaving ? null : onAdd,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add section'),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.index,
    required this.draft,
    required this.canRemove,
    required this.isSaving,
    required this.onRemove,
    required this.onScoreChanged,
  });

  final int index;
  final _SectionDraft draft;
  final bool canRemove;
  final bool isSaving;
  final VoidCallback onRemove;
  final ValueChanged<WorkoutSectionScore> onScoreChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
      decoration: BoxDecoration(
        color: appSurfaceAlt,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Section ${index + 1}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: appPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              IconButton(
                tooltip: canRemove
                    ? 'Remove section'
                    : 'A WOD needs at least one section',
                onPressed: canRemove && !isSaving ? onRemove : null,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          TextFormField(
            controller: draft.titleController,
            enabled: !isSaving,
            decoration: const InputDecoration(
              labelText: 'Title (optional)',
              hintText: 'e.g. Warm Up, Strength, MetCon',
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: draft.descriptionController,
            enabled: !isSaving,
            decoration: const InputDecoration(labelText: 'Description'),
            minLines: 2,
            maxLines: 5,
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Enter a description' : null,
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<WorkoutSectionScore>(
            initialValue: draft.scoreType,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Score unit'),
            items: const [
              DropdownMenuItem<WorkoutSectionScore>(
                value: WorkoutSectionScore.time,
                child: Text('Time'),
              ),
              DropdownMenuItem<WorkoutSectionScore>(
                value: WorkoutSectionScore.roundsReps,
                child: Text('Rounds + Reps'),
              ),
              DropdownMenuItem<WorkoutSectionScore>(
                value: WorkoutSectionScore.weight,
                child: Text('Weight (kg)'),
              ),
            ],
            onChanged: isSaving
                ? null
                : (value) {
                    if (value != null) onScoreChanged(value);
                  },
          ),
        ],
      ),
    );
  }
}

class _WhiteboardResultDialog extends ConsumerStatefulWidget {
  const _WhiteboardResultDialog({required this.workout});
  final DailyWorkout workout;

  @override
  ConsumerState<_WhiteboardResultDialog> createState() =>
      _WhiteboardResultDialogState();
}

class _WhiteboardResultDialogState
    extends ConsumerState<_WhiteboardResultDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _scoreType;
  late TextEditingController _scoreValueController;
  late TextEditingController _notesController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _scoreType = widget.workout.myWhiteboardResult?.scoreType ?? 'time';
    _scoreValueController = TextEditingController(
      text: widget.workout.myWhiteboardResult?.scoreLabel ?? '',
    );
    _notesController = TextEditingController(
      text: widget.workout.myWhiteboardResult?.notesText ?? '',
    );
  }

  @override
  void dispose() {
    _scoreValueController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      await ref
          .read(programmingRepositoryProvider)
          .submitWhiteboardResult(
            workoutId: widget.workout.id,
            scoreType: _scoreType,
            scoreValue: _scoreValueController.text.trim(),
            notesText: _notesController.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(
              error,
              fallback: 'Failed to save whiteboard result',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Submit Whiteboard Result'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _scoreType,
                  decoration: const InputDecoration(labelText: 'Score Type'),
                  items: const [
                    DropdownMenuItem(value: 'time', child: Text('For time')),
                    DropdownMenuItem(value: 'reps', child: Text('Reps')),
                    DropdownMenuItem(value: 'load', child: Text('Load')),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _scoreType = value);
                          }
                        },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _scoreValueController,
                  decoration: InputDecoration(
                    labelText: _scoreType == 'time'
                        ? 'Score (mm:ss or hh:mm:ss)'
                        : _scoreType == 'reps'
                        ? 'Score (reps)'
                        : 'Score (load)',
                  ),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Enter a score' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _WorkoutLogDialog extends ConsumerStatefulWidget {
  const _WorkoutLogDialog({required this.workout});
  final DailyWorkout workout;

  @override
  ConsumerState<_WorkoutLogDialog> createState() => _WorkoutLogDialogState();
}

class _WorkoutLogDialogState extends ConsumerState<_WorkoutLogDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _scoreType;
  late TextEditingController _scoreValueController;
  late TextEditingController _notesController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _scoreType = widget.workout.myWorkoutLog?.scoreType ?? 'time';
    _scoreValueController = TextEditingController(
      text: widget.workout.myWorkoutLog?.scoreLabel ?? '',
    );
    _notesController = TextEditingController(
      text: widget.workout.myWorkoutLog?.notesText ?? '',
    );
  }

  @override
  void dispose() {
    _scoreValueController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      await ref
          .read(logbookRepositoryProvider)
          .submitEntry(
            workoutId: widget.workout.id,
            scoreType: _scoreType,
            scoreValue: _scoreValueController.text.trim(),
            notesText: _notesController.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to save workout log'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Log Workout Result'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _scoreType,
                  decoration: const InputDecoration(labelText: 'Score Type'),
                  items: const [
                    DropdownMenuItem(value: 'time', child: Text('For time')),
                    DropdownMenuItem(value: 'reps', child: Text('Reps')),
                    DropdownMenuItem(value: 'load', child: Text('Load')),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _scoreType = value);
                          }
                        },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _scoreValueController,
                  decoration: InputDecoration(
                    labelText: _scoreType == 'time'
                        ? 'Score (mm:ss or hh:mm:ss)'
                        : _scoreType == 'reps'
                        ? 'Score (reps)'
                        : 'Score (load)',
                  ),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Enter a score' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
