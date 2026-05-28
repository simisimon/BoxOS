import 'dart:ui';

import 'package:app/core/errors/error_message.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/schedule_booking.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:app/features/calendar/domain/models/schedule_trainer.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MyBoxScreen extends ConsumerStatefulWidget {
  const MyBoxScreen({super.key});

  @override
  ConsumerState<MyBoxScreen> createState() => _MyBoxScreenState();
}

class _MyBoxScreenState extends ConsumerState<MyBoxScreen> {
  late Future<List<ScheduleClass>> _scheduleFuture;
  DateTime _selectedWorkoutDate = _dateOnly(DateTime.now());
  _CreateClassMode? _createClassMode;

  @override
  void initState() {
    super.initState();
    _scheduleFuture = _loadSchedule();
  }

  Future<List<ScheduleClass>> _loadSchedule() {
    return ref.read(scheduleRepositoryProvider).fetchSchedule();
  }

  Future<void> _refresh() async {
    setState(() {
      _scheduleFuture = _loadSchedule();
    });
  }

  void _showSnackBar(String message) {
    if (!mounted || Scaffold.maybeOf(context) == null) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openEditor({
    ScheduleClass? existing,
    required bool canManage,
  }) async {
    if (!canManage) {
      return;
    }
    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _ScheduleClassDialog(existing: existing),
    );
    if (updated == true) {
      await _refresh();
    }
  }

  Future<void> _deleteClass(ScheduleClass item, bool canManage) async {
    if (!canManage) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Class'),
        content: Text('Delete ${item.title} on this schedule?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref.read(scheduleRepositoryProvider).deleteClass(id: item.id);
      await _refresh();
      if (!mounted) {
        return;
      }
      _showSnackBar('Class deleted.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(
        errorMessageFrom(error, fallback: 'Failed to delete class'),
      );
    }
  }

  Future<void> _toggleBooking(ScheduleClass item) async {
    try {
      final repository = ref.read(scheduleRepositoryProvider);
      if (item.isBooked) {
        await repository.cancelBooking(classId: item.id);
      } else {
        await repository.bookClass(classId: item.id);
      }
      await _refresh();
      if (!mounted) {
        return;
      }
      _showSnackBar(item.isBooked ? 'Booking cancelled.' : 'Class booked.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(
        errorMessageFrom(error, fallback: 'Failed to update booking'),
      );
    }
  }

  Future<void> _toggleWaitlist(ScheduleClass item) async {
    try {
      final repository = ref.read(scheduleRepositoryProvider);
      if (item.isWaitlisted) {
        await repository.leaveWaitlist(classId: item.id);
      } else {
        await repository.joinWaitlist(classId: item.id);
      }
      await _refresh();
      if (!mounted) {
        return;
      }
      _showSnackBar(
        item.isWaitlisted ? 'Removed from waitlist.' : 'Added to waitlist.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(
        errorMessageFrom(error, fallback: 'Failed to update waitlist'),
      );
    }
  }

