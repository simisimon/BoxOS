import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/features/logbook/data/repositories/api_benchmark_repository.dart';
import 'package:app/features/logbook/data/repositories/api_personal_workout_repository.dart';
import 'package:app/features/logbook/domain/models/benchmark_workout.dart';
import 'package:app/features/logbook/domain/models/personal_workout.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:app/features/tracking/data/repositories/api_tracking_repository.dart';
import 'package:app/features/tracking/domain/models/trackable_workout.dart';
import 'package:app/features/tracking/presentation/screens/workout_timer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _crossfitColor = Color(0xFFE5533D);
const _benchmarkColor = Color(0xFFF5A524);
const _dailyColor = Color(0xFF3FC678);

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  late Future<_PickerData> _dataFuture;
  TrackableWorkout? _selected;
  Future<List<TrackingSession>>? _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _load();
  }

  Future<List<TrackingSession>> _loadSessions(TrackableWorkout workout) {
    return ref.read(trackingRepositoryProvider).fetchSessions(
          source: workout.source,
          sourceKey: workout.sourceKey,
          limit: 5,
        );
  }

  void _selectWorkout(TrackableWorkout workout) {
    setState(() {
      _selected = workout;
      _sessionsFuture = _loadSessions(workout);
    });
  }

  Future<_PickerData> _load() async {
    final personalRepo = ref.read(personalWorkoutRepositoryProvider);
    final benchmarkRepo = ref.read(benchmarkRepositoryProvider);
    final programmingRepo = ref.read(programmingRepositoryProvider);
    final hasActiveGym =
        ref.read(currentProfileProvider).value?.activeGym != null;

    final personalFuture = personalRepo.fetchWorkouts();
    final benchmarkFuture = benchmarkRepo.fetchBenchmarks();
    final dailyFuture = hasActiveGym
        ? programmingRepo.fetchWorkouts().catchError(
            (_) => <DailyWorkout>[],
          )
        : Future.value(<DailyWorkout>[]);

    final results = await Future.wait([
      personalFuture,
      benchmarkFuture,
      dailyFuture,
    ]);
    return _PickerData(
      personal: results[0] as List<PersonalWorkout>,
      benchmarks: results[1] as List<BenchmarkWorkout>,
      daily: results[2] as List<DailyWorkout>,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _dataFuture = _load();
    });
    await _dataFuture;
  }

  Future<void> _openPicker(_PickerData data) async {
    final result = await showModalBottomSheet<TrackableWorkout>(
      context: context,
      isScrollControlled: true,
      backgroundColor: appSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(appRadiusXl)),
      ),
      builder: (_) => _WorkoutPickerSheet(data: data),
    );
    if (result != null && mounted) {
      _selectWorkout(result);
    }
  }

  Future<void> _startTracking() async {
    final workout = _selected;
    if (workout == null) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WorkoutTimerScreen(workout: workout),
      ),
    );
    if (!mounted) return;
    // Refresh history when returning — a save might have happened.
    setState(() {
      _sessionsFuture = _loadSessions(workout);
    });
  }

  @override
  Widget build(BuildContext context) {
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
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_PickerData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _StateCard(
                    icon: Icons.error_outline,
                    title: 'Failed to load workouts',
                    message: errorMessageFrom(
                      snapshot.error!,
                      fallback: 'Failed to load workouts',
                    ),
                  ),
                ],
              );
            }
            final data = snapshot.data ?? const _PickerData.empty();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                const _Header(),
                const SizedBox(height: 20),
                _SelectorField(
                  selected: _selected,
                  onTap: () => _openPicker(data),
                ),
                if (_selected != null) ...[
                  const SizedBox(height: 16),
                  _WorkoutSummary(workout: _selected!),
                  const SizedBox(height: 16),
                  _HistorySection(
                    future: _sessionsFuture,
                    scoreType: _selected!.suggestedScoreType,
                  ),
                ],
                const SizedBox(height: 24),
                _StartButton(
                  enabled: _selected != null,
                  onTap: _startTracking,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PickerData {
  const _PickerData({
    required this.personal,
    required this.benchmarks,
    required this.daily,
  });

  const _PickerData.empty()
      : personal = const [],
        benchmarks = const [],
        daily = const [];

  final List<PersonalWorkout> personal;
  final List<BenchmarkWorkout> benchmarks;
  final List<DailyWorkout> daily;

  List<DailyWorkout> get todays {
    final now = DateTime.now();
    return daily.where((workout) {
      final d = workout.scheduledDate;
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).toList();
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Track a workout',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: appText,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Pick a workout and time it with Stopwatch, AMRAP, or EMOM.',
          style: TextStyle(color: appSubtleText, height: 1.4),
        ),
      ],
    );
  }
}

