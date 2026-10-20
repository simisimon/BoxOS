import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:app/features/calendar/presentation/widgets/class_type_badge.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:app/features/programming/presentation/widgets/wod_day_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime mondayOf(DateTime day) => _addDays(day, 1 - day.weekday);

/// Calendar-day arithmetic. Adding a `Duration` of whole days steps in 24h,
/// which lands on the wrong day across a DST switch (Oct 25 showed twice).
DateTime _addDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Wide enough for seven side-by-side day slips.
const _columnsBreakpoint = 860.0;

/// Where a day stands in programming. Drives the slip's colour and label.
enum _DayStatus {
  published('Published', appPrimary),
  draft('Draft', appMutedText),
  missing('No WOD yet', appWarning),
  rest('No WOD classes', appSubtleText);

  const _DayStatus(this.label, this.color);

  final String label;
  final Color color;
}

class _WeekDay {
  const _WeekDay({
    required this.date,
    required this.workout,
    required this.classes,
  });

  final DateTime date;
  final DailyWorkout? workout;

  /// Every class of the day, by start time.
  final List<ScheduleClass> classes;

  bool get isPast => date.isBefore(_dateOnly(DateTime.now()));
  bool get isToday => date == _dateOnly(DateTime.now());
  bool get hasWodClasses => classes.any((session) => session.type.showsWod);

  _DayStatus get status {
    final workout = this.workout;
    if (workout != null) {
      return workout.isPublished ? _DayStatus.published : _DayStatus.draft;
    }
    return hasWodClasses ? _DayStatus.missing : _DayStatus.rest;
  }
}

/// The schedule, one week at a time: per day the WOD on top and every class
/// below. Managers add classes and WODs right in the day; everyone opens a
/// class to book it or see who is coming.
class ScheduleWeekView extends ConsumerWidget {
  const ScheduleWeekView({
    super.key,
    required this.weekStart,
    required this.onWeekChanged,
    required this.canManage,
    required this.selectedClassId,
    required this.onOpenClass,
    this.onAddClass,
    this.onImport,
  });

  /// Monday of the week shown.
  final DateTime weekStart;
  final ValueChanged<DateTime> onWeekChanged;
  final bool canManage;

  /// Highlighted while its side panel is open.
  final int? selectedClassId;
  final ValueChanged<ScheduleClass> onOpenClass;

  /// Null hides "Add class" (athletes).
  final ValueChanged<DateTime>? onAddClass;

  /// Opens the CSV WOD import. Null hides the button (athletes).
  final VoidCallback? onImport;

