import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/class_type.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:app/features/calendar/presentation/widgets/class_type_badge.dart';
import 'package:app/features/programming/presentation/widgets/wod_day_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _mondayOf(DateTime day) =>
    _dateOnly(day).subtract(Duration(days: day.weekday - 1));

/// Programming view for managers: one week at a time, Monday to Sunday, with
/// the day's WOD (create / edit / publish) and the WOD classes it will run in.
class WodWeekView extends ConsumerStatefulWidget {
  const WodWeekView({super.key});

  @override
  ConsumerState<WodWeekView> createState() => _WodWeekViewState();
}

class _WodWeekViewState extends ConsumerState<WodWeekView> {
  late DateTime _weekStart = _mondayOf(DateTime.now());

  void _shiftWeek(int weeks) {
    setState(() => _weekStart = _weekStart.add(Duration(days: 7 * weeks)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final weekEnd = _weekStart.add(const Duration(days: 6));
    final isCurrentWeek = _weekStart == _mondayOf(DateTime.now());
    final sessions = ref.watch(scheduleListProvider).value ?? const [];

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
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'WODs for the week',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: appSubtleText,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isCurrentWeek) ...[
                TextButton(
                  onPressed: () =>
                      setState(() => _weekStart = _mondayOf(DateTime.now())),
                  child: const Text('This week'),
                ),
                const SizedBox(width: 4),
              ],
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
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: 7,
              separatorBuilder: (_, _) => const SizedBox(height: 18),
              itemBuilder: (context, index) {
                final day = _weekStart.add(Duration(days: index));
                return _WeekDayRow(
                  day: day,
                  wodClasses: [
                    for (final session in sessions)
                      if (session.type.showsWod &&
                          _dateOnly(session.startTime) == day)
                        session,
                  ]..sort((a, b) => a.startTime.compareTo(b.startTime)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekDayRow extends StatelessWidget {
  const _WeekDayRow({required this.day, required this.wodClasses});

  final DateTime day;
  final List<ScheduleClass> wodClasses;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final isToday = day == _dateOnly(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                localizations.formatFullDate(day),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: isToday ? appPrimary : appText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (isToday) ...[
              const SizedBox(width: 8),
              Text('TODAY', style: appMono(fontSize: 9.5, color: appPrimary)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        // Which classes this WOD will run in — or a nudge when none are
        // scheduled, so a WOD is not programmed for a day nobody can book.
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (wodClasses.isEmpty)
              Text(
                'No WOD classes scheduled',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: appSubtleText,
                ),
              )
            else
              for (final session in wodClasses)
                _ClassChip(
                  label:
                      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(session.startTime))}'
                      ' ${session.title}',
                ),
          ],
        ),
        const SizedBox(height: 8),
        WodDaySection(date: day, canManage: true),
      ],
    );
  }
}

class _ClassChip extends StatelessWidget {
  const _ClassChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = classTypeColor(ClassType.wod);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: appMono(fontSize: 10.5, letterSpacing: 0, color: appText),
      ),
    );
  }
}