  Future<void> _updateAttendance({
    required ScheduleClass item,
    required ScheduleBooking booking,
    required String attendanceStatus,
  }) async {
    try {
      await ref
          .read(scheduleRepositoryProvider)
          .updateAttendance(
            classId: item.id,
            userId: booking.userId,
            attendanceStatus: attendanceStatus,
          );
      await _refresh();
      if (!mounted) {
        return;
      }
      _showSnackBar(
        '${booking.displayName} marked as ${_attendanceLabel(attendanceStatus)}.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(
        errorMessageFrom(error, fallback: 'Failed to update attendance'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final canManage =
        profile?.activeGym != null &&
        (profile?.role == UserRole.admin || profile?.role == UserRole.trainer);
    final roleLabel = profile?.role?.label ?? 'Athlete';
    final gymName = profile?.activeGym?.name;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF09111E),
            Color(0xFF10192A),
            Color(0xFF0B1320),
          ],
        ),
      ),
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _CalendarHero(
              canManage: canManage,
              roleLabel: roleLabel,
              gymName: gymName,
            ),
            const SizedBox(height: 16),
            if (profile?.activeGym == null)
              const _CalendarStateCard(
                icon: Icons.store_mall_directory_outlined,
                title: 'No active gym selected',
                message:
                    'Join or switch to a gym to use the schedule, bookings, waitlist, and attendance tools.',
                accentColor: Color(0xFF5FB2FF),
              )
            else
              FutureBuilder<List<ScheduleClass>>(
                future: _scheduleFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return _CalendarStateCard(
                      icon: Icons.error_outline,
                      title: 'Failed to load schedule',
                      message: errorMessageFrom(
                        snapshot.error!,
                        fallback: 'Failed to load schedule',
                      ),
                      accentColor: const Color(0xFFFF6B2C),
                    );
                  }
                  final items = snapshot.data ?? const <ScheduleClass>[];
                  final selectedItems =
                      items
                          .where(
                            (item) =>
                                _isSameDay(item.startTime, _selectedWorkoutDate),
                          )
                          .toList()
                        ..sort((a, b) => a.startTime.compareTo(b.startTime));
                  final selectedDateLabel = MaterialLocalizations.of(
                    context,
                  ).formatFullDate(_selectedWorkoutDate);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _WorkoutCalendarCard(
                        selectedDate: _selectedWorkoutDate,
                        items: items,
                        canManage: canManage,
                        createClassMode: _createClassMode,
                        onSelectCreateMode: (mode) {
                          setState(() {
                            _createClassMode = _createClassMode == mode
                                ? null
                                : mode;
                          });
                        },
                        onCreateSuccess: () async {
                          setState(() {
                            _createClassMode = null;
                          });
                          await _refresh();
                        },
                        onDateChanged: (nextDate) {
                          setState(() {
                            _selectedWorkoutDate = _dateOnly(nextDate);
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      _CalendarSectionHeader(
                        eyebrow: 'Schedule',
                        title: 'Classes on $selectedDateLabel',
                        subtitle: canManage
                            ? 'Coach, capacity, attendance, and booking controls stay anchored to the selected day.'
                            : 'See exactly what is running that day and act on bookings without leaving the schedule.',
                      ),
                      const SizedBox(height: 12),
                      if (selectedItems.isEmpty)
                        _CalendarStateCard(
                          icon: canManage
                              ? Icons.edit_calendar_outlined
                              : Icons.event_busy_outlined,
                          title: 'No classes scheduled',
                          message: canManage
                              ? 'Nothing is scheduled on $selectedDateLabel yet. Add a class to open the day.'
                              : 'No classes are scheduled on this date.',
                          accentColor: canManage
                              ? const Color(0xFFFF6B2C)
                              : const Color(0xFF7EE7C6),
                        )
                      else
                        for (final item in selectedItems) ...[
                          _ScheduleClassCard(
                            item: item,
                            canManage: canManage,
                            onToggleBooking: () => _toggleBooking(item),
                            onToggleWaitlist: () => _toggleWaitlist(item),
                            onUpdateAttendance: (booking, status) =>
                                _updateAttendance(
                                  item: item,
                                  booking: booking,
                                  attendanceStatus: status,
                                ),
                            onEdit: () => _openEditor(
                              existing: item,
                              canManage: canManage,
                            ),
                            onDelete: () => _deleteClass(item, canManage),
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
    );
  }

  static String _attendanceLabel(String value) {
    switch (value) {
      case 'attended':
        return 'Attended';
      case 'no_show':
        return 'No Show';
      default:
        return 'Booked';
    }
  }
}

class _CalendarHero extends StatelessWidget {
  const _CalendarHero({
    required this.canManage,
    required this.roleLabel,
    required this.gymName,
  });

  final bool canManage;
  final String roleLabel;
  final String? gymName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = canManage
        ? const Color(0xFFFF6B2C)
        : const Color(0xFF7EE7C6);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withOpacity(0.24),
            const Color(0xFF11192A),
            const Color(0xFF070B12),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.14),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            top: -12,
            child: _GlowOrb(color: accentColor, size: 84),
          ),
          Positioned(
            right: 38,
            bottom: -28,
            child: _GlowOrb(
              color: const Color(0xFF5FB2FF).withOpacity(0.6),
              size: 88,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _HeroPill(label: roleLabel, color: accentColor),
                  _HeroPill(
                    label: gymName ?? 'No active gym',
                    color: const Color(0xFF7EE7C6),
                    outlined: true,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Schedule',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: const Color(0xFFE8EEF8),
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                canManage
                    ? 'Run the floor with less friction.'
                    : 'Plan the next training session.',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  height: 0.96,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                canManage
                    ? 'Use one cleaner schedule surface for class creation, capacity control, attendance, and booking oversight.'
                    : 'Check the day, book quickly, and keep your waitlist or attendance state visible at a glance.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFFD7E0EE),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CalendarSectionHeader extends StatelessWidget {
  const _CalendarSectionHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: const Color(0xFF7EE7C6),
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            height: 0.96,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFFB8C4D9),
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _CalendarStateCard extends StatelessWidget {
  const _CalendarStateCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.accentColor,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101826),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AccentBadge(icon: icon, color: accentColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFB8C4D9),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _CreateClassMode { fresh, existing }

class _WorkoutCalendarCard extends StatelessWidget {
  const _WorkoutCalendarCard({
    required this.selectedDate,
    required this.items,
    required this.canManage,
    required this.createClassMode,
    required this.onSelectCreateMode,
    required this.onCreateSuccess,
    required this.onDateChanged,
  });

  final DateTime selectedDate;
  final List<ScheduleClass> items;
  final bool canManage;
  final _CreateClassMode? createClassMode;
  final ValueChanged<_CreateClassMode> onSelectCreateMode;
  final Future<void> Function() onCreateSuccess;
  final ValueChanged<DateTime> onDateChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101826),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Workout Calendar',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a date to check whether the gym has a workout scheduled.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFB8C4D9),
            ),
          ),
          const SizedBox(height: 12),
          Theme(
            data: theme.copyWith(
              colorScheme: theme.colorScheme.copyWith(
                primary: const Color(0xFFFF6B2C),
                onPrimary: Colors.white,
                surface: const Color(0xFF101826),
                onSurface: Colors.white,
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF7EE7C6),
                ),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: CalendarDatePicker(
                initialDate: selectedDate,
                firstDate: DateTime.now().subtract(const Duration(days: 30)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                currentDate: DateTime.now(),
                onDateChanged: onDateChanged,
              ),
            ),
          ),
          if (canManage) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () =>
                        onSelectCreateMode(_CreateClassMode.fresh),
                    icon: Icon(
                      createClassMode == _CreateClassMode.fresh
                          ? Icons.close
                          : Icons.add,
                    ),
                    label: Text(
                      createClassMode == _CreateClassMode.fresh
                          ? 'Close New Class'
                          : 'Add New Class',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: items.isEmpty
                        ? null
                        : () =>
                            onSelectCreateMode(_CreateClassMode.existing),
                    icon: Icon(
                      createClassMode == _CreateClassMode.existing
                          ? Icons.close
                          : Icons.history,
                    ),
                    label: Text(
                      createClassMode == _CreateClassMode.existing
                          ? 'Close Existing'
                          : 'Add Existing Class',
                    ),
                  ),
                ),
              ],
            ),
            if (createClassMode != null) ...[
              const SizedBox(height: 12),
              _InlineCreateClassForm(
                selectedDate: selectedDate,
                previousClasses: items,
                initialMode: createClassMode!,
                onSaved: onCreateSuccess,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _InlineCreateClassForm extends ConsumerStatefulWidget {
  const _InlineCreateClassForm({
    required this.selectedDate,
    required this.previousClasses,
    required this.initialMode,
    required this.onSaved,
  });

  final DateTime selectedDate;
  final List<ScheduleClass> previousClasses;
  final _CreateClassMode initialMode;
  final Future<void> Function() onSaved;

  @override
  ConsumerState<_InlineCreateClassForm> createState() =>
      _InlineCreateClassFormState();
}

class _InlineCreateClassFormState
    extends ConsumerState<_InlineCreateClassForm> {
  static const _durationOptions = [30, 45, 60, 75, 90];
  static const _minuteOptions = [0, 15, 30, 45];
  static const _recurrenceOptions = {
    'none': 'Does not repeat',
    'daily': 'Daily',
    'weekly': 'Weekly',
    'monthly': 'Monthly (every 4 weeks)',
  };
  static const _recurrenceOccurrenceCaps = {
    'daily': 365,
    'weekly': 53,
    'monthly': 14,
  };

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _capacityController;
  late final TextEditingController _occurrenceCountController;
  late final TextEditingController _wodDescriptionController;
  late Future<List<ScheduleTrainer>> _trainersFuture;
  int? _selectedPreviousClassId;
  int? _selectedTrainerId;
  late _CreateClassMode _mode;
  late String _selectedRecurrenceFrequency;
  late int _selectedHour;
  late int _selectedMinute;
  late int _selectedDuration;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final defaultStart = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
      widget.selectedDate.day,
      now.hour + 1,
      _nearestMinuteStep(now.minute),
    );
    _selectedHour = defaultStart.hour;
    _selectedMinute = defaultStart.minute;
    _selectedDuration = 60;
    _mode = widget.initialMode;
    _selectedRecurrenceFrequency = 'none';
    _trainersFuture = ref.read(scheduleRepositoryProvider).fetchTrainers();
    _titleController = TextEditingController(text: 'WOD');
    _capacityController = TextEditingController(text: '12');
    _occurrenceCountController = TextEditingController(text: '4');
    _wodDescriptionController = TextEditingController();
  }

  static int _nearestMinuteStep(int minute) {
    if (minute < 8) return 0;
    if (minute < 23) return 15;
    if (minute < 38) return 30;
    return 45;
  }

  int? _occurrenceCapFor(String recurrenceFrequency) {
    return _recurrenceOccurrenceCaps[recurrenceFrequency];
  }

  String? _occurrenceValidationMessage(String recurrenceFrequency, int parsed) {
    final cap = _occurrenceCapFor(recurrenceFrequency);
    if (cap == null || parsed <= cap) {
      return null;
    }
    return 'Enter $cap or fewer occurrences for $recurrenceFrequency repeats';
  }

  static int _normalizeDuration(int value) {
    if (_durationOptions.contains(value)) {
      return value;
    }
    for (final option in _durationOptions) {
      if (value <= option) {
        return option;
      }
    }
    return _durationOptions.last;
  }

  List<ScheduleClass> get _previousClassOptions {
    final seen = <String>{};
    final sorted = [...widget.previousClasses]
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    final unique = <ScheduleClass>[];
    for (final item in sorted) {
      final definitionKey =
          '${item.title.trim().toLowerCase()}|${item.wodDescription.trim().toLowerCase()}';
      if (seen.add(definitionKey)) {
        unique.add(item);
      }
    }
    return unique;
  }

  void _applyPreviousClass(ScheduleClass item) {
    _titleController.text = item.title;
    _capacityController.text = item.capacity.toString();
    _wodDescriptionController.text = item.wodDescription;
    setState(() {
      _selectedPreviousClassId = item.id;
      _selectedTrainerId = item.assignedTrainer?.id;
      _selectedHour = item.startTime.hour;
      _selectedMinute = _nearestMinuteStep(item.startTime.minute);
      _selectedDuration = _normalizeDuration(item.durationMinutes);
    });
  }

  @override
  void didUpdateWidget(covariant _InlineCreateClassForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialMode != widget.initialMode) {
      _mode = widget.initialMode;
      if (_mode == _CreateClassMode.fresh) {
        _selectedPreviousClassId = null;
      }
    }
    if (!_isSameDay(oldWidget.selectedDate, widget.selectedDate)) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _capacityController.dispose();
    _occurrenceCountController.dispose();
    _wodDescriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false) || _isSaving) {
      return;
    }
    setState(() => _isSaving = true);
    final startTime = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
      widget.selectedDate.day,
      _selectedHour,
      _selectedMinute,
    );
    try {
      await ref
          .read(scheduleRepositoryProvider)
          .createClass(
            title: _titleController.text.trim(),
            classType: 'WOD',
            startTime: startTime,
            durationMinutes: _selectedDuration,
            capacity: int.parse(_capacityController.text.trim()),
            trainerUserId: _selectedTrainerId ?? 0,
            wodDescription: _wodDescriptionController.text.trim(),
            recurrenceFrequency: _selectedRecurrenceFrequency,
            occurrenceCount: _selectedRecurrenceFrequency == 'none'
                ? 1
                : int.parse(_occurrenceCountController.text.trim()),
          );
      if (!mounted) {
        return;
      }
      await widget.onSaved();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Class created.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to save class'),
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
    final localizations = MaterialLocalizations.of(context);
    final previewStart = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
      widget.selectedDate.day,
      _selectedHour,
      _selectedMinute,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('New Class', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '${localizations.formatFullDate(previewStart)} ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(previewStart))}',
            ),
            if (_mode == _CreateClassMode.existing &&
                _previousClassOptions.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                key: ValueKey('existing-class-$_selectedPreviousClassId'),
                initialValue: _selectedPreviousClassId,
                decoration: const InputDecoration(
                  labelText: 'Select Existing Class',
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Choose a class'),
                  ),
                  for (final item in _previousClassOptions)
                    DropdownMenuItem<int?>(
                      value: item.id,
                      child: Text(
                        '${item.title} • ${item.durationMinutes} min • ${item.capacity} spots',
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    setState(() {
                      _selectedPreviousClassId = null;
                    });
                    return;
                  }
                  final selected = widget.previousClasses.firstWhere(
                    (item) => item.id == value,
                  );
                  _applyPreviousClass(selected);
                },
              ),
            ],
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
                return DropdownButtonFormField<int>(
                  initialValue: _selectedTrainerId,
                  decoration: const InputDecoration(labelText: 'Trainer'),
                  items: [
                    for (final trainer in trainers)
                      DropdownMenuItem<int>(
                        value: trainer.id,
                        child: Text(trainer.label),
                      ),
                  ],
                  validator: (value) =>
                      value == null ? 'Select a trainer' : null,
                  onChanged: (value) {
                    setState(() => _selectedTrainerId = value);
                  },
                );
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Enter a title';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('hour-$_selectedHour'),
                    initialValue: _selectedHour,
                    decoration: const InputDecoration(labelText: 'Hour'),
                    items: [
                      for (var hour = 0; hour < 24; hour++)
                        DropdownMenuItem(
                          value: hour,
                          child: Text(hour.toString().padLeft(2, '0')),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedHour = value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('minute-$_selectedMinute'),
                    initialValue: _selectedMinute,
                    decoration: const InputDecoration(labelText: 'Minute'),
                    items: [
                      for (final minute in _minuteOptions)
                        DropdownMenuItem(
                          value: minute,
                          child: Text(minute.toString().padLeft(2, '0')),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedMinute = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey('duration-$_selectedDuration'),
              initialValue: _selectedDuration,
              decoration: const InputDecoration(
                labelText: 'Duration (minutes)',
              ),
              items: [
                for (final duration in _durationOptions)
                  DropdownMenuItem(
                    value: duration,
                    child: Text('$duration min'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedDuration = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _capacityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Capacity'),
              validator: (value) {
                final parsed = int.tryParse((value ?? '').trim());
                if (parsed == null || parsed <= 0) {
                  return 'Enter a valid capacity';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _wodDescriptionController,
              decoration: const InputDecoration(labelText: 'WOD Description'),
              minLines: 3,
              maxLines: 5,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedRecurrenceFrequency,
              decoration: const InputDecoration(labelText: 'Repeat'),
              items: [
                for (final entry in _recurrenceOptions.entries)
                  DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedRecurrenceFrequency = value);
                }
              },
            ),
            if (_selectedRecurrenceFrequency != 'none') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _occurrenceCountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Occurrences'),
                validator: (value) {
                  final parsed = int.tryParse((value ?? '').trim());
                  if (parsed == null || parsed <= 0) {
                    return 'Enter a valid occurrence count';
                  }
                  final capError = _occurrenceValidationMessage(
                    _selectedRecurrenceFrequency,
                    parsed,
                  );
                  if (capError != null) {
                    return capError;
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isSaving ? null : _submit,
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Class'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleClassCard extends StatelessWidget {
  const _ScheduleClassCard({
    required this.item,
    required this.canManage,
    required this.onToggleBooking,
    required this.onToggleWaitlist,
    required this.onUpdateAttendance,
    required this.onEdit,
    required this.onDelete,
  });

  final ScheduleClass item;
  final bool canManage;
  final VoidCallback onToggleBooking;
  final VoidCallback onToggleWaitlist;
  final Future<void> Function(ScheduleBooking booking, String attendanceStatus)
  onUpdateAttendance;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = MaterialLocalizations.of(
      context,
    ).formatFullDate(item.startTime);
    final startTime = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(item.startTime));
    final isFuture = item.startTime.isAfter(DateTime.now());
    final canManageAttendance = canManage && !isFuture;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101826),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5FB2FF).withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
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
                      item.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _HeroPill(label: item.classType, color: const Color(0xFFFF6B2C)),
                        _HeroPill(label: startTime, color: const Color(0xFF5FB2FF)),
                        _HeroPill(label: '${item.durationMinutes} min', color: const Color(0xFF7EE7C6)),
                      ],
                    ),
                  ],
                ),
              ),
              if (canManage && isFuture)
                IconButton.filledTonal(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit',
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            date,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFB8C4D9),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricTile(label: 'Bookings', value: '${item.bookedCount}/${item.capacity}', accentColor: const Color(0xFFFF6B2C)),
              _MetricTile(label: 'Open spots', value: '${item.remainingSpots}', accentColor: const Color(0xFF7EE7C6)),
              if (item.waitlistCount > 0)
                _MetricTile(label: 'Waitlist', value: '${item.waitlistCount}', accentColor: const Color(0xFFB98CFF)),
            ],
          ),
          if (item.assignedTrainer != null) ...[
            const SizedBox(height: 14),
            _DetailLine(label: 'Trainer', value: item.assignedTrainer!.label),
          ],
          if (item.wodDescription.isNotEmpty) ...[
            const SizedBox(height: 14),
            _ContentPanel(
              label: 'WOD',
              accentColor: const Color(0xFFFF6B2C),
              child: Text(
                item.wodDescription,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  height: 1.45,
                ),
              ),
            ),
          ],
          if (item.attendanceStatus != null || item.isWaitlisted) ...[
            const SizedBox(height: 14),
            _ContentPanel(
              label: 'Your Status',
              accentColor: const Color(0xFF7EE7C6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.attendanceStatus != null)
                    Text(
                      'Attendance: ${_attendanceLabel(item.attendanceStatus!)}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
                    ),
                  if (item.isWaitlisted)
                    Text(
                      'Waitlist: Active',
                      style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
                    ),
                ],
              ),
            ),
          ],
          if (isFuture) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (item.isBooked)
                  OutlinedButton(
                    onPressed: onToggleBooking,
                    child: const Text('Cancel Booking'),
                  )
                else if (item.isWaitlisted)
                  OutlinedButton(
                    onPressed: onToggleWaitlist,
                    child: const Text('Leave Waitlist'),
                  )
                else
                  FilledButton(
                    onPressed: item.isFull ? onToggleWaitlist : onToggleBooking,
                    child: Text(item.isFull ? 'Join Waitlist' : 'Book Class'),
                  ),
                if (canManage) ...[
                  OutlinedButton(
                    onPressed: onEdit,
                    child: const Text('Edit'),
                  ),
                  OutlinedButton(
                    onPressed: onDelete,
                    child: const Text('Delete'),
                  ),
                ],
              ],
            ),
          ],
          if (item.bookings.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: Color(0x1FFFFFFF)),
            const SizedBox(height: 12),
            Text(
              'Booked Members',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            for (final booking in item.bookings) ...[
              _AttendanceRow(
                booking: booking,
                canManageAttendance: canManageAttendance,
                onUpdateAttendance: onUpdateAttendance,
              ),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }

  static String _attendanceLabel(String value) {
    switch (value) {
      case 'attended':
        return 'Attended';
      case 'no_show':
        return 'No Show';
      default:
        return 'Booked';
    }
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _isSameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.accentColor,
  });

  final String label;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 104),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withOpacity(0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: accentColor,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodyMedium?.copyWith(
          color: const Color(0xFFB8C4D9),
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

class _ContentPanel extends StatelessWidget {
  const _ContentPanel({
    required this.label,
    required this.accentColor,
    required this.child,
  });

  final String label;
  final Color accentColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: accentColor,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({
    required this.label,
    required this.color,
    this.outlined = false,
  });

  final String label;
  final Color color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(outlined ? 0.55 : 0.3)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withOpacity(0.95),
              color.withOpacity(0.0),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentBadge extends StatelessWidget {
  const _AccentBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(0.28),
                color.withOpacity(0.12),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.28)),
          ),
          child: Icon(icon, color: color),
        ),
      ),
    );
  }
}

