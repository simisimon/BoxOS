import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/schedule_booking.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:app/features/calendar/domain/models/schedule_trainer.dart';
import 'package:app/features/programming/presentation/screens/import_workouts_dialog.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:app/features/programming/presentation/widgets/wod_day_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MyBoxScreen extends ConsumerStatefulWidget {
  const MyBoxScreen({super.key});

  @override
  ConsumerState<MyBoxScreen> createState() => _MyBoxScreenState();
}

class _MyBoxScreenState extends ConsumerState<MyBoxScreen> {
  /// First day of the month currently shown in the grid.
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
  }

  Future<void> _refresh() async {
    ref.invalidate(scheduleListProvider);
    await ref.read(scheduleListProvider.future);
  }

  void _showSnackBar(String message) {
    if (!mounted || Scaffold.maybeOf(context) == null) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _goToPreviousMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
    });
  }

  void _goToNextMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
    });
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _visibleMonth = DateTime(now.year, now.month);
    });
  }

  /// The day whose side panel is open, or null when the calendar is full-width.
  DateTime? _selectedDay;

  void _selectDay(DateTime day) {
    setState(() => _selectedDay = _dateOnly(day));
  }

  void _closeDay() {
    setState(() => _selectedDay = null);
  }

  Future<void> _openImport() async {
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const ImportWorkoutsDialog(),
    );
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
    final scheduleAsync = ref.watch(scheduleListProvider);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            appPageBackground,
            appPageBackgroundSoft,
            appPageBackgroundEnd,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: profile?.activeGym == null
            ? const Center(
                child: _CalendarStateCard(
                  icon: Icons.store_mall_directory_outlined,
                  title: 'No active gym selected',
                  message:
                      'Join or switch to a gym to use the schedule, bookings, waitlist, and attendance tools.',
                  accentColor: appPrimary,
                ),
              )
            : scheduleAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: _CalendarStateCard(
                    icon: Icons.error_outline,
                    title: 'Failed to load schedule',
                    message: errorMessageFrom(
                      error,
                      fallback: 'Failed to load schedule',
                    ),
                    accentColor: appPrimary,
                  ),
                ),
                data: (items) => _buildScheduleBody(context, items, canManage),
              ),
      ),
    );
  }

  Widget _buildScheduleBody(
    BuildContext context,
    List<ScheduleClass> items,
    bool canManage,
  ) {
    final calendar = _MonthCalendar(
      month: _visibleMonth,
      items: items,
      today: _dateOnly(DateTime.now()),
      selectedDay: _selectedDay,
      canManage: canManage,
      onPrevMonth: _goToPreviousMonth,
      onNextMonth: _goToNextMonth,
      onToday: _goToToday,
      onRefresh: _refresh,
      onImport: canManage ? _openImport : null,
      onSelectDay: _selectDay,
    );

    if (_selectedDay == null) {
      return calendar;
    }

    final panel = _DayPanel(
      key: ValueKey(_selectedDay),
      date: _selectedDay!,
      canManage: canManage,
      onClose: _closeDay,
      onToggleBooking: _toggleBooking,
      onToggleWaitlist: _toggleWaitlist,
      onUpdateAttendance: (item, booking, status) => _updateAttendance(
        item: item,
        booking: booking,
        attendanceStatus: status,
      ),
      onDelete: (item) => _deleteClass(item, canManage),
    );

    // Wide windows show the day panel inline on the left, next to the calendar;
    // narrow windows swap the calendar out for the full-width panel.
    final isWide = MediaQuery.sizeOf(context).width >= 640;
    if (!isWide) {
      return panel;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 360, child: panel),
        const SizedBox(width: 12),
        Expanded(child: calendar),
      ],
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
        color: appSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: appBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAccentBadge(icon: icon, color: accentColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: appText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: appSubtleText,
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

/// Month grid calendar: a header with month navigation + Today, a weekday row,
/// and a 6×7 grid of day cells that surface each day's classes as colored bars.
/// Tapping a day opens the day-detail sheet (see [_DayScheduleSheet]).
class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.items,
    required this.today,
    required this.selectedDay,
    required this.canManage,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onToday,
    required this.onRefresh,
    required this.onImport,
    required this.onSelectDay,
  });

  /// First day of the displayed month.
  final DateTime month;
  final List<ScheduleClass> items;
  final DateTime today;
  final DateTime? selectedDay;
  final bool canManage;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToday;
  final Future<void> Function() onRefresh;

  /// Opens the CSV import flow. Null hides the button (non-managers).
  final VoidCallback? onImport;
  final ValueChanged<DateTime> onSelectDay;

  static const _weekdayLabels = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthLabel = MaterialLocalizations.of(context).formatMonthYear(month);
    final firstOfMonth = DateTime(month.year, month.month, 1);
    // Grid starts on the Monday on or before the 1st of the month.
    final gridStart =
        firstOfMonth.subtract(Duration(days: firstOfMonth.weekday - 1));

    // Bucket classes by their local calendar day for quick per-cell lookup.
    final eventsByDay = <DateTime, List<ScheduleClass>>{};
    for (final item in items) {
      final day = _dateOnly(item.startTime);
      (eventsByDay[day] ??= <ScheduleClass>[]).add(item);
    }
    for (final dayItems in eventsByDay.values) {
      dayItems.sort((a, b) => a.startTime.compareTo(b.startTime));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  monthLabel,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: appText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _CalendarHeaderButton(label: 'Today', onTap: onToday),
              const SizedBox(width: 8),
              if (onImport != null) ...[
                _CalendarIconButton(
                  icon: Icons.upload_file_rounded,
                  tooltip: 'Import WODs',
                  onTap: onImport!,
                ),
                const SizedBox(width: 6),
              ],
              _CalendarIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh',
                onTap: () => onRefresh(),
              ),
              const SizedBox(width: 6),
              _CalendarIconButton(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Previous month',
                onTap: onPrevMonth,
              ),
              const SizedBox(width: 6),
              _CalendarIconButton(
                icon: Icons.chevron_right_rounded,
                tooltip: 'Next month',
                onTap: onNextMonth,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final label in _weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      label.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: appSubtleText,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // The grid fills the remaining height — each week splits the space
          // evenly so the calendar stretches across the whole screen.
          Expanded(
            child: Column(
              children: [
                for (var week = 0; week < 6; week++)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var dow = 0; dow < 7; dow++)
                          Builder(
                            builder: (context) {
                              final day = _dateOnly(
                                gridStart.add(Duration(days: week * 7 + dow)),
                              );
                              return Expanded(
                                child: _MonthDayCell(
                                  day: day,
                                  inMonth: day.month == month.month,
                                  isToday: _isSameDay(day, today),
                                  isSelected: selectedDay != null &&
                                      _isSameDay(day, selectedDay!),
                                  events: eventsByDay[day] ??
                                      const <ScheduleClass>[],
                                  onTap: onSelectDay,
                                ),
                              );
                            },
                          ),
                      ],
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

class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.events,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final List<ScheduleClass> events;
  final ValueChanged<DateTime> onTap;

  static const _maxBars = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = events.take(_maxBars).toList();
    final extra = events.length - shown.length;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onTap(day),
          child: Container(
            clipBehavior: Clip.hardEdge,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isSelected
                  ? appPrimarySoft
                  : (inMonth ? appSurfaceAlt : Colors.transparent),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected || isToday ? appPrimary : appBorder,
                width: isSelected || isToday ? 1.4 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: isToday
                        ? const BoxDecoration(
                            color: appPrimary,
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Text(
                      '${day.day}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isToday
                            ? Colors.white
                            : (inMonth ? appText : appSubtleText),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final event in shown)
                        Container(
                          margin: const EdgeInsets.only(bottom: 2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: appPrimary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            event.title,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            softWrap: false,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (extra > 0)
                        Text(
                          '+$extra more',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: appSubtleText,
                            fontSize: 8,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarIconButton extends StatelessWidget {
  const _CalendarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: appSurfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: appBorder),
            ),
            child: Icon(icon, color: appText, size: 22),
          ),
        ),
      ),
    );
  }
}

