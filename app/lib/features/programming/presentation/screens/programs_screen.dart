import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_form_dialog.dart';
import 'package:app/core/presentation/app_side_panel.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/calendar/presentation/widgets/schedule_week_view.dart'
    show mondayOf;
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:app/features/programming/presentation/screens/import_workouts_dialog.dart';
import 'package:app/features/programming/presentation/widgets/block_editor_panel.dart';
import 'package:app/features/programming/presentation/widgets/wod_day_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Programs page (docs/admin-ui-reference.md §3): a Mon–Sun board with one
/// column per day. BoxOS programs one WOD per gym per day, so a column holds
/// that WOD's sections as block cards. Blocks are created and edited one by
/// one in the block panel (§3.1), reorder by drag within a day and move to
/// other days with "Copy to day…". No tracks: one WOD per gym per day.
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
                  // Seven columns of at least 160px; narrower windows scroll
                  // the board sideways instead of squeezing the cards.
                  const minColumn = 160.0;
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

class _DayColumn extends ConsumerStatefulWidget {
  const _DayColumn({required this.date, required this.workouts});

  final DateTime date;
  final List<DailyWorkout> workouts;

  @override
  ConsumerState<_DayColumn> createState() => _DayColumnState();

  /// Saves [sections] as [day]'s WOD: updates it, or creates a draft "WOD"
  /// when the day has none yet (BoxOS has one WOD per gym per day). True
  /// when it was saved; waits for the refreshed list.
  static Future<bool> saveBlocks(
    BuildContext context,
    WidgetRef ref, {
    required DateTime day,
    required DailyWorkout? workout,
    required List<DailyWorkoutSection> sections,
  }) async {
    final repository = ref.read(programmingRepositoryProvider);
    try {
      if (workout == null) {
        await repository.createWorkout(
          scheduledDate: day,
          title: 'WOD',
          sections: sections,
          status: DailyWorkoutStatus.draft,
        );
      } else {
        await repository.updateWorkout(
          id: workout.id,
          scheduledDate: workout.scheduledDate,
          title: workout.title,
          sections: sections,
        );
      }
      ref.invalidate(programmingListProvider);
      await ref.read(programmingListProvider.future);
      return true;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessageFrom(error, fallback: 'Could not save the block'),
            ),
          ),
        );
      }
      return false;
    }
  }
}

class _DayColumnState extends ConsumerState<_DayColumn> {
  /// Shown while a save is in flight, so a drag lands at once and a second
  /// action never writes from stale data.
  List<DailyWorkoutSection>? _pending;

  DateTime get date => widget.date;

  DailyWorkout? _workoutOn(DateTime day) => widget.workouts
      .where((w) => _dateOnly(w.scheduledDate) == day)
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    final isToday = date == today;
    final isPast = date.isBefore(today);
    final workout = _workoutOn(date);
    final busy = _pending != null;
    final sections =
        _pending ?? workout?.sections ?? const <DailyWorkoutSection>[];
    const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final dayLabel = MaterialLocalizations.of(context).formatFullDate(date);

    Future<void> save(List<DailyWorkoutSection> next) async {
      if (busy) return;
      setState(() => _pending = next);
      await _DayColumn.saveBlocks(
        context,
        ref,
        day: date,
        workout: workout,
        sections: next,
      );
      if (mounted) setState(() => _pending = null);
    }

    Future<void> addBlock() async {
      final block = await showBlockEditorPanel(context, dayLabel: dayLabel);
      if (block != null) await save([...sections, block]);
    }

    Future<void> editBlock(int index) async {
      final block = await showBlockEditorPanel(
        context,
        existing: sections[index],
        dayLabel: dayLabel,
      );
      if (block != null) {
        await save([...sections]..[index] = block);
      }
    }

