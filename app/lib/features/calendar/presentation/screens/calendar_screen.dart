import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_form_dialog.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/class_type.dart';
import 'package:app/features/calendar/domain/repositories/schedule_repository.dart';
import 'package:app/features/calendar/domain/models/schedule_booking.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:app/features/calendar/domain/models/schedule_trainer.dart';
import 'package:app/features/calendar/presentation/widgets/class_type_badge.dart';
import 'package:app/features/calendar/presentation/widgets/class_template_dialog.dart';
import 'package:app/features/calendar/presentation/widgets/schedule_week_view.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
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
  /// The class whose side panel is open, or null when the week is full-width.
  int? _selectedClassId;

  /// Monday of the week shown; kept here so opening a class keeps the week.
  DateTime _weekStart = mondayOf(DateTime.now());

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
    if (item.classTemplateId != null) {
      final scope = await _askSeriesScope(context, action: 'Delete');
      if (scope == null) {
        return;
      }
      if (scope == _SeriesScope.series) {
        await _deleteSeries(item);
        return;
      }
    }
    if (!mounted) {
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Delete Class',
      message: 'Delete ${item.title} on this schedule?',
      confirmLabel: 'Delete',
      destructive: true,
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

  Future<void> _deleteSeries(ScheduleClass item) async {
    try {
      final kept = await ref
          .read(scheduleRepositoryProvider)
          .deleteTemplate(id: item.classTemplateId!);
      ref.invalidate(classTemplatesProvider);
      await _refresh();
      if (!mounted) {
        return;
      }
      _showSnackBar(
        kept == 0
            ? '${item.title} removed from all upcoming dates.'
            : '${item.title} removed. $kept booked '
                  '${kept == 1 ? 'date stays' : 'dates stay'} on the calendar.',
      );
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

    return AppGridBackground(
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
                loading: () => const Center(child: CircularProgressIndicator()),
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
    final selected = items
        .where((item) => item.id == _selectedClassId)
        .firstOrNull;
    final week = ScheduleWeekView(
      weekStart: _weekStart,
      onWeekChanged: (monday) => setState(() => _weekStart = monday),
      canManage: canManage,
      selectedClassId: selected?.id,
      onOpenClass: (item) => setState(() => _selectedClassId = item.id),
      onAddClass: canManage
          ? (date) => _showClassFormDialog(context, date: date)
          : null,
      onImport: canManage ? _openImport : null,
    );

    // A deleted class simply drops out of [items], which closes the panel.
    if (selected == null) {
      return week;
    }

    final panel = _ClassPanel(
      key: ValueKey(selected.id),
      item: selected,
      canManage: canManage,
      onClose: () => setState(() => _selectedClassId = null),
      onToggleBooking: _toggleBooking,
      onToggleWaitlist: _toggleWaitlist,
      onUpdateAttendance: (item, booking, status) => _updateAttendance(
        item: item,
        booking: booking,
        attendanceStatus: status,
      ),
      onDelete: (item) => _deleteClass(item, canManage),
    );

    // Wide windows show the class panel inline on the left, next to the week;
    // narrow windows swap the week out for the full-width panel.
    final isWide = MediaQuery.sizeOf(context).width >= 640;
    if (!isWide) {
      return panel;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 360, child: panel),
        const SizedBox(width: 12),
        Expanded(child: week),
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
        borderRadius: BorderRadius.circular(8),
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

/// Class form in a dialog: a new class on [date], or edits [existing].
Future<void> _showClassFormDialog(
  BuildContext context, {
  required DateTime date,
  ScheduleClass? existing,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _ClassForm(
      date: date,
      existing: existing,
      onSaved: () => Navigator.of(dialogContext).pop(),
      onCancel: () => Navigator.of(dialogContext).pop(),
    ),
  );
}

/// Side panel for one class, next to the week: booking for athletes,
/// edit/delete and attendance for managers.
class _ClassPanel extends ConsumerWidget {
  const _ClassPanel({
    super.key,
    required this.item,
    required this.canManage,
    required this.onClose,
    required this.onToggleBooking,
    required this.onToggleWaitlist,
    required this.onUpdateAttendance,
    required this.onDelete,
  });

  final ScheduleClass item;
  final bool canManage;
  final VoidCallback onClose;
  final void Function(ScheduleClass item) onToggleBooking;
  final void Function(ScheduleClass item) onToggleWaitlist;
  final Future<void> Function(
    ScheduleClass item,
    ScheduleBooking booking,
    String attendanceStatus,
  )
  onUpdateAttendance;
  final void Function(ScheduleClass item) onDelete;

  Future<void> _openEdit(BuildContext context, WidgetRef ref) async {
    if (item.classTemplateId != null) {
      final scope = await _askSeriesScope(context, action: 'Edit');
      if (scope == null || !context.mounted) {
        return;
      }
      if (scope == _SeriesScope.series) {
        final templates = await ref.read(classTemplatesProvider.future);
        if (!context.mounted) {
          return;
        }
        final template = templates
            .where((candidate) => candidate.id == item.classTemplateId)
            .firstOrNull;
        if (template != null) {
          await showClassTemplateDialog(context, ref, existing: template);
          return;
        }
      }
    }
    if (!context.mounted) {
      return;
    }
    await _showClassFormDialog(
      context,
      date: _dateOnly(item.startTime),
      existing: item,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final date = _dateOnly(item.startTime);
    String? wodTitle;
    for (final workout
        in ref.watch(programmingListProvider).value ?? const []) {
      if (_isSameDay(workout.scheduledDate, date)) {
        wodTitle = workout.title;
        break;
      }
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(8),
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
                        'CLASS',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: appPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        MaterialLocalizations.of(context).formatFullDate(date),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: appText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, color: appText),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: appBorder),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ScheduleClassCard(
                  item: item,
                  wodTitle: wodTitle,
                  canManage: canManage,
                  onToggleBooking: () => onToggleBooking(item),
                  onToggleWaitlist: () => onToggleWaitlist(item),
                  onUpdateAttendance: (booking, status) =>
                      onUpdateAttendance(item, booking, status),
                  onEdit: () => _openEdit(context, ref),
                  onDelete: () => onDelete(item),
                ),
                // Athletes read the WOD here; managers program it in the week.
                if (!canManage && item.type.showsWod) ...[
                  const SizedBox(height: 18),
                  WodDaySection(date: date, canManage: false),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleClassCard extends StatelessWidget {
  const _ScheduleClassCard({
    required this.item,
    required this.wodTitle,
    required this.canManage,
    required this.onToggleBooking,
    required this.onToggleWaitlist,
    required this.onUpdateAttendance,
    required this.onEdit,
    required this.onDelete,
  });

  final ScheduleClass item;

  /// Title of the day's programmed WOD; only shown on WOD-type classes.
  final String? wodTitle;
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
    final isFuture = item.startTime.isAfter(DateTime.now());
    final canManageAttendance = canManage && !isFuture;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ClassCardHeader(item: item, wodTitle: wodTitle),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CapacityBar(
                  booked: item.bookedCount,
                  capacity: item.capacity,
                  waitlist: item.waitlistCount,
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
                if (item.type.showsWod) ...[
                  const SizedBox(height: 14),
                  _DetailLine(
                    label: 'WOD',
                    value: wodTitle ?? 'Not programmed yet',
                  ),
                ],
                if (item.classTemplateId != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Part of the weekly plan',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: appSubtleText,
                    ),
                  ),
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
                          onPressed: item.isFull
                              ? onToggleWaitlist
                              : onToggleBooking,
                          child: Text(
                            item.isFull ? 'Join Waitlist' : 'Book Class',
                          ),
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
          ),
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

/// Summary line of a class: time, title, type, fill.
class _ClassCardHeader extends StatelessWidget {
  const _ClassCardHeader({required this.item, required this.wodTitle});

  final ScheduleClass item;
  final String? wodTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final startTime = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(item.startTime));
    final fillColor = item.waitlistCount > 0 || item.isFull
        ? appDanger
        : appMutedText;
    final subtitle = [
      '${item.durationMinutes} min',
      if (item.assignedTrainer != null) item.assignedTrainer!.label,
      if (item.type.showsWod) 'WOD: ${wodTitle ?? '—'}',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(
              startTime,
              style: appMono(fontSize: 12, color: appText, letterSpacing: 0),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: appText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ClassTypeBadge(type: item.type, dense: true),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: appSubtleText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (item.isBooked || item.isWaitlisted) ...[
            Tooltip(
              message: item.isBooked ? 'You are booked' : 'On the waitlist',
              child: Icon(
                item.isBooked
                    ? Icons.check_circle_rounded
                    : Icons.hourglass_top_rounded,
                size: 16,
                color: item.isBooked ? appSuccess : appWarning,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            '${item.bookedCount}/${item.capacity}',
            style: appMono(fontSize: 11, color: fillColor, letterSpacing: 0),
          ),
        ],
      ),
    );
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _isSameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

/// Capacity fill bar promoting the booked/capacity ratio to a glance-able
/// state. Cyan while there's room, amber as it nears full, danger when full
/// or carrying a waitlist — with the count labelled in the BoxOS mono voice.
class _CapacityBar extends StatelessWidget {
  const _CapacityBar({
    required this.booked,
    required this.capacity,
    required this.waitlist,
  });

  final int booked;
  final int capacity;
  final int waitlist;

  @override
  Widget build(BuildContext context) {
    final fraction = capacity <= 0 ? 0.0 : (booked / capacity).clamp(0.0, 1.0);
    final isFull = capacity > 0 && booked >= capacity;
    final Color fill;
    final String status;
    if (waitlist > 0) {
      fill = appDanger;
      status = '+$waitlist waitlist';
    } else if (isFull) {
      fill = appDanger;
      status = 'Full';
    } else if (fraction >= 0.8) {
      fill = appWarning;
      status = 'Filling up';
    } else {
      fill = appPrimary;
      status = '${capacity - booked} open';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('CAPACITY', style: appMono(fontSize: 9.5, letterSpacing: 1.3)),
            const Spacer(),
            Text(
              '$booked/$capacity · $status',
              style: appMono(fontSize: 10.5, letterSpacing: 0, color: fill),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(appRadiusPill),
          child: Stack(
            children: [
              Container(height: 7, color: appSurfaceAlt),
              FractionallySizedBox(
                widthFactor: fraction == 0 ? 0.02 : fraction,
                child: Container(
                  height: 7,
                  decoration: BoxDecoration(
                    color: fill,
                    boxShadow: [
                      BoxShadow(
                        color: fill.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
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
        borderRadius: BorderRadius.circular(6),
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
        borderRadius: BorderRadius.circular(6),
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

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _capacityController;
  late Future<List<ScheduleTrainer>> _trainersFuture;
  late int _selectedHour;
  late int _selectedMinute;
  int? _selectedTrainerId;
  late int _selectedDuration;
  late ClassType _type;
  bool _repeatsWeekly = false;
  late Set<int> _weekdays;
  bool _isSaving = false;

  bool get _isCreating => widget.existing == null;

  DateTime get _baseDate =>
      _dateOnly(widget.existing?.startTime ?? widget.date);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final base = widget.existing?.startTime;
    _selectedHour = base?.hour ?? ((now.hour + 1) % 24);
    _selectedMinute = _nearestMinuteStep(base?.minute ?? now.minute);
    _selectedDuration = _normalizeDuration(
      widget.existing?.durationMinutes ?? 60,
    );
    _selectedTrainerId = widget.existing?.assignedTrainer?.id;
    _trainersFuture = ref.read(scheduleRepositoryProvider).fetchTrainers();
    _type = widget.existing?.type ?? ClassType.wod;
    _weekdays = {_baseDate.weekday};
    _titleController = TextEditingController(
      text: widget.existing?.title ?? _type.defaultTitle,
    );
    _capacityController = TextEditingController(
      text: '${widget.existing?.capacity ?? 12}',
    );
  }

  void _selectType(ClassType type) {
    setState(() {
      // Follow the type with the title until the user has typed their own.
      if (_titleController.text.trim() == _type.defaultTitle) {
        _titleController.text = type.defaultTitle;
      }
      _type = type;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _capacityController.dispose();
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
    if (_isCreating && _repeatsWeekly && _weekdays.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Select at least one weekday.')),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final repository = ref.read(scheduleRepositoryProvider);
      if (_isCreating && _repeatsWeekly) {
        await repository.createTemplate(
          ClassTemplateDraft(
            title: _titleController.text.trim(),
            classType: _type.wireValue,
            weekdays: _weekdays.toList()..sort(),
            hour: _selectedHour,
            minute: _selectedMinute,
            durationMinutes: _selectedDuration,
            capacity: capacity,
            trainerUserId: _selectedTrainerId,
          ),
        );
        ref.invalidate(classTemplatesProvider);
      } else if (_isCreating) {
        await repository.createClass(
          title: _titleController.text.trim(),
          classType: _type.wireValue,
          startTime: startTime,
          durationMinutes: _selectedDuration,
          capacity: capacity,
          trainerUserId: _selectedTrainerId ?? 0,
        );
      } else {
        await repository.updateClass(
          id: widget.existing!.id,
          title: _titleController.text.trim(),
          classType: _type.wireValue,
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
          content: Text(
            !_isCreating
                ? 'Class updated.'
                : _repeatsWeekly
                ? 'Weekly class created.'
                : 'Class created.',
          ),
        ),
      );
      widget.onSaved();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to save class'),
          ),
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
    final dateLabel = localizations.formatFullDate(_baseDate);
    return AppFormDialog(
      title: _isCreating ? 'New class' : 'Edit class',
      subtitle: widget.existing?.classTemplateId != null
          ? '$dateLabel · changes apply to this date only'
          : dateLabel,
      actions: [
        TextButton(
          onPressed: _isSaving ? null : widget.onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isCreating ? 'Create' : 'Save'),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            const SizedBox(height: 12),
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
                  validator: (value) =>
                      value == null ? 'Select a trainer' : null,
                  onChanged: (value) =>
                      setState(() => _selectedTrainerId = value),
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
                      if (value != null)
                        setState(() => _selectedMinute = value);
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
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Repeats weekly',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: appText,
                          ),
                        ),
                        Text(
                          _repeatsWeekly
                              ? 'Runs every week on the selected days, '
                                    'starting this week.'
                              : 'Happens once on this date.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: appSubtleText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _repeatsWeekly,
                    onChanged: (value) =>
                        setState(() => _repeatsWeekly = value),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_repeatsWeekly)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var day = 1; day <= 7; day++)
                      FilterChip(
                        label: Text(_weekdayShortLabels[day - 1]),
                        selected: _weekdays.contains(day),
                        onSelected: (selected) => setState(
                          () => selected
                              ? _weekdays.add(day)
                              : _weekdays.remove(day),
                        ),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Mutable draft of a single class section, used by the form. Owns its own
/// controllers so the parent only has to dispose the draft when removing it.

const _weekdayShortLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

enum _SeriesScope { single, series }

/// For a session generated from a weekly class: apply [action] to just this
/// date or to the whole series. Null when cancelled.
Future<_SeriesScope?> _askSeriesScope(
  BuildContext context, {
  required String action,
}) {
  return showDialog<_SeriesScope>(
    context: context,
    builder: (dialogContext) => AppFormDialog(
      title: '$action weekly class',
      fitContent: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(dialogContext).pop(_SeriesScope.single),
          child: const Text('Only this date'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(_SeriesScope.series),
          child: const Text('All upcoming dates'),
        ),
      ],
      child: Text(
        'This class repeats every week. Apply the change to this date only '
        'or to all upcoming dates?',
        style: Theme.of(
          dialogContext,
        ).textTheme.bodyMedium?.copyWith(color: appText, height: 1.45),
      ),
    ),
  );
}
