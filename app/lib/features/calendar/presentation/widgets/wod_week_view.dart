import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:app/features/programming/presentation/widgets/wod_day_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _mondayOf(DateTime day) => _addDays(day, 1 - day.weekday);

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
    required this.wodClasses,
  });

  final DateTime date;
  final DailyWorkout? workout;
  final List<ScheduleClass> wodClasses;

  bool get isPast => date.isBefore(_dateOnly(DateTime.now()));
  bool get isToday => date == _dateOnly(DateTime.now());

  _DayStatus get status {
    final workout = this.workout;
    if (workout != null) {
      return workout.isPublished ? _DayStatus.published : _DayStatus.draft;
    }
    return wodClasses.isEmpty ? _DayStatus.rest : _DayStatus.missing;
  }
}

/// Programming view for managers: the whole week at a glance, one slip per
/// day showing whether its WOD is published, drafted or still missing.
/// Tapping a slip opens the full WOD (or the editor for an empty day).
class WodWeekView extends ConsumerStatefulWidget {
  const WodWeekView({super.key});

  @override
  ConsumerState<WodWeekView> createState() => _WodWeekViewState();
}

class _WodWeekViewState extends ConsumerState<WodWeekView> {
  late DateTime _weekStart = _mondayOf(DateTime.now());

  void _shiftWeek(int weeks) {
    setState(() => _weekStart = _addDays(_weekStart, 7 * weeks));
  }

  Future<void> _openDay(_WeekDay day) async {
    if (day.workout != null) {
      await showWodDetailsDialog(context, date: day.date, canManage: true);
    } else if (!day.isPast) {
      await showWodEditorDialog(context, ref, date: day.date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final sessions = ref.watch(scheduleListProvider).value ?? const [];
    final workoutsAsync = ref.watch(programmingListProvider);
    final workouts = workoutsAsync.value ?? const <DailyWorkout>[];

    final days = [for (var i = 0; i < 7; i++) _buildDay(i, workouts, sessions)];
    final weekEnd = _addDays(_weekStart, 6);
    final isCurrentWeek = _weekStart == _mondayOf(DateTime.now());

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
                      '${localizations.formatShortMonthDay(_weekStart)} – '
                      '${localizations.formatShortMonthDay(weekEnd)}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _summary(days),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: appMutedText,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isCurrentWeek)
                TextButton(
                  onPressed: () =>
                      setState(() => _weekStart = _mondayOf(DateTime.now())),
                  child: const Text('This week'),
                ),
              IconButton(
                onPressed: () => _shiftWeek(-1),
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Previous week',
              ),
              IconButton(
                onPressed: () => _shiftWeek(1),
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
                      if (constraints.maxWidth >= _columnsBreakpoint) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < days.length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              Expanded(
                                child: _DaySlip(
                                  day: days[i],
                                  layout: _SlipLayout.column,
                                  onTap: () => _openDay(days[i]),
                                ),
                              ),
                            ],
                          ],
                        );
                      }
                      return ListView.separated(
                        itemCount: days.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _DaySlip(
                          day: days[index],
                          layout: _SlipLayout.row,
                          onTap: () => _openDay(days[index]),
                        ),
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
    final date = _addDays(_weekStart, offset);
    return _WeekDay(
      date: date,
      workout: workouts
          .where((workout) => _dateOnly(workout.scheduledDate) == date)
          .firstOrNull,
      wodClasses: [
        for (final session in sessions)
          if (session.type.showsWod && _dateOnly(session.startTime) == date)
            session,
      ]..sort((a, b) => a.startTime.compareTo(b.startTime)),
    );
  }

  /// One plain sentence on what is left to do this week.
  static String _summary(List<_WeekDay> days) {
    final wodDays = days.where((day) => day.wodClasses.isNotEmpty).toList();
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

/// One day of the week: status, WOD title and sections, and the WOD class
/// times. Columns on wide screens, compact rows on phones.
class _DaySlip extends StatelessWidget {
  const _DaySlip({
    required this.day,
    required this.layout,
    required this.onTap,
  });

  final _WeekDay day;
  final _SlipLayout layout;
  final VoidCallback onTap;

  bool get _isTappable => day.workout != null || !day.isPast;

  @override
  Widget build(BuildContext context) {
    final status = day.status;
    final content = layout == _SlipLayout.column
        ? _ColumnContent(day: day, status: status)
        : _RowContent(day: day, status: status);
    // Status rail: solid for published or missing, faint for drafts.
    final railColor = switch (status) {
      _DayStatus.draft => appPrimary.withValues(alpha: 0.35),
      _DayStatus.rest => Colors.transparent,
      _ => status.color,
    };

    return Opacity(
      opacity: day.isPast && day.workout == null ? 0.55 : 1,
      child: Material(
        color: appSurfaceAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: day.isToday ? appPrimaryHairline : appBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _isTappable ? onTap : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(height: 3, color: railColor),
              if (layout == _SlipLayout.column)
                Expanded(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: content,
                  ),
                )
              else
                content,
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

String _classTimes(BuildContext context, List<ScheduleClass> classes) {
  final localizations = MaterialLocalizations.of(context);
  return classes
      .map(
        (session) => localizations.formatTimeOfDay(
          TimeOfDay.fromDateTime(session.startTime),
        ),
      )
      .join('  ');
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
  const _ColumnContent({required this.day, required this.status});

  final _WeekDay day;
  final _DayStatus status;

  static const _maxSections = 4;

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
          if (day.wodClasses.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _classTimes(context, day.wodClasses),
              style: appMono(fontSize: 10, letterSpacing: 0),
            ),
          ],
          const SizedBox(height: 14),
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
                padding: const EdgeInsets.only(bottom: 10),
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
          ] else if (!day.isPast)
            const _AddWodHint(),
        ],
      ),
    );
  }
}

class _RowContent extends StatelessWidget {
  const _RowContent({required this.day, required this.status});

  final _WeekDay day;
  final _DayStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workout = day.workout;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
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
                ] else if (!day.isPast)
                  const _AddWodHint(),
                if (day.wodClasses.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    _classTimes(context, day.wodClasses),
                    style: appMono(fontSize: 10, letterSpacing: 0),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