    Future<void> deleteBlock(int index) async {
      if (sections.length == 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'A WOD needs at least one block. Unpublish it instead.',
            ),
          ),
        );
        return;
      }
      final confirmed = await showAppConfirmDialog(
        context,
        title: 'Delete block?',
        message: 'Remove "${_blockTitle(sections[index])}" from this day.',
        confirmLabel: 'Delete',
        destructive: true,
      );
      if (confirmed) await save([...sections]..removeAt(index));
    }

    Future<void> copyBlock(int index) async {
      final target = await showDatePicker(
        context: context,
        initialDate: isPast ? today : date.add(const Duration(days: 1)),
        firstDate: today,
        lastDate: today.add(const Duration(days: 365)),
      );
      if (target == null || !context.mounted) return;
      final day = _dateOnly(target);
      final targetWorkout = _workoutOn(day);
      final saved = await _DayColumn.saveBlocks(
        context,
        ref,
        day: day,
        workout: targetWorkout,
        sections: [...?targetWorkout?.sections, sections[index]],
      );
      if (saved && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Copied to ${MaterialLocalizations.of(context).formatMediumDate(day)}.',
            ),
          ),
        );
      }
    }

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
              appSpaceSm,
              appSpaceXs,
              appSpaceXs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${weekdays[date.weekday - 1]} ${date.day}',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: appMono(
                      fontSize: 12,
                      color: isToday ? appPrimary : appMutedText,
                    ),
                  ),
                ),
                if (!isPast)
                  SizedBox.square(
                    dimension: 32,
                    child: IconButton(
                      tooltip: 'Add block',
                      padding: EdgeInsets.zero,
                      onPressed: addBlock,
                      icon: const Icon(
                        Icons.add_rounded,
                        size: 18,
                        color: appSubtleText,
                      ),
                    ),
                  ),
                if (workout != null)
                  SizedBox.square(
                    dimension: 32,
                    child: PopupMenuButton<String>(
                      tooltip: 'WOD actions',
                      color: appSurfaceElevated,
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color: appSubtleText,
                      ),
                      onSelected: (value) => switch (value) {
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
                        'details' => showWodDetailsDialog(
                          context,
                          date: date,
                          canManage: false,
                        ),
                        _ => duplicateWod(context, ref, workout),
                      },
                      itemBuilder: (_) => [
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
                          value: 'details',
                          child: Text('View as member'),
                        ),
                        const PopupMenuItem(
                          value: 'duplicate',
                          child: Text('Copy day to…'),
                        ),
                      ],
                    ),
                  ),
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
              child: Align(
                alignment: Alignment.centerLeft,
                child: AppPill(
                  label: workout.isPublished ? 'Published' : 'Draft',
                  intent: workout.isPublished
                      ? AppPillIntent.success
                      : AppPillIntent.warning,
                  dense: true,
                ),
              ),
            ),
          const Divider(height: 1, color: appBorder),
          Expanded(
            // Cards drag by their handle to reorder within the day.
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(appSpaceSm),
              buildDefaultDragHandles: false,
              itemCount: sections.length,
              onReorder: (from, to) {
                if (isPast) return;
                final next = [...sections];
                final block = next.removeAt(from);
                next.insert(to > from ? to - 1 : to, block);
                save(next);
              },
              footer: sections.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(appSpaceSm),
                      child: isPast
                          ? const Text(
                              'No WOD',
                              style: TextStyle(
                                color: appSubtleText,
                                fontSize: 12.5,
                              ),
                            )
                          : TextButton.icon(
                              onPressed: addBlock,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Add block'),
                            ),
                    )
                  : null,
              itemBuilder: (context, index) => Padding(
                key: ObjectKey(sections[index]),
                padding: const EdgeInsets.only(bottom: appSpaceSm),
                child: _BlockCard(
                  section: sections[index],
                  index: index,
                  readOnly: isPast,
                  onTap: isPast
                      ? () => showWodDetailsDialog(
                          context,
                          date: date,
                          canManage: false,
                        )
                      : () => editBlock(index),
                  onSelected: (action) => switch (action) {
                    'edit' => editBlock(index),
                    // A copy, not the same object: cards are keyed by identity.
                    'duplicate' => save(
                      [...sections]..insert(
                        index + 1,
                        DailyWorkoutSection.fromJson(sections[index].toJson()),
                      ),
                    ),
                    'copy' => copyBlock(index),
                    _ => deleteBlock(index),
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _blockTitle(DailyWorkoutSection section) => section.title.isNotEmpty
    ? section.title
    : section.kind == BlockKind.exercise
    ? section.exerciseName
    : 'Workout';

/// One block on the board (§3): title, then free text or a REPS | % set
/// table (first three sets, "+N more sets…"); footer with drag handle, kind
/// pill, notes marker and the ⋯ menu.
class _BlockCard extends StatelessWidget {
  const _BlockCard({
    required this.section,
    required this.index,
    required this.readOnly,
    required this.onTap,
    required this.onSelected,
  });

  final DailyWorkoutSection section;
  final int index;
  final bool readOnly;
  final VoidCallback onTap;
  final ValueChanged<String> onSelected;

  static String _value(WorkoutSet set) {
    final value = set.value;
    if (value == null) return '—';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final isExercise = section.kind == BlockKind.exercise;
    final shown = section.sets.take(3).toList();
    final notes = [
      if (section.coachNotes.isNotEmpty) 'Coach notes',
      if (section.memberNotes.isNotEmpty) 'Member notes',
    ];
    const muted = TextStyle(color: appMutedText, fontSize: 12.5, height: 1.4);
    return Material(
      color: appSurfaceAlt,
      borderRadius: BorderRadius.circular(appRadiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(appRadiusMd),
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            appSpaceMd,
            appSpaceMd,
            appSpaceXs,
            appSpaceXs,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(appRadiusMd),
            border: Border.all(color: appBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _blockTitle(section),
                style: const TextStyle(
                  color: appText,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: appSpaceXs),
              if (isExercise) ...[
                if (section.title.isNotEmpty &&
                    section.title != section.exerciseName)
                  Text(section.exerciseName, style: muted),
                Row(
                  children: [
                    Expanded(
                      child: Text('REPS', style: appMono(fontSize: 9.5)),
                    ),
                    Expanded(
                      child: Text(
                        section.setUnit == SetUnit.rpe ? 'RPE' : '%',
                        style: appMono(fontSize: 9.5),
                      ),
                    ),
                  ],
                ),
                for (final set in shown)
                  Row(
                    children: [
                      Expanded(child: Text('${set.reps}', style: muted)),
                      Expanded(child: Text(_value(set), style: muted)),
                    ],
                  ),
                if (section.sets.length > shown.length)
                  Text(
                    '+${section.sets.length - shown.length} more sets…',
                    style: const TextStyle(color: appSubtleText, fontSize: 12),
                  ),
              ] else
                Text(
                  section.description,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              const SizedBox(height: appSpaceXs),
              Row(
                children: [
                  if (!readOnly)
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.only(right: appSpaceXs),
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          size: 16,
                          color: appSubtleText,
                        ),
                      ),
                    ),
                  Flexible(
                    fit: FlexFit.tight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AppPill(
                        label: isExercise ? 'Exercise' : 'Workout',
                        intent: isExercise
                            ? AppPillIntent.primary
                            : AppPillIntent.neutral,
                        dense: true,
                      ),
                    ),
                  ),
                  if (notes.isNotEmpty)
                    Tooltip(
                      message: notes.join(' · '),
                      child: const Padding(
                        padding: EdgeInsets.only(left: appSpaceXs),
                        child: Icon(
                          Icons.sticky_note_2_outlined,
                          size: 15,
                          color: appSubtleText,
                        ),
                      ),
                    ),
                  if (!readOnly)
                    PopupMenuButton<String>(
                      tooltip: 'Block actions',
                      color: appSurfaceElevated,
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(28, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(
                        Icons.more_horiz_rounded,
                        color: appSubtleText,
                      ),
                      onSelected: onSelected,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(
                          value: 'duplicate',
                          child: Text('Duplicate'),
                        ),
                        PopupMenuItem(
                          value: 'copy',
                          child: Text('Copy to day…'),
                        ),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
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