class _SelectorField extends StatelessWidget {
  const _SelectorField({required this.selected, required this.onTap});

  final TrackableWorkout? selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasSelection = selected != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(appRadiusLg),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            color: appSurface,
            borderRadius: BorderRadius.circular(appRadiusLg),
            border: Border.all(
              color: hasSelection ? appPrimaryHairline : appBorder,
            ),
          ),
          child: Row(
            children: [
              if (hasSelection) ...[
                AppAccentBadge(
                  icon: _iconFor(selected!.source),
                  color: selected!.accent,
                  size: 36,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasSelection ? 'Workout' : 'Select workout',
                      style: const TextStyle(
                        color: appSubtleText,
                        fontSize: 11,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasSelection ? selected!.title : 'Tap to choose…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasSelection ? appText : appMutedText,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.expand_more_rounded, color: appSubtleText),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkoutSummary extends StatelessWidget {
  const _WorkoutSummary({required this.workout});

  final TrackableWorkout workout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(appRadiusLg),
        border: Border.all(color: appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (workout.subtitle.isNotEmpty)
            Text(
              workout.subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: appSubtleText,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (workout.movements.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (var i = 0; i < workout.movements.length; i++) ...[
              _MovementLine(movement: workout.movements[i]),
              if (i != workout.movements.length - 1)
                const SizedBox(height: 6),
            ],
          ],
        ],
      ),
    );
  }
}

class _MovementLine extends StatelessWidget {
  const _MovementLine({required this.movement});

  final TrackableMovement movement;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 5,
          height: 5,
          margin: const EdgeInsets.only(top: 8, right: 10),
          decoration: const BoxDecoration(
            color: appSubtleText,
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                movement.name,
                style: const TextStyle(
                  color: appText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (movement.detail != null && movement.detail!.isNotEmpty)
                Text(
                  movement.detail!,
                  style: const TextStyle(
                    color: appSubtleText,
                    height: 1.35,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.future, required this.scoreType});

  final Future<List<TrackingSession>>? future;
  final TrackingScoreType scoreType;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TrackingSession>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _HistoryCard(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snapshot.hasError) {
          return const _HistoryCard(
            child: Text(
              'Couldn’t load previous attempts.',
              style: TextStyle(color: appSubtleText),
            ),
          );
        }
        final sessions = snapshot.data ?? const <TrackingSession>[];
        if (sessions.isEmpty) {
          return const _HistoryCard(
            child: Text(
              'No previous attempts yet. Your first one shows up here.',
              style: TextStyle(color: appSubtleText, height: 1.4),
            ),
          );
        }
        final lowerIsBetter = sessions.first.scoreType == TrackingScoreType.time;
        final best = sessions.reduce(
          (acc, s) => lowerIsBetter
              ? (s.scoreValue < acc.scoreValue ? s : acc)
              : (s.scoreValue > acc.scoreValue ? s : acc),
        );
        return _HistoryCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'PREVIOUS ATTEMPTS',
                    style: TextStyle(
                      color: appSubtleText,
                      fontSize: 11,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  _BestBadge(label: 'Best ${best.scoreLabel}'),
                ],
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < sessions.length; i++) ...[
                _SessionRow(
                  session: sessions[i],
                  isBest: sessions[i].id == best.id,
                ),
                if (i != sessions.length - 1)
                  const Divider(color: appBorder, height: 14),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(appRadiusLg),
        border: Border.all(color: appBorder),
      ),
      child: child,
    );
  }
}

class _BestBadge extends StatelessWidget {
  const _BestBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: appPrimarySoft,
        borderRadius: BorderRadius.circular(appRadiusPill),
        border: Border.all(color: appPrimaryHairline),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: appPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.isBest});

  final TrackingSession session;
  final bool isBest;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    session.scoreLabel,
                    style: const TextStyle(
                      color: appText,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isBest)
                    const Icon(
                      Icons.emoji_events_outlined,
                      size: 14,
                      color: appPrimary,
                    ),
                ],
              ),
              if (session.notesText.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  session.notesText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: appSubtleText,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        Text(
          _relativeDate(session.createdAt),
          style: const TextStyle(
            color: appSubtleText,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  static String _relativeDate(DateTime when) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final whenDay = DateTime(when.year, when.month, when.day);
    final diff = today.difference(whenDay).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '${diff}d ago';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[when.month - 1]} ${when.day}';
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(appRadiusLg),
        onTap: enabled ? onTap : null,
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: enabled ? appPrimary : appSurfaceAlt,
            borderRadius: BorderRadius.circular(appRadiusLg),
            border: Border.all(color: enabled ? appPrimary : appBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.play_arrow_rounded,
                color: enabled ? Colors.white : appSubtleText,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Start tracking',
                style: TextStyle(
                  color: enabled ? Colors.white : appSubtleText,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkoutPickerSheet extends StatelessWidget {
  const _WorkoutPickerSheet({required this.data});

  final _PickerData data;

  @override
  Widget build(BuildContext context) {
    final todays = data.todays;
    final hasAny = todays.isNotEmpty ||
        data.benchmarks.isNotEmpty ||
        data.personal.isNotEmpty;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: appBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Select workout',
                style: TextStyle(
                  color: appText,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Expanded(
            child: hasAny
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      if (todays.isNotEmpty) ...[
                        const _GroupHeader(label: 'Today'),
                        for (final workout in todays)
                          _PickerTile(
                            workout: _trackableFromDaily(workout),
                          ),
                      ],
                      if (data.benchmarks.isNotEmpty) ...[
                        const _GroupHeader(label: 'Benchmark WODs'),
                        for (final workout in data.benchmarks)
                          _PickerTile(
                            workout: _trackableFromBenchmark(workout),
                          ),
                      ],
                      if (data.personal.isNotEmpty) ...[
                        const _GroupHeader(label: 'My workouts'),
                        for (final workout in data.personal)
                          _PickerTile(
                            workout: _trackableFromPersonal(workout),
                          ),
                      ],
                    ],
                  )
                : const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No workouts available. Create one in the Logbook or wait for today’s WOD.',
                      style: TextStyle(color: appSubtleText),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: appSubtleText,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({required this.workout});

  final TrackableWorkout workout;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: appSurfaceAlt,
        borderRadius: BorderRadius.circular(appRadiusMd),
        border: Border.all(color: appBorder),
      ),
      child: ListTile(
        leading: AppAccentBadge(
          icon: _iconFor(workout.source),
          color: workout.accent,
          size: 42,
        ),
        title: Text(
          workout.title,
          style: const TextStyle(
            color: appText,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: workout.subtitle.isEmpty
            ? null
            : Text(
                workout.subtitle,
                style: const TextStyle(color: appSubtleText),
              ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: appSubtleText,
        ),
        onTap: () => Navigator.of(context).pop(workout),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(appRadiusLg),
        border: Border.all(color: appBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAccentBadge(icon: icon, color: appPrimary),
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

IconData _iconFor(TrackableSource source) {
  switch (source) {
    case TrackableSource.personal:
      return Icons.fitness_center_outlined;
    case TrackableSource.benchmark:
      return Icons.local_fire_department_outlined;
    case TrackableSource.daily:
      return Icons.event_outlined;
  }
}

TrackableWorkout _trackableFromPersonal(PersonalWorkout workout) {
  if (workout.type == WorkoutType.crossfit) {
    final movements = workout.movements
        .map(
          (item) => TrackableMovement(
            name: item['name']?.toString() ?? '',
            detail: _detailFromCrossfitMovement(item),
          ),
        )
        .where((m) => m.name.isNotEmpty)
        .toList();
    return TrackableWorkout(
      source: TrackableSource.personal,
      sourceKey: workout.id.toString(),
      title: workout.title,
      subtitle: _crossfitSubtitle(workout.format, movements.length),
      movements: movements,
      suggestedMode: timerModeFromFormat(workout.format),
      suggestedMinutes: workout.structure['time_cap_minutes'] as int?,
      accent: _crossfitColor,
    );
  }
  final exercises = workout.exercises
      .map(
        (item) => TrackableMovement(
          name: item['name']?.toString() ?? '',
          detail: _detailFromFitnessExercise(item),
        ),
      )
      .where((m) => m.name.isNotEmpty)
      .toList();
  return TrackableWorkout(
    source: TrackableSource.personal,
    sourceKey: workout.id.toString(),
    title: workout.title,
    subtitle: '${exercises.length} exercise${exercises.length == 1 ? '' : 's'}',
    movements: exercises,
    suggestedMode: TimerMode.stopwatch,
    accent: appPrimary,
  );
}

TrackableWorkout _trackableFromBenchmark(BenchmarkWorkout workout) {
  final format = workout.structure['format'] as String?;
  final movements = workout.movements
      .map(
        (item) => TrackableMovement(
          name: item['name']?.toString() ?? '',
          detail: _detailFromCrossfitMovement(item),
        ),
      )
      .where((m) => m.name.isNotEmpty)
      .toList();
  return TrackableWorkout(
    source: TrackableSource.benchmark,
    sourceKey: workout.id,
    title: workout.name,
    subtitle: _crossfitSubtitle(format, movements.length),
    movements: movements,
    suggestedMode: timerModeFromFormat(format),
    suggestedMinutes: workout.structure['time_cap_minutes'] as int?,
    accent: _benchmarkColor,
  );
}

TrackableWorkout _trackableFromDaily(DailyWorkout workout) {
  final movements = workout.sections
      .map(
        (section) => TrackableMovement(
          name: section.title,
          detail: section.description,
        ),
      )
      .where((m) => m.name.isNotEmpty)
      .toList();
  return TrackableWorkout(
    source: TrackableSource.daily,
    sourceKey: workout.id.toString(),
    title: workout.title,
    subtitle:
        'Today · ${workout.sections.length} section${workout.sections.length == 1 ? '' : 's'}',
    movements: movements,
    suggestedMode: TimerMode.stopwatch,
    accent: _dailyColor,
  );
}

String _crossfitSubtitle(String? format, int movementCount) {
  final label = _formatLabel(format);
  final mvmt = '$movementCount movement${movementCount == 1 ? '' : 's'}';
  if (label == null) return mvmt;
  return '$label · $mvmt';
}

String? _formatLabel(String? format) => switch (format) {
      'for_time' => 'For Time',
      'amrap' => 'AMRAP',
      'emom' => 'EMOM',
      'rounds' => 'Rounds',
      _ => null,
    };

String? _detailFromCrossfitMovement(Map<String, dynamic> item) {
  final reps = item['reps']?.toString().trim();
  final weight = item['weight']?.toString().trim();
  final parts = [
    if (reps != null && reps.isNotEmpty) reps,
    if (weight != null && weight.isNotEmpty) weight,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

String? _detailFromFitnessExercise(Map<String, dynamic> item) {
  final sets = item['sets']?.toString().trim();
  final reps = item['reps']?.toString().trim();
  final weight = item['weight']?.toString().trim();
  final parts = <String>[
    if (sets != null && sets.isNotEmpty && sets != 'null') '$sets sets',
    if (reps != null && reps.isNotEmpty && reps != 'null') '$reps reps',
    if (weight != null && weight.isNotEmpty) weight,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}
