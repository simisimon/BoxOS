import 'dart:async';

import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:app/features/results/data/api_results_repository.dart';
import 'package:app/features/results/domain/workout_result.dart';
import 'package:app/features/results/presentation/block_leaderboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _wire(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// `?date=2026-11-14` as a day; today when missing or invalid.
DateTime whiteboardDay(String? value) {
  final parsed = value == null ? null : DateTime.tryParse(value);
  return _dateOnly(parsed ?? DateTime.now());
}

/// The Whiteboard: the day's WOD with every scored block's leaderboard, for
/// every role. [tv] is the full-screen version for the box's TV: bigger type,
/// no navigation, refreshed every minute.
class WhiteboardScreen extends ConsumerStatefulWidget {
  const WhiteboardScreen({super.key, required this.day, this.tv = false});

  final DateTime day;
  final bool tv;

  @override
  ConsumerState<WhiteboardScreen> createState() => _WhiteboardScreenState();
}

class _WhiteboardScreenState extends ConsumerState<WhiteboardScreen> {
  late DateTime _day = _dateOnly(widget.day);
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    if (widget.tv) {
      _refresh = Timer.periodic(const Duration(minutes: 1), (_) {
        ref.invalidate(programmingListProvider);
        ref.invalidate(leaderboardProvider);
      });
    }
  }

  @override
  void didUpdateWidget(WhiteboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.day != widget.day) _day = _dateOnly(widget.day);
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  void _show(DateTime day) {
    setState(() => _day = day);
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go(
        '${widget.tv ? '/whiteboard/tv' : '/whiteboard'}'
        '?date=${_wire(day)}',
      );
    }
  }

  void _shift(int days) =>
      _show(DateTime(_day.year, _day.month, _day.day + days));

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final workouts = ref.watch(programmingListProvider);
    final workout = (workouts.value ?? const <DailyWorkout>[])
        .where((w) => _dateOnly(w.scheduledDate) == _day)
        .firstOrNull;
    final today = _dateOnly(DateTime.now());
    final header = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('WHITEBOARD', style: appMono(fontSize: 11)),
              const SizedBox(height: appSpaceXs),
              Text(
                localizations.formatFullDate(_day),
                style: const TextStyle(
                  color: appText,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: _day == today ? null : () => _show(today),
          child: const Text('Today'),
        ),
        IconButton(
          tooltip: 'Previous day',
          onPressed: () => _shift(-1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        IconButton(
          tooltip: 'Next day',
          onPressed: () => _shift(1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        if (widget.tv)
          IconButton(
            tooltip: 'Leave TV mode',
            onPressed: () => GoRouter.maybeOf(
              context,
            )?.go('/whiteboard?date=${_wire(_day)}'),
            icon: const Icon(Icons.close_fullscreen_rounded),
          )
        else
          IconButton(
            tooltip: 'TV mode',
            onPressed: () => GoRouter.maybeOf(
              context,
            )?.go('/whiteboard/tv?date=${_wire(_day)}'),
            icon: const Icon(Icons.tv_rounded),
          ),
      ],
    );

    final Widget body;
    if (workouts.isLoading && !workouts.hasValue) {
      body = const LinearProgressIndicator();
    } else if (workouts.hasError && !workouts.hasValue) {
      body = const Text(
        'Could not load the WOD.',
        style: TextStyle(color: appDanger),
      );
    } else if (workout == null || !workout.isPublished) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: appSpaceXl),
        child: Text(
          'No WOD on the whiteboard for this day.',
          style: TextStyle(color: appSubtleText, fontSize: 15),
        ),
      );
    } else {
      body = _Board(workout: workout);
    }

    final content = ListView(
      padding: EdgeInsets.all(widget.tv ? appSpace2xl : appSpaceLg),
      children: [
        header,
        const SizedBox(height: appSpaceLg),
        body,
      ],
    );
    if (!widget.tv) return content;
    return Scaffold(
      backgroundColor: appPageBackground,
      body: SafeArea(
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: content,
        ),
      ),
    );
  }
}

