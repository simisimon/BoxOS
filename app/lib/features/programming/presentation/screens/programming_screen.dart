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
                            onEdit: canManage && workout.canEdit
                                ? () => _openEditor(existing: workout)
                                : null,
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
  const _WorkoutCard({required this.workout, this.onEdit});

  final DailyWorkout workout;
  final VoidCallback? onEdit;

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
          ],
        ),
      ),
    );
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