class _CalendarHeaderButton extends StatelessWidget {
  const _CalendarHeaderButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: appSurfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: appBorder),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: appText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet listing a single day's classes, with an "Add Class" entry for
/// managers. Watches [scheduleListProvider] so bookings/creates/deletes update
/// it live (the parent invalidates the provider after each mutation).
/// Side panel shown to the left of the calendar when a day is selected. Lists
/// that day's classes and hosts the inline add/edit form. Watches
/// [scheduleListProvider] so it stays in sync with the calendar.
class _DayPanel extends ConsumerStatefulWidget {
  const _DayPanel({
    super.key,
    required this.date,
    required this.canManage,
    required this.onClose,
    required this.onToggleBooking,
    required this.onToggleWaitlist,
    required this.onUpdateAttendance,
    required this.onDelete,
  });

  final DateTime date;
  final bool canManage;
  final VoidCallback onClose;
  final void Function(ScheduleClass item) onToggleBooking;
  final void Function(ScheduleClass item) onToggleWaitlist;
  final Future<void> Function(
    ScheduleClass item,
    ScheduleBooking booking,
    String attendanceStatus,
  ) onUpdateAttendance;
  final void Function(ScheduleClass item) onDelete;

  @override
  ConsumerState<_DayPanel> createState() => _DayPanelState();
}

