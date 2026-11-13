import 'dart:async';
import 'dart:math' as math;

import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:app/features/calendar/presentation/widgets/class_type_badge.dart';
import 'package:app/features/calendar/presentation/widgets/schedule_week_view.dart'
    show mondayOf;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double _hourHeight = 56;
const double _gutterWidth = 52;
const double _minDayWidth = 120;

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _addDays(DateTime day, int days) =>
    DateTime(day.year, day.month, day.day + days);

/// Owners' and trainers' class calendar (docs/admin-ui-reference.md §2): a
/// Mon–Sun grid with hour rows, today's date in an accent circle, a red line
/// at the current time, and each class as a block sized by its duration,
/// parallel classes side by side. Past classes are faded. Trainers can
/// narrow it to the classes they coach. Athletes keep [ScheduleWeekView].
class ScheduleHourGrid extends ConsumerStatefulWidget {
  const ScheduleHourGrid({
    super.key,
    required this.weekStart,
    required this.onWeekChanged,
    required this.onOpenClass,
    this.selectedClassId,
    this.onAddClass,
    this.onCreateSchedule,
    this.coachUserId,
  });

  final DateTime weekStart;
  final ValueChanged<DateTime> onWeekChanged;
  final ValueChanged<ScheduleClass> onOpenClass;
  final int? selectedClassId;

  /// "+" on a day header: a one-off class that day. Null hides it.
  final ValueChanged<DateTime>? onAddClass;

  /// The header's accent +: create recurring classes.
  final VoidCallback? onCreateSchedule;

  /// A trainer's user id: shows a "Coached by me" filter for their classes.
  final int? coachUserId;

  @override
  ConsumerState<ScheduleHourGrid> createState() => _ScheduleHourGridState();
}

class _ScheduleHourGridState extends ConsumerState<ScheduleHourGrid> {
  ScrollController? _vertical;
  bool _onlyMine = false;

  /// Moves the current-time line and fades classes that just ended.
  late final Timer _clock = Timer.periodic(
    const Duration(minutes: 1),
    (_) => setState(() {}),
  );

  @override
  void initState() {
    super.initState();
    _clock;
  }

