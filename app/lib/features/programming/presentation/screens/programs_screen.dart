import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_side_panel.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/calendar/presentation/widgets/schedule_week_view.dart'
    show mondayOf;
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:app/features/programming/presentation/screens/import_workouts_dialog.dart';
import 'package:app/features/programming/presentation/widgets/wod_day_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Programs page (docs/admin-ui-reference.md §3): a Mon–Sun board with one
/// column per day. BoxOS programs one WOD per gym per day, so a column holds
/// that WOD's sections as block cards; the WOD opens in the editor panel.
/// No tracks (one WOD per day) and no drag & drop: "Copy to day…" duplicates.
class ProgramsScreen extends ConsumerStatefulWidget {
  const ProgramsScreen({super.key});

  @override
  ConsumerState<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends ConsumerState<ProgramsScreen> {
  DateTime _weekStart = mondayOf(DateTime.now());

  void _shiftWeek(int weeks) => setState(
    () => _weekStart = DateTime(
      _weekStart.year,
      _weekStart.month,
      _weekStart.day + 7 * weeks,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final workoutsAsync = ref.watch(programmingListProvider);
    final localizations = MaterialLocalizations.of(context);
    final weekEnd = DateTime(
      _weekStart.year,
      _weekStart.month,
      _weekStart.day + 6,
    );
    final isCurrentWeek = _weekStart == mondayOf(DateTime.now());

    return Padding(
      padding: const EdgeInsets.all(appSpaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${localizations.formatShortMonthDay(_weekStart)} – '
                  '${localizations.formatShortMonthDay(weekEnd)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: appText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => showAppSidePanel<bool>(
                  context,
                  builder: (_) => const ImportWorkoutsDialog(),
                ),
                icon: const Icon(Icons.upload_file_rounded),
                tooltip: 'Import WODs',
              ),
              IconButton(
                onPressed: () => _shiftWeek(-1),
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Previous week',
              ),
              TextButton(
                onPressed: isCurrentWeek
                    ? null
                    : () =>
                          setState(() => _weekStart = mondayOf(DateTime.now())),
                child: const Text('Today'),
              ),
              IconButton(
                onPressed: () => _shiftWeek(1),
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: 'Next week',
              ),
            ],
          ),
          const SizedBox(height: appSpaceMd),
          Expanded(
            child: workoutsAsync.when(
              loading: () => const AppLoadingState(),
              error: (error, _) => AppEmptyState.error(
                title: 'Could not load programming',
                subtitle: errorMessageFrom(error, fallback: 'Try again'),
                actionLabel: 'Retry',
                onAction: () => ref.invalidate(programmingListProvider),
              ),
              data: (workouts) => LayoutBuilder(
                builder: (context, constraints) {
                  // Seven columns of at least 150px; narrower windows scroll
                  // the board sideways instead of squeezing the cards.
                  const minColumn = 150.0;
                  final columnWidth =
                      (constraints.maxWidth - 6 * appSpaceSm) / 7;
                  final width = columnWidth < minColumn
                      ? minColumn
                      : columnWidth;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < 7; i++) ...[
                          if (i > 0) const SizedBox(width: appSpaceSm),
                          SizedBox(
                            width: width,
                            height: constraints.maxHeight,
                            child: _DayColumn(
                              date: DateTime(
                                _weekStart.year,
                                _weekStart.month,
                                _weekStart.day + i,
                              ),
                              workouts: workouts,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

class _DayColumn extends ConsumerWidget {
  const _DayColumn({required this.date, required this.workouts});

  final DateTime date;
  final List<DailyWorkout> workouts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = _dateOnly(DateTime.now());
    final isToday = date == today;
    final isPast = date.isBefore(today);
    final workout = workouts
        .where((w) => _dateOnly(w.scheduledDate) == date)
        .firstOrNull;
    const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

    void edit() =>
        showWodEditorDialog(context, ref, date: date, existing: workout);

    return Container(
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(appRadiusLg),
        border: Border.all(color: isToday ? appPrimaryHairline : appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              appSpaceMd,
              appSpaceMd,
              appSpaceXs,
              appSpaceSm,
            ),
            child: Row(
              children: [
                Text(
                  '${weekdays[date.weekday - 1]} ${date.day}',
                  style: appMono(
                    fontSize: 12,
                    color: isToday ? appPrimary : appMutedText,
                  ),
                ),
                const Spacer(),
                if (workout != null)
                  PopupMenuButton<String>(
                    tooltip: 'WOD actions',
                    color: appSurfaceElevated,
                    iconSize: 18,
                    icon: const Icon(
                      Icons.more_horiz_rounded,
                      color: appSubtleText,
                    ),
                    onSelected: (value) => switch (value) {
                      'edit' => edit(),
                      'publish' => publishWod(
                        context,
                        ref,
                        workout,
                        publish: true,
                      ),
                      'unpublish' => publishWod(
                        context,
                        ref,
                        workout,
                        publish: false,
                      ),
                      _ => duplicateWod(context, ref, workout),
                    },
                    itemBuilder: (_) => [
                      if (!isPast)
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      if (workout.isPublished)
                        const PopupMenuItem(
                          value: 'unpublish',
                          child: Text('Unpublish'),
                        )
                      else
                        const PopupMenuItem(
                          value: 'publish',
                          child: Text('Publish'),
                        ),
                      const PopupMenuItem(
                        value: 'duplicate',
                        child: Text('Copy to day…'),
                      ),
                    ],
                  )
                else
                  const SizedBox(height: 40),
              ],
            ),
          ),
          if (workout != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                appSpaceMd,
                0,
                appSpaceMd,
                appSpaceSm,
              ),
              child: Wrap(
                spacing: appSpaceSm,
                runSpacing: appSpaceXs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    workout.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: appText,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  AppPill(
                    label: workout.isPublished ? 'Published' : 'Draft',
                    intent: workout.isPublished
                        ? AppPillIntent.success
                        : AppPillIntent.warning,
                    dense: true,
                  ),
                ],
              ),
            ),
          const Divider(height: 1, color: appBorder),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(appSpaceSm),
              children: [
                for (final section in workout?.sections ?? const [])
                  Padding(
                    padding: const EdgeInsets.only(bottom: appSpaceSm),
                    child: _BlockCard(
                      section: section,
                      // Past days are read-only: show the full WOD.
                      onTap: isPast
                          ? () => showWodDetailsDialog(
                              context,
                              date: date,
                              canManage: false,
                            )
                          : edit,
                    ),
                  ),
                if (!isPast)
                  TextButton.icon(
                    onPressed: edit,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(workout == null ? 'Add WOD' : 'Edit WOD'),
                  )
                else if (workout == null)
                  const Padding(
                    padding: EdgeInsets.all(appSpaceSm),
                    child: Text(
                      'No WOD',
                      style: TextStyle(color: appSubtleText, fontSize: 12.5),
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

/// One WOD section as a board card: title, free text, score unit.
class _BlockCard extends StatelessWidget {
  const _BlockCard({required this.section, required this.onTap});

  final DailyWorkoutSection section;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final score = switch (section.scoreType) {
      WorkoutSectionScore.time => 'Time',
      WorkoutSectionScore.roundsReps => 'Rounds + Reps',
      WorkoutSectionScore.weight => 'Weight',
    };
    return Material(
      color: appSurfaceAlt,
      borderRadius: BorderRadius.circular(appRadiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(appRadiusMd),
        child: Container(
          padding: const EdgeInsets.all(appSpaceMd),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(appRadiusMd),
            border: Border.all(color: appBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (section.title.isNotEmpty) ...[
                Text(
                  section.title,
                  style: const TextStyle(
                    color: appText,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: appSpaceXs),
              ],
              Text(
                section.description,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: appMutedText,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: appSpaceSm),
              AppPill(label: score, dense: true),
            ],
          ),
        ),
      ),
    );
  }
}