class _DayPanelState extends ConsumerState<_DayPanel> {
  bool _showForm = false;
  ScheduleClass? _editing;

  /// Classes can only be created from today onward.
  bool get _isPastDay =>
      _dateOnly(widget.date).isBefore(_dateOnly(DateTime.now()));

  void _openAdd() {
    setState(() {
      _editing = null;
      _showForm = true;
    });
  }

  void _openEdit(ScheduleClass item) {
    setState(() {
      _editing = item;
      _showForm = true;
    });
  }

  void _closeForm() {
    setState(() {
      _editing = null;
      _showForm = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel =
        MaterialLocalizations.of(context).formatFullDate(widget.date);
    final scheduleAsync = ref.watch(scheduleListProvider);
    final dayItems = scheduleAsync.maybeWhen(
      data: (items) =>
          items.where((item) => _isSameDay(item.startTime, widget.date)).toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime)),
      orElse: () => const <ScheduleClass>[],
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SCHEDULE',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: appPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: appText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _showForm ? _closeForm : widget.onClose,
                  icon: const Icon(Icons.close_rounded, color: appText),
                  tooltip: _showForm ? 'Back' : 'Close',
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: appBorder),
          Expanded(
            child: _showForm
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _ClassForm(
                      date: widget.date,
                      existing: _editing,
                      onSaved: _closeForm,
                      onCancel: _closeForm,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      WodDaySection(
                        date: widget.date,
                        canManage: widget.canManage,
                      ),
                      const SizedBox(height: 18),
                      _SectionLabel(
                        icon: Icons.event_outlined,
                        label: 'Classes',
                      ),
                      const SizedBox(height: 10),
                      if (widget.canManage && !_isPastDay) ...[
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _openAdd,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Class'),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ] else if (widget.canManage && _isPastDay) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: appSurfaceAlt,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: appBorder),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.history_rounded,
                                size: 18,
                                color: appSubtleText,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'This day is in the past — new classes can '
                                  'only be added from today onward.',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: appSubtleText),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (dayItems.isEmpty)
                        _CalendarStateCard(
                          icon: widget.canManage
                              ? Icons.edit_calendar_outlined
                              : Icons.event_busy_outlined,
                          title: 'No classes scheduled',
                          message: widget.canManage
                              ? 'Nothing is scheduled on this day yet. Use "Add Class" to open the day.'
                              : 'No classes are scheduled on this date.',
                          accentColor: appPrimary,
                        )
                      else
                        for (final item in dayItems) ...[
                          _ScheduleClassCard(
                            item: item,
                            canManage: widget.canManage,
                            onToggleBooking: () => widget.onToggleBooking(item),
                            onToggleWaitlist: () =>
                                widget.onToggleWaitlist(item),
                            onUpdateAttendance: (booking, status) =>
                                widget.onUpdateAttendance(item, booking, status),
                            onEdit: () => _openEdit(item),
                            onDelete: () => widget.onDelete(item),
                          ),
                          const SizedBox(height: 12),
                        ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: appPrimary, size: 16),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: appPrimary,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
      ],
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
        color: appSurface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: appBorder),
        boxShadow: [
          BoxShadow(
            color: appPrimary.withOpacity(0.08),
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
                        color: appText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _HeroPill(label: item.classType, color: appPrimary),
                        _HeroPill(label: startTime, color: appPrimary),
                        _HeroPill(
                          label: '${item.durationMinutes} min',
                          color: appPrimary,
                        ),
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
            style: theme.textTheme.bodyMedium?.copyWith(color: appSubtleText),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricTile(
                label: 'Bookings',
                value: '${item.bookedCount}/${item.capacity}',
                accentColor: appPrimary,
              ),
              _MetricTile(
                label: 'Open spots',
                value: '${item.remainingSpots}',
                accentColor: appPrimary,
              ),
              if (item.waitlistCount > 0)
                _MetricTile(
                  label: 'Waitlist',
                  value: '${item.waitlistCount}',
                  accentColor: appPrimary,
                ),
            ],
          ),
          if (item.assignedTrainer != null) ...[
            const SizedBox(height: 14),
            _DetailLine(label: 'Trainer', value: item.assignedTrainer!.label),
          ],
          if (item.attendanceStatus != null || item.isWaitlisted) ...[
            const SizedBox(height: 14),
            _ContentPanel(
              label: 'Your Status',
              accentColor: appPrimary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.attendanceStatus != null)
                    Text(
                      'Attendance: ${_attendanceLabel(item.attendanceStatus!)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: appText,
                      ),
                    ),
                  if (item.isWaitlisted)
                    Text(
                      'Waitlist: Active',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: appText,
                      ),
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
                  OutlinedButton(onPressed: onEdit, child: const Text('Edit')),
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
            const Divider(color: appBorder),
            const SizedBox(height: 12),
            Text(
              'Booked Members',
              style: theme.textTheme.titleMedium?.copyWith(
                color: appText,
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
              color: appText,
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
        style: theme.textTheme.bodyMedium?.copyWith(color: appSubtleText),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(color: appText, fontWeight: FontWeight.w700),
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
  const _HeroPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: appText,
          fontWeight: FontWeight.w700,
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

/// Inline create/edit form rendered inside the day side panel. On save it
/// writes through the repository, invalidates [scheduleListProvider] (so the
/// panel list and the calendar refresh), then calls [onSaved].
class _ClassForm extends ConsumerStatefulWidget {
  const _ClassForm({
    required this.date,
    this.existing,
    required this.onSaved,
    required this.onCancel,
  });

  /// The day this class belongs to (from the tapped calendar cell).
  final DateTime date;
  final ScheduleClass? existing;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  @override
  ConsumerState<_ClassForm> createState() => _ClassFormState();
}

class _ClassFormState extends ConsumerState<_ClassForm> {
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
  late Future<List<ScheduleTrainer>> _trainersFuture;
  late int _selectedHour;
  late int _selectedMinute;
  int? _selectedTrainerId;
  late int _selectedDuration;
  String _recurrenceFrequency = 'none';
  bool _isSaving = false;

  bool get _isCreating => widget.existing == null;

  DateTime get _baseDate => _dateOnly(widget.existing?.startTime ?? widget.date);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final base = widget.existing?.startTime;
    _selectedHour = base?.hour ?? ((now.hour + 1) % 24);
    _selectedMinute = _nearestMinuteStep(base?.minute ?? now.minute);
    _selectedDuration = _normalizeDuration(widget.existing?.durationMinutes ?? 60);
    _selectedTrainerId = widget.existing?.assignedTrainer?.id;
    _trainersFuture = ref.read(scheduleRepositoryProvider).fetchTrainers();
    _titleController =
        TextEditingController(text: widget.existing?.title ?? 'WOD');
    _capacityController =
        TextEditingController(text: '${widget.existing?.capacity ?? 12}');
    _occurrenceCountController = TextEditingController(text: '4');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _capacityController.dispose();
    _occurrenceCountController.dispose();
    super.dispose();
  }

  static int _nearestMinuteStep(int minute) {
    if (minute < 8) return 0;
    if (minute < 23) return 15;
    if (minute < 38) return 30;
    return 45;
  }

  static int _normalizeDuration(int value) {
    if (_durationOptions.contains(value)) return value;
    for (final option in _durationOptions) {
      if (value <= option) return option;
    }
    return _durationOptions.last;
  }

  String? _occurrenceValidationMessage(String recurrenceFrequency, int parsed) {
    final cap = _recurrenceOccurrenceCaps[recurrenceFrequency];
    if (cap == null || parsed <= cap) return null;
    return 'Enter $cap or fewer occurrences for $recurrenceFrequency repeats';
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false) || _isSaving) {
      return;
    }
    // Guard against creating/moving a class onto a past day, regardless of how
    // the form was reached.
    if (_baseDate.isBefore(_dateOnly(DateTime.now()))) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Classes can only be scheduled from today onward.'),
        ),
      );
      return;
    }
    final capacity = int.parse(_capacityController.text.trim());
    final startTime = DateTime(
      _baseDate.year,
      _baseDate.month,
      _baseDate.day,
      _selectedHour,
      _selectedMinute,
    );
    setState(() => _isSaving = true);
    try {
      final repository = ref.read(scheduleRepositoryProvider);
      if (_isCreating) {
        await repository.createClass(
          title: _titleController.text.trim(),
          classType: 'WOD',
          startTime: startTime,
          durationMinutes: _selectedDuration,
          capacity: capacity,
          trainerUserId: _selectedTrainerId ?? 0,
          recurrenceFrequency: _recurrenceFrequency,
          occurrenceCount: _recurrenceFrequency == 'none'
              ? 1
              : int.parse(_occurrenceCountController.text.trim()),
        );
      } else {
        await repository.updateClass(
          id: widget.existing!.id,
          title: _titleController.text.trim(),
          classType: widget.existing!.classType,
          startTime: startTime,
          durationMinutes: _selectedDuration,
          capacity: capacity,
          trainerUserId: _selectedTrainerId ?? 0,
        );
      }
      ref.invalidate(scheduleListProvider);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(_isCreating ? 'Class created.' : 'Class updated.'),
        ),
      );
      widget.onSaved();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(errorMessageFrom(error, fallback: 'Failed to save class')),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isCreating ? 'New class' : 'Edit class',
            style: theme.textTheme.titleMedium?.copyWith(
              color: appText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            localizations.formatFullDate(_baseDate),
            style: theme.textTheme.bodySmall?.copyWith(color: appSubtleText),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Title'),
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Enter a title' : null,
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
              return DropdownButtonFormField<int>(
                initialValue: _selectedTrainerId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Trainer'),
                items: [
                  for (final trainer in trainers)
                    DropdownMenuItem<int>(
                      value: trainer.id,
                      child: Text(trainer.label),
                    ),
                ],
                validator: (value) => value == null ? 'Select a trainer' : null,
                onChanged: (value) => setState(() => _selectedTrainerId = value),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
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
                    if (value != null) setState(() => _selectedHour = value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
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
                    if (value != null) setState(() => _selectedMinute = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _selectedDuration,
            decoration: const InputDecoration(labelText: 'Duration (minutes)'),
            items: [
              for (final duration in _durationOptions)
                DropdownMenuItem(value: duration, child: Text('$duration min')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _selectedDuration = value);
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
          if (_isCreating) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _recurrenceFrequency,
              isExpanded: true,
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
                  setState(() => _recurrenceFrequency = value);
                }
              },
            ),
            if (_recurrenceFrequency != 'none') ...[
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
                  return _occurrenceValidationMessage(
                    _recurrenceFrequency,
                    parsed,
                  );
                },
              ),
            ],
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving ? null : widget.onCancel,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _isSaving ? null : _submit,
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isCreating ? 'Create' : 'Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Mutable draft of a single class section, used by the form. Owns its own
/// controllers so the parent only has to dispose the draft when removing it.