  Future<void> _openWod(
    BuildContext context,
    WidgetRef ref,
    _WeekDay day,
  ) async {
    if (day.workout != null) {
      await showWodDetailsDialog(context, date: day.date, canManage: canManage);
    } else if (canManage && !day.isPast) {
      await showWodEditorDialog(context, ref, date: day.date);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final sessions = ref.watch(scheduleListProvider).value ?? const [];
    final workoutsAsync = ref.watch(programmingListProvider);
    // Athletes only ever see published WODs.
    final workouts = [
      for (final workout in workoutsAsync.value ?? const <DailyWorkout>[])
        if (canManage || workout.isPublished) workout,
    ];

    final days = [for (var i = 0; i < 7; i++) _buildDay(i, workouts, sessions)];
    final weekEnd = _addDays(weekStart, 6);
    final isCurrentWeek = weekStart == mondayOf(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${localizations.formatShortMonthDay(weekStart)} – '
                      '${localizations.formatShortMonthDay(weekEnd)}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (canManage) ...[
                      const SizedBox(height: 2),
                      Text(
                        _summary(days),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: appMutedText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!isCurrentWeek)
                TextButton(
                  onPressed: () => onWeekChanged(mondayOf(DateTime.now())),
                  child: const Text('This week'),
                ),
              if (onImport != null)
                IconButton(
                  onPressed: onImport,
                  icon: const Icon(Icons.upload_file_rounded),
                  tooltip: 'Import WODs',
                ),
              IconButton(
                onPressed: () => onWeekChanged(_addDays(weekStart, -7)),
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Previous week',
              ),
              IconButton(
                onPressed: () => onWeekChanged(_addDays(weekStart, 7)),
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: 'Next week',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: workoutsAsync.isLoading && !workoutsAsync.hasValue
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      Widget slip(_WeekDay day, _SlipLayout layout) => _DaySlip(
                        day: day,
                        layout: layout,
                        canManage: canManage,
                        selectedClassId: selectedClassId,
                        onOpenWod: () => _openWod(context, ref, day),
                        onOpenClass: onOpenClass,
                        onAddClass: onAddClass == null || day.isPast
                            ? null
                            : () => onAddClass!(day.date),
                      );
                      if (constraints.maxWidth >= _columnsBreakpoint) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < days.length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              Expanded(
                                child: slip(days[i], _SlipLayout.column),
                              ),
                            ],
                          ],
                        );
                      }
                      return ListView.separated(
                        itemCount: days.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            slip(days[index], _SlipLayout.row),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  _WeekDay _buildDay(
    int offset,
    List<DailyWorkout> workouts,
    List<ScheduleClass> sessions,
  ) {
    final date = _addDays(weekStart, offset);
    return _WeekDay(
      date: date,
      workout: workouts
          .where((workout) => _dateOnly(workout.scheduledDate) == date)
          .firstOrNull,
      classes: [
        for (final session in sessions)
          if (_dateOnly(session.startTime) == date) session,
      ]..sort((a, b) => a.startTime.compareTo(b.startTime)),
    );
  }

  /// One plain sentence on what is left to do this week.
  static String _summary(List<_WeekDay> days) {
    final wodDays = days.where((day) => day.hasWodClasses).toList();
    if (wodDays.isEmpty) {
      return 'No WOD classes this week.';
    }
    final programmed = wodDays.where((day) => day.workout != null).length;
    final drafts = days.where((day) => day.status == _DayStatus.draft).length;
    final draftNote = drafts == 0
        ? ''
        : ', $drafts still ${drafts == 1 ? 'a draft' : 'drafts'}';
    if (programmed == wodDays.length) {
      return 'All ${wodDays.length} WOD days programmed$draftNote.';
    }
    return '$programmed of ${wodDays.length} WOD days programmed$draftNote.';
  }
}

enum _SlipLayout { column, row }

/// One day of the week: the WOD on top (tap to open or add it), then the
/// day's classes and, for managers, "Add class". Columns on wide screens,
/// stacked rows on phones.
class _DaySlip extends StatelessWidget {
  const _DaySlip({
    required this.day,
    required this.layout,
    required this.canManage,
    required this.selectedClassId,
    required this.onOpenWod,
    required this.onOpenClass,
    required this.onAddClass,
  });

  final _WeekDay day;
  final _SlipLayout layout;
  final bool canManage;
  final int? selectedClassId;
  final VoidCallback onOpenWod;
  final ValueChanged<ScheduleClass> onOpenClass;
  final VoidCallback? onAddClass;

  bool get _wodTappable => day.workout != null || (canManage && !day.isPast);

  @override
  Widget build(BuildContext context) {
    final status = day.status;
    // Status rail: solid for published or missing, faint for drafts.
    final railColor = switch (status) {
      _DayStatus.draft => appPrimary.withValues(alpha: 0.35),
      _DayStatus.rest => Colors.transparent,
      _ => status.color,
    };
    final isColumn = layout == _SlipLayout.column;

    final wod = InkWell(
      onTap: _wodTappable ? onOpenWod : null,
      child: Opacity(
        opacity: day.isPast && day.workout == null ? 0.55 : 1,
        child: isColumn
            ? _ColumnContent(day: day, status: status, canManage: canManage)
            : _RowContent(day: day, status: status, canManage: canManage),
      ),
    );
    final classes = Padding(
      // Phone rows line the classes up under the WOD, past the date column.
      padding: EdgeInsets.fromLTRB(isColumn ? 8 : 68, 0, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final session in day.classes) ...[
            _ClassTile(
              session: session,
              selected: session.id == selectedClassId,
              onTap: () => onOpenClass(session),
            ),
            const SizedBox(height: 4),
          ],
          if (onAddClass != null)
            TextButton.icon(
              onPressed: onAddClass,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add class'),
            ),
        ],
      ),
    );

    return Material(
      color: appSurfaceAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: day.isToday ? appPrimaryHairline : appBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 3, color: railColor),
          if (isColumn)
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [wod, classes],
                ),
              ),
            )
          else ...[
            wod,
            classes,
          ],
        ],
      ),
    );
  }
}

/// One class in a day slip: type colour, time, title and fill.
class _ClassTile extends StatelessWidget {
  const _ClassTile({
    required this.session,
    required this.selected,
    required this.onTap,
  });