class _AttendanceRow extends StatelessWidget {
  const _AttendanceRow({
    required this.booking,
    required this.canManageAttendance,
    required this.onUpdateAttendance,
  });

  final ScheduleBooking booking;
  final bool canManageAttendance;
  final Future<void> Function(ScheduleBooking booking, String attendanceStatus)
  onUpdateAttendance;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                booking.displayName.isEmpty
                    ? booking.nickname
                    : booking.displayName,
              ),
            ),
            Material(
              color: Colors.transparent,
              child: Chip(label: Text(_labelFor(booking.attendanceStatus))),
            ),
          ],
        ),
        if (canManageAttendance)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: booking.attendanceStatus == 'booked'
                    ? null
                    : () => onUpdateAttendance(booking, 'booked'),
                child: const Text('Reset'),
              ),
              OutlinedButton(
                onPressed: booking.attendanceStatus == 'attended'
                    ? null
                    : () => onUpdateAttendance(booking, 'attended'),
                child: const Text('Attended'),
              ),
              OutlinedButton(
                onPressed: booking.attendanceStatus == 'no_show'
                    ? null
                    : () => onUpdateAttendance(booking, 'no_show'),
                child: const Text('No Show'),
              ),
            ],
          ),
      ],
    );
  }

  static String _labelFor(String value) {
    switch (value) {
      case 'attended':
        return 'Attended';
      case 'no_show':
        return 'No Show';
      default:
        return 'Booked';
    }
  }
}

