import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_form_dialog.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/class_template.dart';
import 'package:app/features/calendar/domain/models/class_type.dart';
import 'package:app/features/calendar/domain/models/schedule_trainer.dart';
import 'package:app/features/calendar/domain/repositories/schedule_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Opens [ClassTemplateDialog] and, after a save or delete, refreshes the
/// class series and the generated sessions and shows the result message.
Future<void> showClassTemplateDialog(
  BuildContext context,
  WidgetRef ref, {
  ClassTemplate? existing,
  int? initialWeekday,
}) async {
  final message = await showDialog<String>(
    context: context,
    builder: (_) =>
        ClassTemplateDialog(existing: existing, initialWeekday: initialWeekday),
  );
  if (message == null) {
    return;
  }
  ref.invalidate(classTemplatesProvider);
  ref.invalidate(scheduleListProvider);
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Create/edit form for a weekly class. Pops with a confirmation message on
/// save or delete, or null when cancelled.
class ClassTemplateDialog extends ConsumerStatefulWidget {
  const ClassTemplateDialog({super.key, this.existing, this.initialWeekday});

  final ClassTemplate? existing;
  final int? initialWeekday;

  @override
  ConsumerState<ClassTemplateDialog> createState() =>
      _ClassTemplateDialogState();
}

class _ClassTemplateDialogState extends ConsumerState<ClassTemplateDialog> {
  static const _durationOptions = [30, 45, 60, 75, 90, 120];
  static const _minuteOptions = [0, 15, 30, 45];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _capacityController;
  late final Future<List<ScheduleTrainer>> _trainersFuture;
  late ClassType _type;
  late Set<int> _weekdays;
  late int _hour;
  late int _minute;
  late int _duration;
  int? _trainerId;
  bool _isSaving = false;
  String? _weekdayError;

  bool get _isCreating => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.classType ?? ClassType.wod;
    _weekdays = {
      ...?existing?.weekdays,
      if (existing == null) widget.initialWeekday ?? 1,
    };
    _hour = existing?.hour ?? 18;
    _minute = _minuteOptions.contains(existing?.minute) ? existing!.minute : 0;
    _duration = _durationOptions.contains(existing?.durationMinutes)
        ? existing!.durationMinutes
        : 60;
    _trainerId = existing?.assignedTrainer?.id;
    _titleController = TextEditingController(
      text: existing?.title ?? _type.defaultTitle,
    );
    _capacityController = TextEditingController(
      text: '${existing?.capacity ?? 12}',
    );
    _trainersFuture = ref.read(scheduleRepositoryProvider).fetchTrainers();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  void _selectType(ClassType type) {
    setState(() {
      // Follow the type with the title until the owner has typed their own.
      if (_titleController.text.trim() == _type.defaultTitle) {
        _titleController.text = type.defaultTitle;
      }
      _type = type;
    });
  }

  Future<void> _save() async {
    final formValid = _formKey.currentState?.validate() ?? false;
    setState(
      () => _weekdayError = _weekdays.isEmpty
          ? 'Select at least one weekday'
          : null,
    );
    if (!formValid || _weekdays.isEmpty || _isSaving) {
      return;
    }
    final draft = ClassTemplateDraft(
      title: _titleController.text.trim(),
      classType: _type.wireValue,
      weekdays: _weekdays.toList()..sort(),
      hour: _hour,
      minute: _minute,
      durationMinutes: _duration,
      capacity: int.parse(_capacityController.text.trim()),
      trainerUserId: _trainerId,
    );
    setState(() => _isSaving = true);
    try {
      final repository = ref.read(scheduleRepositoryProvider);
      final String message;
      if (_isCreating) {
        await repository.createTemplate(draft);
        message = '${draft.title} added to the week plan.';
      } else {
        final kept = await repository.updateTemplate(
          id: widget.existing!.id,
          draft: draft,
        );
        message = kept == 0
            ? '${draft.title} updated for all upcoming dates.'
            : '${draft.title} updated. $kept already-booked '
                  '${kept == 1 ? 'date keeps' : 'dates keep'} the old time — '
                  'check the calendar.';
      }
      if (mounted) {
        Navigator.of(context).pop(message);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to save class'),
          ),
        ),
      );
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing!;
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Delete class',
      message:
          'Remove ${existing.title} from the week plan? Upcoming dates nobody '
          'has booked are removed too; booked dates stay on the calendar.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      final kept = await ref
          .read(scheduleRepositoryProvider)
          .deleteTemplate(id: existing.id);
      if (!mounted) return;
      Navigator.of(context).pop(
        kept == 0
            ? '${existing.title} removed from the week plan.'
            : '${existing.title} removed. $kept booked '
                  '${kept == 1 ? 'date stays' : 'dates stay'} on the calendar.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to delete class'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppFormDialog(
      title: _isCreating ? 'Add class' : 'Edit class',
      subtitle: _isCreating
          ? null
          : 'Changes apply to all upcoming dates. Booked dates keep their time.',
      leading: _isCreating
          ? null
          : IconButton(
              onPressed: _isSaving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
              color: appDanger,
              tooltip: 'Delete class',
            ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: Text(_isCreating ? 'Add class' : 'Save'),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('TYPE', style: appMono(fontSize: 10)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in ClassType.values)
                  ChoiceChip(
                    label: Text(type.label),
                    selected: _type == type,
                    onSelected: (_) => _selectType(type),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Enter a title' : null,
            ),
            const SizedBox(height: 16),
            Text('DAYS', style: appMono(fontSize: 10)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var day = 1; day <= 7; day++)
                  FilterChip(
                    label: Text(_weekdayShort[day - 1]),
                    selected: _weekdays.contains(day),
                    onSelected: (selected) => setState(() {
                      selected ? _weekdays.add(day) : _weekdays.remove(day);
                      if (_weekdays.isNotEmpty) _weekdayError = null;
                    }),
                  ),
              ],
            ),
            if (_weekdayError != null) ...[
              const SizedBox(height: 6),
              Text(
                _weekdayError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _hour,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Hour'),
                    items: [
                      for (var hour = 0; hour < 24; hour++)
                        DropdownMenuItem(
                          value: hour,
                          child: Text(hour.toString().padLeft(2, '0')),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _hour = value);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _minute,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Minute'),
                    items: [
                      for (final minute in _minuteOptions)
                        DropdownMenuItem(
                          value: minute,
                          child: Text(minute.toString().padLeft(2, '0')),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _minute = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _duration,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Duration'),
                    items: [
                      for (final duration in _durationOptions)
                        DropdownMenuItem(
                          value: duration,
                          child: Text('$duration min'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _duration = value);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _capacityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Capacity'),
                    validator: (value) {
                      final parsed = int.tryParse((value ?? '').trim());
                      if (parsed == null || parsed <= 0 || parsed > 200) {
                        return '1–200';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<ScheduleTrainer>>(
              future: _trainersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  );
                }
                final trainers = snapshot.data ?? const <ScheduleTrainer>[];
                final selected =
                    trainers.any((trainer) => trainer.id == _trainerId)
                    ? _trainerId
                    : null;
                return DropdownButtonFormField<int?>(
                  initialValue: selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Default trainer',
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('No trainer'),
                    ),
                    for (final trainer in trainers)
                      DropdownMenuItem<int?>(
                        value: trainer.id,
                        child: Text(trainer.label),
                      ),
                  ],
                  onChanged: (value) => setState(() => _trainerId = value),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