  @override
  void dispose() {
    _clock.cancel();
    _vertical?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final sessions = ref.watch(scheduleListProvider).value ?? const [];
    final days = [for (var i = 0; i < 7; i++) _addDays(widget.weekStart, i)];
    final weekEnd = days.last;
    final inWeek = [
      for (final s in sessions)
        if (!_dateOnly(s.startTime).isBefore(widget.weekStart) &&
            !_dateOnly(s.startTime).isAfter(weekEnd) &&
            (!_onlyMine || s.assignedTrainer?.id == widget.coachUserId))
          s,
    ];
    // 05:00–21:00 by default, widened to fit the week's classes.
    var firstHour = 5;
    var lastHour = 21;
    for (final s in inWeek) {
      firstHour = math.min(firstHour, s.startTime.hour);
      // Counted from the class's own midnight; a class running past 24:00
      // is cut at the end of its day.
      final endMinute =
          s.startTime.hour * 60 + s.startTime.minute + s.durationMinutes;
      lastHour = math.max(lastHour, (endMinute / 60).ceil());
    }
    lastHour = math.min(lastHour, 24);
    // Open on the hour before now (or the first hour), once.
    _vertical ??= ScrollController(
      initialScrollOffset:
          math.max(0, DateTime.now().hour - 1 - firstHour) * _hourHeight,
    );
    final isCurrentWeek = widget.weekStart == mondayOf(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(appSpaceLg),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(appRadiusLg),
        border: Border.all(color: appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${localizations.formatShortMonthDay(widget.weekStart)} – '
                  '${localizations.formatShortMonthDay(weekEnd)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: appText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: isCurrentWeek
                    ? null
                    : () => widget.onWeekChanged(mondayOf(DateTime.now())),
                child: const Text('Today'),
              ),
              IconButton(
                onPressed: () =>
                    widget.onWeekChanged(_addDays(widget.weekStart, -7)),
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Previous week',
              ),
              IconButton(
                onPressed: () =>
                    widget.onWeekChanged(_addDays(widget.weekStart, 7)),
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: 'Next week',
              ),
              if (widget.onCreateSchedule != null) ...[
                const SizedBox(width: appSpaceSm),
                IconButton.filled(
                  onPressed: widget.onCreateSchedule,
                  style: IconButton.styleFrom(
                    backgroundColor: appPrimary,
                    foregroundColor: appInverseText,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(appRadiusSm),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Create recurring classes',
                ),
              ],
            ],
          ),
          // Below the week header, which has no room left on phones.
          if (widget.coachUserId != null) ...[
            const SizedBox(height: appSpaceSm),
            Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: const Text('Coached by me'),
                selected: _onlyMine,
                onSelected: (value) => setState(() => _onlyMine = value),
              ),
            ),
          ],
          const SizedBox(height: appSpaceMd),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final dayWidth = math.max(
                  _minDayWidth,
                  (constraints.maxWidth - _gutterWidth) / 7,
                );
                final width = _gutterWidth + dayWidth * 7;
                // Narrow windows scroll the whole grid sideways.
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const SizedBox(width: _gutterWidth),
                            for (final day in days)
                              SizedBox(
                                width: dayWidth,
                                child: _DayHeader(
                                  day: day,
                                  onAdd:
                                      widget.onAddClass == null ||
                                          day.isBefore(
                                            _dateOnly(DateTime.now()),
                                          )
                                      ? null
                                      : () => widget.onAddClass!(day),
                                ),
                              ),
                          ],
                        ),
                        const Divider(height: 1, color: appBorder),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _vertical,
                            child: SizedBox(
                              height: (lastHour - firstHour) * _hourHeight,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _HourGutter(
                                    firstHour: firstHour,
                                    lastHour: lastHour,
                                  ),
                                  for (final day in days)
                                    SizedBox(
                                      width: dayWidth,
                                      child: _DayColumn(
                                        day: day,
                                        classes: [
                                          for (final s in inWeek)
                                            if (_dateOnly(s.startTime) == day)
                                              s,
                                        ],
                                        firstHour: firstHour,
                                        lastHour: lastHour,
                                        selectedClassId: widget.selectedClassId,
                                        onOpenClass: widget.onOpenClass,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.onAdd});

  final DateTime day;
  final VoidCallback? onAdd;

  static const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  @override
  Widget build(BuildContext context) {
    final isToday = day == _dateOnly(DateTime.now());
    return SizedBox(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _weekdays[day.weekday - 1],
            style: appMono(fontSize: 11, color: appSubtleText),
          ),
          const SizedBox(width: appSpaceXs),
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isToday ? appPrimary : Colors.transparent,
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                color: isToday ? appInverseText : appText,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          if (onAdd != null)
            IconButton(
              onPressed: onAdd,
              tooltip: 'Add class',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              icon: const Icon(Icons.add_rounded, color: appSubtleText),
            ),
        ],
      ),
    );
  }
}

class _HourGutter extends StatelessWidget {
  const _HourGutter({required this.firstHour, required this.lastHour});

  final int firstHour;
  final int lastHour;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _gutterWidth,
      child: Stack(
        children: [
          for (var h = firstHour; h < lastHour; h++)
            Positioned(
              top: (h - firstHour) * _hourHeight + 2,
              left: 0,
              right: appSpaceSm,
              child: Text(
                '${h.toString().padLeft(2, '0')}:00',
                textAlign: TextAlign.right,
                style: appMono(fontSize: 10, color: appSubtleText),
              ),
            ),
        ],
      ),
    );
  }
}

