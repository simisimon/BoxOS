import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/mobile_content.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProgrammingScreen extends ConsumerStatefulWidget {
  const ProgrammingScreen({super.key});

  @override
  ConsumerState<ProgrammingScreen> createState() => _ProgrammingScreenState();
}

class _ProgrammingScreenState extends ConsumerState<ProgrammingScreen> {
  late Future<List<DailyWorkout>> _workoutsFuture;

  @override
  void initState() {
    super.initState();
    _workoutsFuture = _loadWorkouts();
  }

  Future<List<DailyWorkout>> _loadWorkouts() {
    return ref.read(programmingRepositoryProvider).fetchWorkouts();
  }

  Future<void> _refresh() async {
    setState(() {
      _workoutsFuture = _loadWorkouts();
    });
  }

  Future<void> _openEditor({DailyWorkout? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _WorkoutEditorDialog(existing: existing),
    );
    if (saved == true) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.valueOrNull;
    final canManage =
        profile?.activeGym != null &&
        (profile?.role == UserRole.admin || profile?.role == UserRole.trainer);

    return Scaffold(
      appBar: AppBar(title: const Text('Programming')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('New WOD'),
            )
          : null,
      body: MobileContent(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily workout programming',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        canManage
                            ? 'Create and adjust the workout plan for each day in your active gym.'
                            : 'See the current and upcoming workouts for your active gym.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (profile?.activeGym == null)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No active gym selected. Join or switch to a gym to view programming.',
                    ),
                  ),
                )
              else
                FutureBuilder<List<DailyWorkout>>(
                  future: _workoutsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            errorMessageFrom(
                              snapshot.error!,
                              fallback: 'Failed to load programming',
                            ),
                          ),
                        ),
                      );
                    }

                    final workouts = snapshot.data ?? const <DailyWorkout>[];
                    if (workouts.isEmpty) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            canManage
                                ? 'No workouts have been programmed yet. Add the first daily WOD.'
                                : 'No workouts have been programmed yet for this gym.',
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: [
                        for (final workout in workouts) ...[
                          _WorkoutCard(
                            workout: workout,
                            canSubmitWhiteboard: profile?.activeGym != null,
                            onEdit: canManage && workout.canEdit
                                ? () => _openEditor(existing: workout)
                                : null,
                            onSubmitWhiteboard: () async {
                              final updated = await showDialog<bool>(
                                context: context,
                                builder: (context) =>
                                    _WhiteboardResultDialog(workout: workout),
                              );
                              if (updated == true) {
                                await _refresh();
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({
    required this.workout,
    required this.canSubmitWhiteboard,
    this.onEdit,
    this.onSubmitWhiteboard,
  });

  final DailyWorkout workout;
  final bool canSubmitWhiteboard;
  final VoidCallback? onEdit;
  final VoidCallback? onSubmitWhiteboard;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final scheduledDate = localizations.formatFullDate(workout.scheduledDate);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        workout.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(scheduledDate),
                    ],
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit workout',
                  ),
              ],
            ),
            if (workout.strengthText.isNotEmpty) ...[
              const SizedBox(height: 12),
              _WorkoutSection(label: 'Strength', value: workout.strengthText),
            ],
            if (workout.metconText.isNotEmpty) ...[
              const SizedBox(height: 12),
              _WorkoutSection(label: 'MetCon', value: workout.metconText),
            ],
            if (workout.notesText.isNotEmpty) ...[
              const SizedBox(height: 12),
              _WorkoutSection(label: 'Notes', value: workout.notesText),
            ],
            const SizedBox(height: 16),
            _WhiteboardSection(
              workout: workout,
              canSubmit: canSubmitWhiteboard,
              onSubmit: onSubmitWhiteboard,
            ),
          ],
        ),
      ),
    );
  }
}

class _WhiteboardSection extends StatelessWidget {
  const _WhiteboardSection({
    required this.workout,
    required this.canSubmit,
    this.onSubmit,
  });

