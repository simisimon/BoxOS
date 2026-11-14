import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_side_panel.dart';
import 'package:app/features/calendar/domain/models/schedule_booking.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:app/features/results/data/api_results_repository.dart';
import 'package:app/features/results/domain/workout_result.dart';
import 'package:app/features/results/presentation/block_leaderboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A block's whole leaderboard for coaches, with everyone's notes.
Future<void> showBlockResultsPanel(
  BuildContext context, {
  required int workoutId,
  required DailyWorkoutSection section,
  required String dayLabel,
}) {
  final title = section.title.isNotEmpty
      ? section.title
      : section.kind == BlockKind.exercise
      ? section.exerciseName
      : 'Workout';
  return showAppSidePanel<void>(
    context,
    builder: (_) => AppSidePanel(
      title: 'Results',
      subtitle: '$title · $dayLabel',
      child: _BlockResults(workoutId: workoutId, sectionId: section.id!),
    ),
  );
}

class _BlockResults extends ConsumerWidget {
  const _BlockResults({required this.workoutId, required this.sectionId});

  final int workoutId;
  final int sectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(leaderboardProvider(workoutId))
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Text(
            'Could not load the results.',
            style: TextStyle(color: appDanger),
          ),
          data: (sections) {
            final entries = sections[sectionId] ?? const [];
            if (entries.isEmpty) {
              return const Text(
                'No results yet.',
                style: TextStyle(color: appSubtleText),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in entries)
                  LeaderboardRow(entry: entry, workoutId: workoutId),
              ],
            );
          },
        );
  }
}

/// Class detail › Results: each booked member with their result on every
/// scored block of the day's WOD.
class ClassResults extends ConsumerWidget {
  const ClassResults({
    super.key,
    required this.workout,
    required this.bookings,
  });

  final DailyWorkout workout;
  final List<ScheduleBooking> bookings;

  static String _blockTitle(DailyWorkoutSection section) =>
      section.title.isNotEmpty
      ? section.title
      : section.kind == BlockKind.exercise
      ? section.exerciseName
      : 'Workout';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scored = [
      for (final section in workout.sections)
        if (section.isScored && section.id != null) section,
    ];
    if (bookings.isEmpty) {
      return const Text(
        'Nobody is booked into this class.',
        style: TextStyle(color: appSubtleText),
      );
    }
    return ref
        .watch(leaderboardProvider(workout.id))
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Text(
            'Could not load the results.',
            style: TextStyle(color: appDanger),
          ),
          data: (sections) {
            final byUser = <int, Map<int, LeaderboardEntry>>{};
            for (final MapEntry(key: sectionId, value: entries)
                in sections.entries) {
              for (final entry in entries) {
                (byUser[entry.userId] ??= {})[sectionId] = entry;
              }
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final booking in bookings)
                  _MemberResults(
                    name: booking.displayName.isEmpty
                        ? booking.nickname
                        : booking.displayName,
                    blocks: [
                      for (final section in scored)
                        (
                          _blockTitle(section),
                          byUser[booking.userId]?[section.id!],
                        ),
                    ],
                  ),
              ],
            );
          },
        );
  }
}

class _MemberResults extends StatelessWidget {
  const _MemberResults({required this.name, required this.blocks});

  final String name;
  final List<(String, LeaderboardEntry?)> blocks;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: appSpaceSm),
      padding: const EdgeInsets.all(appSpaceMd),
      decoration: BoxDecoration(
        color: appSurfaceAlt,
        borderRadius: BorderRadius.circular(appRadiusMd),
        border: Border.all(color: appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(color: appText, fontWeight: FontWeight.w600),
          ),
          for (final (title, entry) in blocks)
            Padding(
              padding: const EdgeInsets.only(top: appSpaceXs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: appMutedText,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  Text(
                    entry == null
                        ? 'No result'
                        : '${entry.scoreLabel} · '
                              '${entry.division == ResultDivision.rx ? 'Rx' : 'Scaled'}'
                              '${entry.isPr ? ' · PR' : ''}',
                    style: TextStyle(
                      color: entry == null ? appSubtleText : appText,
                      fontSize: 12.5,
                      fontWeight: entry == null
                          ? FontWeight.w400
                          : FontWeight.w600,
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