  final ScheduleClass session;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(session.startTime));
    final fillColor = session.isFull ? appDanger : appSubtleText;

    return Material(
      color: selected ? appPrimary.withValues(alpha: 0.12) : appSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: selected ? appPrimary : appBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 30,
                color: classTypeColor(session.type),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      time,
                      style: appMono(
                        fontSize: 10,
                        color: appText,
                        letterSpacing: 0,
                      ),
                    ),
                    Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (session.isBooked || session.isWaitlisted)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    session.isBooked
                        ? Icons.check_circle_rounded
                        : Icons.hourglass_top_rounded,
                    size: 14,
                    color: session.isBooked ? appSuccess : appWarning,
                  ),
                ),
              const SizedBox(width: 4),
              Text(
                '${session.bookedCount}/${session.capacity}',
                style: appMono(
                  fontSize: 10,
                  color: fillColor,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayHeading extends StatelessWidget {
  const _DayHeading({required this.day, this.stacked = false});

  final _WeekDay day;

  /// Weekday above the date, for the narrow date column of phone rows.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = [
      Text(
        _weekdayShort[day.date.weekday - 1],
        style: theme.textTheme.labelLarge?.copyWith(
          color: day.isToday ? appPrimary : appMutedText,
          fontWeight: FontWeight.w700,
        ),
      ),
      SizedBox(width: stacked ? 0 : 6, height: stacked ? 2 : 0),
      Text(
        '${day.date.day}',
        style: theme.textTheme.headlineSmall?.copyWith(
          color: day.isToday ? appPrimary : appText,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    ];
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: children,
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status, required this.isPast});

  final _DayStatus status;
  final bool isPast;

  @override
  Widget build(BuildContext context) {
    final label = isPast && status == _DayStatus.missing
        ? 'No WOD'
        : status.label;
    final isDraft = status == _DayStatus.draft;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Hollow dot for drafts, filled once published.
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDraft ? null : status.color,
            border: isDraft
                ? Border.all(color: status.color, width: 1.4)
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: status.color),
          ),
        ),
      ],
    );
  }
}

/// Section names as a coach would say them: the title, or the first line of
/// the description when the section has no title.
String _sectionName(DailyWorkoutSection section) {
  if (section.title.trim().isNotEmpty) {
    return section.title.trim();
  }
  return section.description.trim().split('\n').first;
}

/// The first line of the description, unless it is already the section's
/// name (sections without a title).
String? _sectionDetail(DailyWorkoutSection section) {
  if (section.title.trim().isEmpty) {
    return null;
  }
  final line = section.description.trim().split('\n').first.trim();
  return line.isEmpty ? null : line;
}

class _AddWodHint extends StatelessWidget {
  const _AddWodHint();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.add_rounded, size: 16, color: appPrimary),
        const SizedBox(width: 4),
        Text(
          'Add WOD',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: appPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ColumnContent extends StatelessWidget {
  const _ColumnContent({
    required this.day,
    required this.status,
    required this.canManage,
  });

  final _WeekDay day;
  final _DayStatus status;
  final bool canManage;

  /// Kept short so the day's classes stay in view below the WOD.
  static const _maxSections = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workout = day.workout;
    final sections = workout?.sections ?? const <DailyWorkoutSection>[];

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DayHeading(day: day),
          const SizedBox(height: 6),
          _StatusLabel(status: status, isPast: day.isPast),
          const SizedBox(height: 10),
          if (workout != null) ...[
            Text(
              workout.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: appText,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 8),
            for (final section in sections.take(_maxSections))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _sectionName(section),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_sectionDetail(section) case final detail?)
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: appSubtleText,
                          height: 1.3,
                        ),
                      ),
                  ],
                ),
              ),
            if (sections.length > _maxSections)
              Text(
                '${sections.length - _maxSections} more',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: appSubtleText,
                ),
              ),
          ] else if (canManage && !day.isPast)
            const _AddWodHint(),
        ],
      ),
    );
  }
}

class _RowContent extends StatelessWidget {
  const _RowContent({
    required this.day,
    required this.status,
    required this.canManage,
  });

  final _WeekDay day;
  final _DayStatus status;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workout = day.workout;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 48, child: _DayHeading(day: day, stacked: true)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusLabel(status: status, isPast: day.isPast),
                const SizedBox(height: 4),
                if (workout != null) ...[
                  Text(
                    workout.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: appText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (workout.sections.isNotEmpty)
                    Text(
                      workout.sections.map(_sectionName).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: appMutedText,
                      ),
                    ),
                ] else if (canManage && !day.isPast)
                  const _AddWodHint(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