/// Blocks on the left, leaderboards on the right; stacked on narrow screens.
class _Board extends StatelessWidget {
  const _Board({required this.workout});

  final DailyWorkout workout;

  @override
  Widget build(BuildContext context) {
    final blocks = _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (workout.title.isNotEmpty) ...[
            Text(
              workout.title,
              style: const TextStyle(
                color: appText,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: appSpaceMd),
          ],
          for (final section in workout.sections) _Block(section: section),
        ],
      ),
    );
    final scored = [
      for (final section in workout.sections)
        if (section.isScored && section.id != null) section,
    ];
    final boards = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in scored) ...[
          _Card(
            child: _BlockBoard(workoutId: workout.id, section: section),
          ),
          const SizedBox(height: appSpaceMd),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 900
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: blocks),
                if (scored.isNotEmpty) ...[
                  const SizedBox(width: appSpaceLg),
                  Expanded(child: boards),
                ],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                blocks,
                if (scored.isNotEmpty) ...[
                  const SizedBox(height: appSpaceLg),
                  boards,
                ],
              ],
            ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(appSpaceLg),
    decoration: BoxDecoration(
      color: appSurface,
      borderRadius: BorderRadius.circular(appRadiusLg),
      border: Border.all(color: appBorder),
    ),
    child: child,
  );
}

String _title(DailyWorkoutSection section) => section.title.isNotEmpty
    ? section.title
    : section.kind == BlockKind.exercise
    ? section.exerciseName
    : 'Workout';

String _setLabel(WorkoutSet set, SetUnit unit) {
  final value = set.value;
  if (value == null) return '${set.reps} reps';
  final number = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
  return unit == SetUnit.rpe
      ? '${set.reps} reps @ RPE $number'
      : '${set.reps} reps @ $number %';
}

/// One block as members read it: no coach notes.
class _Block extends StatelessWidget {
  const _Block({required this.section});

  final DailyWorkoutSection section;

  @override
  Widget build(BuildContext context) {
    const text = TextStyle(color: appMutedText, fontSize: 14, height: 1.5);
    return Padding(
      padding: const EdgeInsets.only(bottom: appSpaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _title(section).toUpperCase(),
            style: appMono(fontSize: 12, color: appPrimary),
          ),
          const SizedBox(height: appSpaceXs),
          if (section.kind == BlockKind.exercise &&
              section.exerciseName.isNotEmpty &&
              section.exerciseName != section.title)
            Text(section.exerciseName, style: text.copyWith(color: appText)),
          if (section.description.trim().isNotEmpty)
            Text(section.description.trim(), style: text),
          for (var i = 0; i < section.sets.length; i++)
            Text(
              '${i + 1}.  ${_setLabel(section.sets[i], section.setUnit)}',
              style: text,
            ),
          if (section.memberNotes.trim().isNotEmpty)
            Text(
              section.memberNotes.trim(),
              style: text.copyWith(fontStyle: FontStyle.italic),
            ),
        ],
      ),
    );
  }
}

/// A scored block's leaderboard, always open: Rx first, then Scaled.
class _BlockBoard extends ConsumerWidget {
  const _BlockBoard({required this.workoutId, required this.section});

  final int workoutId;
  final DailyWorkoutSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(leaderboardProvider(workoutId));
    final entries = board.value?[section.id!] ?? const <LeaderboardEntry>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _title(section),
                style: const TextStyle(
                  color: appText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              entries.length == 1 ? '1 result' : '${entries.length} results',
              style: const TextStyle(color: appSubtleText, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: appSpaceSm),
        if (board.isLoading && !board.hasValue)
          const LinearProgressIndicator()
        else if (board.hasError && !board.hasValue)
          const Text(
            'Could not load the leaderboard.',
            style: TextStyle(color: appDanger, fontSize: 12),
          )
        else if (entries.isEmpty)
          const Text(
            'No results yet.',
            style: TextStyle(color: appSubtleText, fontSize: 13),
          )
        else
          for (final entry in entries)
            LeaderboardRow(entry: entry, workoutId: workoutId),
      ],
    );
  }
}