  final DailyWorkout workout;
  final bool canSubmit;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Whiteboard',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (canSubmit && onSubmit != null)
              OutlinedButton.icon(
                onPressed: onSubmit,
                icon: const Icon(Icons.emoji_events_outlined),
                label: Text(
                  workout.myWhiteboardResult == null ? 'Submit Result' : 'Update Result',
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (workout.myWhiteboardResult != null) ...[
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My result: ${workout.myWhiteboardResult!.scoreLabel} (${_scoreTypeLabel(workout.myWhiteboardResult!.scoreType)})',
                  ),
                  if (workout.myWhiteboardResult!.notesText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(workout.myWhiteboardResult!.notesText),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (workout.whiteboardResults.isEmpty)
          const Text('No whiteboard results yet.')
        else
          Column(
            children: [
              for (final result in workout.whiteboardResults) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text('${result.rank}'),
                  ),
                  title: Text(result.athleteName),
                  subtitle: result.notesText.isEmpty
                      ? Text(_scoreTypeLabel(result.scoreType))
                      : Text(
                          '${_scoreTypeLabel(result.scoreType)} • ${result.notesText}',
                        ),
                  trailing: Text(
                    result.scoreLabel,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Divider(height: 1),
              ],
            ],
          ),
      ],
    );
  }
}

String _scoreTypeLabel(String value) {
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

class _WorkoutSection extends StatelessWidget {
  const _WorkoutSection({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(value),
      ],
    );
  }
}

class _WorkoutEditorDialog extends ConsumerStatefulWidget {
  const _WorkoutEditorDialog({this.existing});

  final DailyWorkout? existing;

  @override
  ConsumerState<_WorkoutEditorDialog> createState() =>
      _WorkoutEditorDialogState();
}

class _WorkoutEditorDialogState extends ConsumerState<_WorkoutEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _selectedDate;
  late TextEditingController _titleController;
  late TextEditingController _strengthController;
  late TextEditingController _metconController;
  late TextEditingController _notesController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.existing?.scheduledDate ?? DateTime.now();
    _titleController = TextEditingController(text: widget.existing?.title ?? 'Daily WOD');
    _strengthController = TextEditingController(text: widget.existing?.strengthText ?? '');
    _metconController = TextEditingController(text: widget.existing?.metconText ?? '');
    _notesController = TextEditingController(text: widget.existing?.notesText ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _strengthController.dispose();
    _metconController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 0)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      final repository = ref.read(programmingRepositoryProvider);
      if (widget.existing == null) {
        await repository.createWorkout(
          scheduledDate: _selectedDate,
          title: _titleController.text.trim(),
          strengthText: _strengthController.text.trim(),
          metconText: _metconController.text.trim(),
          notesText: _notesController.text.trim(),
        );
      } else {
        await repository.updateWorkout(
          id: widget.existing!.id,
          scheduledDate: _selectedDate,
          title: _titleController.text.trim(),
          strengthText: _strengthController.text.trim(),
          metconText: _metconController.text.trim(),
          notesText: _notesController.text.trim(),
        );
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
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
    final dateLabel = MaterialLocalizations.of(context).formatFullDate(_selectedDate);
    return AlertDialog(
      title: Text(widget.existing == null ? 'New Daily WOD' : 'Edit Daily WOD'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
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
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Enter a workout title';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _strengthController,
                  decoration: const InputDecoration(labelText: 'Strength'),
                  minLines: 3,
                  maxLines: 5,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _metconController,
                  decoration: const InputDecoration(labelText: 'MetCon'),
                  minLines: 3,
                  maxLines: 5,
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

class _WhiteboardResultDialog extends ConsumerStatefulWidget {
  const _WhiteboardResultDialog({required this.workout});

  final DailyWorkout workout;

  @override
  ConsumerState<_WhiteboardResultDialog> createState() =>
      _WhiteboardResultDialogState();
}

class _WhiteboardResultDialogState extends ConsumerState<_WhiteboardResultDialog> {
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
      await ref.read(programmingRepositoryProvider).submitWhiteboardResult(
            workoutId: widget.workout.id,
            scoreType: _scoreType,
            scoreValue: _scoreValueController.text.trim(),
            notesText: _notesController.text.trim(),
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to save whiteboard result'),
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
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Enter a score';
                    }
                    return null;
                  },
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