class _ScheduleClassDialog extends ConsumerStatefulWidget {
  const _ScheduleClassDialog({this.existing});

  final ScheduleClass? existing;

  @override
  ConsumerState<_ScheduleClassDialog> createState() =>
      _ScheduleClassDialogState();
}

class _ScheduleClassDialogState extends ConsumerState<_ScheduleClassDialog> {
  static const _durationOptions = [30, 45, 60, 75, 90];
  static const _minuteOptions = [0, 15, 30, 45];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _capacityController;
  late final TextEditingController _wodDescriptionController;
  late Future<List<ScheduleTrainer>> _trainersFuture;
  late DateTime _startTime;
  int? _selectedTrainerId;
  late int _selectedDuration;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final defaultStart = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour + 1,
      _nearestMinuteStep(now.minute),
    );
    _startTime = _normalizeStartTime(
      widget.existing?.startTime ?? defaultStart,
    );
    _trainersFuture = ref.read(scheduleRepositoryProvider).fetchTrainers();
    _selectedTrainerId = widget.existing?.assignedTrainer?.id;
    _titleController = TextEditingController(
      text: widget.existing?.title ?? 'WOD',
    );
    _capacityController = TextEditingController(
      text: '${widget.existing?.capacity ?? 12}',
    );
    _wodDescriptionController = TextEditingController(
      text: widget.existing?.wodDescription ?? '',
    );
    _selectedDuration = _normalizeDuration(
      widget.existing?.durationMinutes ?? 60,
    );
  }

  static DateTime _normalizeStartTime(DateTime value) {
    return DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      _nearestMinuteStep(value.minute),
    );
  }

  static int _nearestMinuteStep(int minute) {
    if (minute < 8) {
      return 0;
    }
    if (minute < 23) {
      return 15;
    }
    if (minute < 38) {
      return 30;
    }
    if (minute < 53) {
      return 45;
    }
    return 45;
  }

  static int _normalizeDuration(int value) {
    if (_durationOptions.contains(value)) {
      return value;
    }
    for (final option in _durationOptions) {
      if (value <= option) {
        return option;
      }
    }
    return _durationOptions.last;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _capacityController.dispose();
    _wodDescriptionController.dispose();
    super.dispose();
  }

  void _updateStartDate(DateTime nextDate) {
    setState(() {
      _startTime = DateTime(
        nextDate.year,
        nextDate.month,
        nextDate.day,
        _startTime.hour,
        _startTime.minute,
      );
    });
  }

  void _updateStartHour(int hour) {
    setState(() {
      _startTime = DateTime(
        _startTime.year,
        _startTime.month,
        _startTime.day,
        hour,
        _startTime.minute,
      );
    });
  }

  void _updateStartMinute(int minute) {
    setState(() {
      _startTime = DateTime(
        _startTime.year,
        _startTime.month,
        _startTime.day,
        _startTime.hour,
        minute,
      );
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false) || _isSaving) {
      return;
    }
    final capacity = int.parse(_capacityController.text.trim());
    final wodDescription = _wodDescriptionController.text.trim();
    setState(() => _isSaving = true);
    try {
      final repository = ref.read(scheduleRepositoryProvider);
      if (widget.existing == null) {
        await repository.createClass(
          title: _titleController.text.trim(),
          classType: 'WOD',
          startTime: _startTime,
          durationMinutes: _selectedDuration,
          capacity: capacity,
          trainerUserId: _selectedTrainerId ?? 0,
          wodDescription: wodDescription,
        );
      } else {
        await repository.updateClass(
          id: widget.existing!.id,
          title: _titleController.text.trim(),
          classType: widget.existing!.classType,
          startTime: _startTime,
          durationMinutes: _selectedDuration,
          capacity: capacity,
          trainerUserId: _selectedTrainerId ?? 0,
          wodDescription: wodDescription,
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
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to save class'),
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
    final localizations = MaterialLocalizations.of(context);
    final selectedDay = _dateOnly(_startTime);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing == null ? 'Add Class' : 'Edit Class',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _titleController,
                          decoration: const InputDecoration(labelText: 'Title'),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Enter a title';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        FutureBuilder<List<ScheduleTrainer>>(
                          future: _trainersFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: LinearProgressIndicator(),
                              );
                            }
                            final trainers =
                                snapshot.data ?? const <ScheduleTrainer>[];
                            return DropdownButtonFormField<int>(
                              initialValue: _selectedTrainerId,
                              decoration: const InputDecoration(
                                labelText: 'Trainer',
                              ),
                              items: [
                                for (final trainer in trainers)
                                  DropdownMenuItem<int>(
                                    value: trainer.id,
                                    child: Text(trainer.label),
                                  ),
                              ],
                              validator: (value) =>
                                  value == null ? 'Select a trainer' : null,
                              onChanged: (value) {
                                setState(() => _selectedTrainerId = value);
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'Start: ${localizations.formatFullDate(_startTime)} ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(_startTime))}',
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 320,
                          child: CalendarDatePicker(
                            initialDate: selectedDay,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                            currentDate: DateTime.now(),
                            onDateChanged: _updateStartDate,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                initialValue: _startTime.hour,
                                decoration: const InputDecoration(
                                  labelText: 'Hour',
                                ),
                                items: [
                                  for (var hour = 0; hour < 24; hour++)
                                    DropdownMenuItem(
                                      value: hour,
                                      child: Text(
                                        hour.toString().padLeft(2, '0'),
                                      ),
                                    ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    _updateStartHour(value);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                initialValue: _startTime.minute,
                                decoration: const InputDecoration(
                                  labelText: 'Minute',
                                ),
                                items: [
                                  for (final minute in _minuteOptions)
                                    DropdownMenuItem(
                                      value: minute,
                                      child: Text(
                                        minute.toString().padLeft(2, '0'),
                                      ),
                                    ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    _updateStartMinute(value);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: _selectedDuration,
                          decoration: const InputDecoration(
                            labelText: 'Duration (minutes)',
                          ),
                          items: [
                            for (final duration in _durationOptions)
                              DropdownMenuItem(
                                value: duration,
                                child: Text('$duration min'),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedDuration = value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _capacityController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Capacity',
                          ),
                          validator: (value) {
                            final parsed = int.tryParse((value ?? '').trim());
                            if (parsed == null || parsed <= 0) {
                              return 'Enter a valid capacity';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _wodDescriptionController,
                          decoration: const InputDecoration(
                            labelText: 'WOD Description',
                          ),
                          minLines: 3,
                          maxLines: 5,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _isSaving ? null : _submit,
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