/// One day: hour lines, the classes as positioned blocks, and on today the
/// current-time line.
class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.classes,
    required this.firstHour,
    required this.lastHour,
    required this.selectedClassId,
    required this.onOpenClass,
  });

  final DateTime day;
  final List<ScheduleClass> classes;
  final int firstHour;
  final int lastHour;
  final int? selectedClassId;
  final ValueChanged<ScheduleClass> onOpenClass;

  double _offset(DateTime t) =>
      ((t.hour - firstHour) + t.minute / 60) * _hourHeight;

  @override
  Widget build(BuildContext context) {
    final lanes = laneLayout(classes);
    final now = DateTime.now();
    final isToday = day == _dateOnly(now);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Container(
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: appBorder)),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (var h = firstHour; h < lastHour; h++)
                Positioned(
                  top: (h - firstHour) * _hourHeight,
                  left: 0,
                  right: 0,
                  child: const Divider(height: 1, color: appBorder),
                ),
              for (final placed in lanes)
                Positioned(
                  top: _offset(placed.session.startTime),
                  height: math.max(
                    22,
                    placed.session.durationMinutes / 60 * _hourHeight - 2,
                  ),
                  left: width / placed.laneCount * placed.lane + 2,
                  width: width / placed.laneCount - 4,
                  child: _ClassBlock(
                    session: placed.session,
                    selected: placed.session.id == selectedClassId,
                    onTap: () => onOpenClass(placed.session),
                  ),
                ),
              if (isToday && now.hour >= firstHour && now.hour < lastHour)
                Positioned(
                  top: _offset(now),
                  left: 0,
                  right: 0,
                  child: Container(height: 2, color: appDanger),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A class placed in a day: [lane] of [laneCount] side-by-side lanes.
class PlacedClass {
  const PlacedClass(this.session, this.lane, this.laneCount);

  final ScheduleClass session;
  final int lane;
  final int laneCount;
}

/// Splits a day's classes into side-by-side lanes so overlapping classes
/// never cover each other. Classes that overlap (directly or through a chain)
/// share one group and its lane count; a class alone keeps the full width.
List<PlacedClass> laneLayout(List<ScheduleClass> classes) {
  final sorted = [...classes]
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  DateTime end(ScheduleClass s) =>
      s.startTime.add(Duration(minutes: s.durationMinutes));
  final placed = <PlacedClass>[];
  var group = <(ScheduleClass, int)>[];
  var laneEnds = <DateTime>[];
  DateTime? groupEnd;

  void flush() {
    for (final (session, lane) in group) {
      placed.add(PlacedClass(session, lane, laneEnds.length));
    }
    group = [];
    laneEnds = [];
    groupEnd = null;
  }

  for (final s in sorted) {
    if (groupEnd != null && !s.startTime.isBefore(groupEnd!)) flush();
    var lane = laneEnds.indexWhere((e) => !s.startTime.isBefore(e));
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(end(s));
    } else {
      laneEnds[lane] = end(s);
    }
    group.add((s, lane));
    groupEnd = groupEnd == null || end(s).isAfter(groupEnd!)
        ? end(s)
        : groupEnd;
  }
  flush();
  return placed;
}

class _ClassBlock extends StatelessWidget {
  const _ClassBlock({
    required this.session,
    required this.selected,
    required this.onTap,
  });

  final ScheduleClass session;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = classTypeColor(session.type);
    final end = session.startTime.add(
      Duration(minutes: session.durationMinutes),
    );
    String hm(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Opacity(
      opacity: end.isBefore(DateTime.now()) ? 0.5 : 1,
      child: Material(
        color: Color.alphaBlend(color.withValues(alpha: 0.14), appSurfaceAlt),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(appRadiusSm),
          side: BorderSide(
            color: selected ? appPrimary : color.withValues(alpha: 0.5),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 3, 4, 2),
            // Short classes cut their lower lines instead of overflowing.
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxHeight: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hm(session.startTime),
                      maxLines: 1,
                      style: appMono(fontSize: 9.5, color: appMutedText),
                    ),
                    Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: appText,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${session.bookedCount}/${session.capacity}',
                      maxLines: 1,
                      style: appMono(
                        fontSize: 9.5,
                        color: session.isFull ? appDanger : appSubtleText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
