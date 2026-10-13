import 'dart:async';

import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/features/logbook/data/repositories/api_benchmark_repository.dart';
import 'package:app/features/logbook/data/repositories/api_exercise_repository.dart';
import 'package:app/features/logbook/data/repositories/api_logbook_repository.dart';
import 'package:app/features/logbook/data/repositories/api_personal_workout_repository.dart';
import 'package:app/features/logbook/domain/models/benchmark_workout.dart';
import 'package:app/features/logbook/domain/models/exercise.dart';
import 'package:app/features/logbook/domain/models/personal_workout.dart';
import 'package:app/features/logbook/domain/models/workout_log_entry.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class LogbookScreen extends ConsumerStatefulWidget {
  const LogbookScreen({super.key});

  @override
  ConsumerState<LogbookScreen> createState() => _LogbookScreenState();
}

class _LogbookScreenState extends ConsumerState<LogbookScreen> {
  late Future<List<WorkoutLogEntry>> _entriesFuture;
  late Future<List<PersonalWorkout>> _workoutsFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = _loadEntries();
    _workoutsFuture = _loadWorkouts();
  }

  Future<List<WorkoutLogEntry>> _loadEntries() {
    return ref.read(logbookRepositoryProvider).fetchEntries();
  }

  Future<List<PersonalWorkout>> _loadWorkouts() {
    return ref.read(personalWorkoutRepositoryProvider).fetchWorkouts();
  }

  Future<void> _refresh() async {
    setState(() {
      _entriesFuture = _loadEntries();
      _workoutsFuture = _loadWorkouts();
    });
  }

  Future<void> _refreshWorkouts() async {
    setState(() {
      _workoutsFuture = _loadWorkouts();
    });
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createWorkout(WorkoutType type) async {
    final draft = await showDialog<_WorkoutDraft>(
      context: context,
      builder: (context) => type == WorkoutType.crossfit
          ? const _CrossfitBuilderDialog()
          : const _FitnessBuilderDialog(),
    );
    if (draft == null) {
      return;
    }
    try {
      await ref
          .read(personalWorkoutRepositoryProvider)
          .createWorkout(
            title: draft.title,
            type: type,
            structure: draft.structure,
          );
      if (!mounted) {
        return;
      }
      await _refreshWorkouts();
      _showSnack('${type.label} workout created.');
    } catch (error) {
      _showSnack(errorMessageFrom(error, fallback: 'Failed to create workout'));
    }
  }

  Future<void> _deleteWorkout(PersonalWorkout workout) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: appSurface,
        title: const Text('Delete workout', style: TextStyle(color: appText)),
        content: Text(
          'Delete "${workout.title}"? This can’t be undone.',
          style: const TextStyle(color: appMutedText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: appDanger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref
          .read(personalWorkoutRepositoryProvider)
          .deleteWorkout(id: workout.id);
      if (!mounted) {
        return;
      }
      await _refreshWorkouts();
    } catch (error) {
      _showSnack(errorMessageFrom(error, fallback: 'Failed to delete workout'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final hasActiveGym = profile?.activeGym != null;

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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // Tracking lost its own tab: it answers the same question as the
            // logbook, so this is its entry point until the two views are
            // merged properly.
            const _TrackWorkoutCard(),
            const SizedBox(height: 20),
            _CreateWorkoutActions(onCreate: _createWorkout),
            const SizedBox(height: 20),
            const _SectionTitle(title: 'My workouts'),
            const SizedBox(height: 12),
            _buildMyWorkouts(),
            const SizedBox(height: 20),
            const _SectionTitle(title: 'Recent training'),
            const SizedBox(height: 12),
            if (hasActiveGym)
              _buildHistory()
            else
              const _StateCard(
                icon: Icons.history_outlined,
                title: 'Join a gym for history',
                message:
                    'Your workout history appears once a gym is active. You can still create personal workouts above.',
                accentColor: appPrimary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistory() {
    return FutureBuilder<List<WorkoutLogEntry>>(
      future: _entriesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return _StateCard(
            icon: Icons.error_outline,
            title: 'Failed to load logbook',
            message: errorMessageFrom(
              snapshot.error!,
              fallback: 'Failed to load logbook',
            ),
            accentColor: appPrimary,
          );
        }
        final entries = snapshot.data ?? const <WorkoutLogEntry>[];
        if (entries.isEmpty) {
          return const _StateCard(
            icon: Icons.menu_book_outlined,
            title: 'No workout logs yet',
            message:
                'Log a result from Programming to start building your personal training history.',
            accentColor: appPrimary,
          );
        }
        return Column(
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              _HistoryCard(entry: entries[i]),
              if (i != entries.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  Widget _buildMyWorkouts() {
    return FutureBuilder<List<PersonalWorkout>>(
      future: _workoutsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return _StateCard(
            icon: Icons.error_outline,
            title: 'Failed to load workouts',
            message: errorMessageFrom(
              snapshot.error!,
              fallback: 'Failed to load workouts',
            ),
            accentColor: appPrimary,
          );
        }
        final workouts = snapshot.data ?? const <PersonalWorkout>[];
        if (workouts.isEmpty) {
          return const _StateCard(
            icon: Icons.fitness_center_outlined,
            title: 'No workouts yet',
            message:
                'Tap “Create workout” to build your first Fitness or CrossFit workout.',
            accentColor: appPrimary,
          );
        }
        return Column(
          children: [
            for (var i = 0; i < workouts.length; i++) ...[
              _PersonalWorkoutCard(
                workout: workouts[i],
                onDelete: () => _deleteWorkout(workouts[i]),
              ),
              if (i != workouts.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: appText,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _HistoryCard extends ConsumerStatefulWidget {
  const _HistoryCard({required this.entry});

  final WorkoutLogEntry entry;

  @override
  ConsumerState<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends ConsumerState<_HistoryCard> {
  late WorkoutLogEntry _entry;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
  }

  @override
  void didUpdateWidget(covariant _HistoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh from the parent's snapshot only if the id changed (a different
    // entry took this slot); otherwise our local optimistic state is the
    // source of truth.
    if (oldWidget.entry.id != widget.entry.id) {
      _entry = widget.entry;
    }
  }

  Future<void> _toggleReaction(String reaction) async {
    if (_busy) return;
    final repository = ref.read(logbookRepositoryProvider);
    final isClearing = _entry.myReaction == reaction;
    setState(() => _busy = true);
    try {
      final summary = isClearing
          ? await repository.clearReaction(entryId: _entry.id)
          : await repository.setReaction(
              entryId: _entry.id,
              reaction: reaction,
            );
      if (!mounted) return;
      setState(() {
        _entry = _entry.copyWithReactions(
          reactionCount: summary.reactionCount,
          reactions: summary.reactions,
          myReaction: summary.myReaction,
        );
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Couldn’t update reaction'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = _entry;
    final dateLabel = MaterialLocalizations.of(
      context,
    ).formatFullDate(entry.scheduledDate);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: appBorder),
        boxShadow: [
          BoxShadow(
            color: appPrimary.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAccentBadge(
                icon: entry.isPr
                    ? Icons.emoji_events_outlined
                    : Icons.fitness_center_outlined,
                color: entry.isPr ? appPrimary : appPrimary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.workoutTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _HeroPill(label: entry.scoreLabel, color: appPrimary),
                        if (entry.isPr)
                          const _HeroPill(label: 'PR', color: appPrimary)
                        else if (entry.prRank != null)
                          _HeroPill(
                            label: 'Rank #${entry.prRank}',
                            color: appPrimary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dateLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: appSubtleText,
                      ),
                    ),
                    if (entry.classTitle != null &&
                        entry.classTitle!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Class: ${entry.classTitle!}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: appMutedText,
                        ),
                      ),
                    ],
                    if (entry.notesText.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: appSurfaceAlt,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: appBorder),
                        ),
                        child: Text(
                          entry.notesText,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: appText,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ReactionRow(
            entry: entry,
            busy: _busy,
            onToggle: _toggleReaction,
          ),
        ],
      ),
    );
  }
}

/// Three-button reaction strip. Each button highlights when it's the viewer's
/// active reaction. Tapping the active button clears it; tapping a different
/// one swaps in place (the backend upsert handles the swap server-side).
class _ReactionRow extends StatelessWidget {
  const _ReactionRow({
    required this.entry,
    required this.busy,
    required this.onToggle,
  });

  final WorkoutLogEntry entry;
  final bool busy;
  final Future<void> Function(String reaction) onToggle;

  static const _kinds = <(String, IconData)>[
    ('fire', Icons.local_fire_department_rounded),
    ('clap', Icons.front_hand_rounded),
    ('strong', Icons.fitness_center_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final kind in _kinds) ...[
          _ReactionChip(
            label: '${entry.reactions[kind.$1] ?? 0}',
            icon: kind.$2,
            active: entry.myReaction == kind.$1,
            disabled: busy,
            onTap: () => onToggle(kind.$1),
          ),
          const SizedBox(width: 8),
        ],
        const Spacer(),
        if (entry.reactionCount > 0)
          Text(
            '${entry.reactionCount}',
            style: const TextStyle(
              color: appSubtleText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.disabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? appPrimary : appSubtleText;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(appRadiusPill),
        onTap: disabled ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? appPrimarySoft : appSurfaceAlt,
            borderRadius: BorderRadius.circular(appRadiusPill),
            border: Border.all(
              color: active ? appPrimaryHairline : appBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
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

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: appText,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

const _crossfitColor = Color(0xFFE5533D);

String? _crossfitFormatLabel(String? format) => switch (format) {
  'for_time' => 'For Time',
  'amrap' => 'AMRAP',
  'emom' => 'EMOM',
  'rounds' => 'Rounds',
  _ => null,
};

class _WorkoutDraft {
  const _WorkoutDraft({required this.title, required this.structure});

  final String title;
  final Map<String, dynamic> structure;
}

/// Entry point into the tracking flow (workout picker → timer), which used to
/// be a bottom-nav tab of its own.
class _TrackWorkoutCard extends StatelessWidget {
  const _TrackWorkoutCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(appRadiusLg),
        onTap: () => context.go('/tracking'),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: appSurface,
            borderRadius: BorderRadius.circular(appRadiusLg),
            border: Border.all(color: appPrimaryHairline),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: appPrimarySoft,
                  borderRadius: BorderRadius.circular(appRadiusMd),
                ),
                child: const Icon(
                  Icons.timer_outlined,
                  color: appPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Track a workout',
                      style: TextStyle(
                        color: appText,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Pick today’s WOD, a benchmark, or your own — then start the timer.',
                      style: TextStyle(
                        color: appSubtleText,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.arrow_forward_rounded,
                color: appPrimary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateWorkoutActions extends StatelessWidget {
  const _CreateWorkoutActions({required this.onCreate});

  final ValueChanged<WorkoutType> onCreate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Create workout'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _TypeActionCard(
                icon: Icons.fitness_center_outlined,
                title: 'Fitness',
                subtitle: 'Strength · sets, reps, weight',
                color: appPrimary,
                onTap: () => onCreate(WorkoutType.fitness),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TypeActionCard(
                icon: Icons.local_fire_department_outlined,
                title: 'CrossFit',
                subtitle: 'WOD · format, time cap, movements',
                color: _crossfitColor,
                onTap: () => onCreate(WorkoutType.crossfit),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TypeActionCard extends StatelessWidget {
  const _TypeActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(appRadiusLg),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: appSurface,
            borderRadius: BorderRadius.circular(appRadiusLg),
            border: Border.all(color: appBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(appRadiusMd),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  color: appText,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: appSubtleText,
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final WorkoutType type;

  @override
  Widget build(BuildContext context) {
    final color = type == WorkoutType.crossfit ? _crossfitColor : appPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(appRadiusPill),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        type.label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _PersonalWorkoutCard extends StatelessWidget {
  const _PersonalWorkoutCard({required this.workout, required this.onDelete});

  final PersonalWorkout workout;
  final VoidCallback onDelete;

  String _summary() {
    if (workout.type == WorkoutType.crossfit) {
      final count = workout.movements.length;
      final format = _crossfitFormatLabel(workout.format);
      return [
        ?format,
        '$count movement${count == 1 ? '' : 's'}',
      ].join(' · ');
    }
    final count = workout.exercises.length;
    return '$count exercise${count == 1 ? '' : 's'}';
  }

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
      child: Row(
        children: [
          AppAccentBadge(
            icon: workout.type == WorkoutType.crossfit
                ? Icons.local_fire_department_outlined
                : Icons.fitness_center_outlined,
            color: workout.type == WorkoutType.crossfit
                ? _crossfitColor
                : appPrimary,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        workout.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: appText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _TypeBadge(type: workout.type),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _summary(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: appSubtleText,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, color: appSubtleText),
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }
}

class _MovementControllers {
  final name = TextEditingController();
  final reps = TextEditingController();
  final weight = TextEditingController();

  void dispose() {
    name.dispose();
    reps.dispose();
    weight.dispose();
  }
}

class _ExerciseControllers {
  final name = TextEditingController();
  final sets = TextEditingController();
  final reps = TextEditingController();
  final weight = TextEditingController();

  void dispose() {
    name.dispose();
    sets.dispose();
    reps.dispose();
    weight.dispose();
  }
}

class _CrossfitBuilderDialog extends StatefulWidget {
  const _CrossfitBuilderDialog();

  @override
  State<_CrossfitBuilderDialog> createState() => _CrossfitBuilderDialogState();
}

class _CrossfitBuilderDialogState extends State<_CrossfitBuilderDialog> {
  static const _formats = {
    'for_time': 'For Time',
    'amrap': 'AMRAP',
    'emom': 'EMOM',
    'rounds': 'Rounds',
  };
  static const _scoreTypes = {
    'time': 'Time',
    'reps': 'Reps',
    'rounds': 'Rounds + reps',
    'load': 'Load (kg)',
  };

  final _titleController = TextEditingController();
  final _timeCapController = TextEditingController();
  final _roundsController = TextEditingController();
  final _movements = <_MovementControllers>[_MovementControllers()];
  String _format = 'for_time';
  String _scoreType = 'time';
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _timeCapController.dispose();
    _roundsController.dispose();
    for (final movement in _movements) {
      movement.dispose();
    }
    super.dispose();
  }

  Future<void> _loadBenchmark() async {
    final benchmark = await showModalBottomSheet<BenchmarkWorkout>(
      context: context,
      isScrollControlled: true,
      backgroundColor: appSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(appRadiusXl)),
      ),
      builder: (context) => const _BenchmarkPickerSheet(),
    );
    if (benchmark != null) {
      _applyBenchmark(benchmark);
    }
  }

  void _applyBenchmark(BenchmarkWorkout benchmark) {
    final structure = benchmark.structure;
    setState(() {
      _error = null;
      _titleController.text = benchmark.name;
      final format = structure['format'] as String?;
      if (format != null && _formats.containsKey(format)) {
        _format = format;
      }
      final scoreType = structure['score_type'] as String?;
      if (scoreType != null && _scoreTypes.containsKey(scoreType)) {
        _scoreType = scoreType;
      }
      _timeCapController.text =
          structure['time_cap_minutes']?.toString() ?? '';
      _roundsController.text = structure['rounds']?.toString() ?? '';
      for (final movement in _movements) {
        movement.dispose();
      }
      _movements
        ..clear()
        ..addAll(
          benchmark.movements.map((item) {
            final controllers = _MovementControllers();
            controllers.name.text = item['name']?.toString() ?? '';
            controllers.reps.text = item['reps']?.toString() ?? '';
            controllers.weight.text = item['weight']?.toString() ?? '';
            return controllers;
          }),
        );
      if (_movements.isEmpty) {
        _movements.add(_MovementControllers());
      }
    });
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Enter a workout name.');
      return;
    }
    final movements = <Map<String, dynamic>>[];
    for (final movement in _movements) {
      final name = movement.name.text.trim();
      if (name.isEmpty) {
        continue;
      }
      movements.add({
        'name': name,
        'reps': movement.reps.text.trim(),
        'weight': movement.weight.text.trim(),
      });
    }
    if (movements.isEmpty) {
      setState(() => _error = 'Add at least one movement.');
      return;
    }
    final timeCap = int.tryParse(_timeCapController.text.trim());
    final rounds = int.tryParse(_roundsController.text.trim());
    Navigator.of(context).pop(
      _WorkoutDraft(
        title: title,
        structure: {
          'format': _format,
          'time_cap_minutes': ?timeCap,
          'rounds': ?rounds,
          'score_type': _scoreType,
          'movements': movements,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: appSurface,
      title: const Text('New CrossFit workout', style: TextStyle(color: appText)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _loadBenchmark,
                icon: const Icon(Icons.bookmark_outline_rounded),
                label: const Text('Load a benchmark WOD'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Workout name'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _format,
                      decoration: const InputDecoration(labelText: 'Format'),
                      items: [
                        for (final entry in _formats.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _format = value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _scoreType,
                      decoration: const InputDecoration(labelText: 'Score'),
                      items: [
                        for (final entry in _scoreTypes.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _scoreType = value);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _timeCapController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Time cap (min)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _roundsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Rounds'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Movements',
                  style: TextStyle(color: appText, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _movements.length; i++) ...[
                _BuilderItemCard(
                  onRemove: _movements.length == 1
                      ? null
                      : () => setState(() => _movements.removeAt(i).dispose()),
                  children: [
                    TextField(
                      controller: _movements[i].name,
                      decoration: InputDecoration(
                        labelText: 'Movement',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search),
                          tooltip: 'Search exercises',
                          onPressed: () =>
                              _pickExerciseInto(context, _movements[i].name),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _movements[i].reps,
                            decoration: const InputDecoration(
                              labelText: 'Reps',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _movements[i].weight,
                            decoration: const InputDecoration(
                              labelText: 'Weight',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _movements.add(_MovementControllers())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add movement'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: appDanger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _FitnessBuilderDialog extends StatefulWidget {
  const _FitnessBuilderDialog();

  @override
  State<_FitnessBuilderDialog> createState() => _FitnessBuilderDialogState();
}

class _FitnessBuilderDialogState extends State<_FitnessBuilderDialog> {
  final _titleController = TextEditingController();
  final _exercises = <_ExerciseControllers>[_ExerciseControllers()];
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    for (final exercise in _exercises) {
      exercise.dispose();
    }
    super.dispose();
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Enter a workout name.');
      return;
    }
    final exercises = <Map<String, dynamic>>[];
    for (final exercise in _exercises) {
      final name = exercise.name.text.trim();
      if (name.isEmpty) {
        continue;
      }
      exercises.add({
        'name': name,
        'sets': int.tryParse(exercise.sets.text.trim()),
        'reps': int.tryParse(exercise.reps.text.trim()),
        'weight': exercise.weight.text.trim(),
      });
    }
    if (exercises.isEmpty) {
      setState(() => _error = 'Add at least one exercise.');
      return;
    }
    Navigator.of(context).pop(
      _WorkoutDraft(
        title: title,
        structure: {'exercises': exercises},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: appSurface,
      title: const Text('New Fitness workout', style: TextStyle(color: appText)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Workout name'),
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Exercises',
                  style: TextStyle(color: appText, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _exercises.length; i++) ...[
                _BuilderItemCard(
                  onRemove: _exercises.length == 1
                      ? null
                      : () => setState(() => _exercises.removeAt(i).dispose()),
                  children: [
                    TextField(
                      controller: _exercises[i].name,
                      decoration: InputDecoration(
                        labelText: 'Exercise',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search),
                          tooltip: 'Search exercises',
                          onPressed: () =>
                              _pickExerciseInto(context, _exercises[i].name),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _exercises[i].sets,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Sets'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _exercises[i].reps,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Reps'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _exercises[i].weight,
                            decoration: const InputDecoration(
                              labelText: 'Weight',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _exercises.add(_ExerciseControllers())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add exercise'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: appDanger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _BuilderItemCard extends StatelessWidget {
  const _BuilderItemCard({required this.children, this.onRemove});

  final List<Widget> children;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: appSurfaceAlt,
        borderRadius: BorderRadius.circular(appRadiusMd),
        border: Border.all(color: appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...children,
          if (onRemove != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Remove'),
                style: TextButton.styleFrom(foregroundColor: appSubtleText),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _pickExerciseInto(
  BuildContext context,
  TextEditingController controller,
) async {
  final name = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: appSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(appRadiusXl)),
    ),
    builder: (context) => const _ExercisePickerSheet(),
  );
  if (name != null && name.isNotEmpty) {
    controller.text = name;
  }
}

class _ExercisePickerSheet extends ConsumerStatefulWidget {
  const _ExercisePickerSheet();

  @override
  ConsumerState<_ExercisePickerSheet> createState() =>
      _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends ConsumerState<_ExercisePickerSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  late Future<List<Exercise>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load('');
  }

  Future<List<Exercise>> _load(String query) {
    return ref
        .read(exerciseRepositoryProvider)
        .fetchExercises(query: query, limit: 50);
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _future = _load(value.trim());
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: _onQueryChanged,
                decoration: InputDecoration(
                  hintText: 'Search exercises',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: appSurfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(appRadiusMd),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Exercise>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        errorMessageFrom(
                          snapshot.error!,
                          fallback: 'Failed to load exercises',
                        ),
                        style: const TextStyle(color: appSubtleText),
                      ),
                    );
                  }
                  final exercises = snapshot.data ?? const <Exercise>[];
                  if (exercises.isEmpty) {
                    return const Center(
                      child: Text(
                        'No matching exercises',
                        style: TextStyle(color: appSubtleText),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: exercises.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, color: appBorder),
                    itemBuilder: (context, index) {
                      final exercise = exercises[index];
                      return ListTile(
                        title: Text(
                          exercise.name,
                          style: const TextStyle(
                            color: appText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: exercise.subtitle.isEmpty
                            ? null
                            : Text(
                                exercise.subtitle,
                                style: const TextStyle(color: appSubtleText),
                              ),
                        onTap: () => Navigator.of(context).pop(exercise.name),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BenchmarkPickerSheet extends ConsumerStatefulWidget {
  const _BenchmarkPickerSheet();

  @override
  ConsumerState<_BenchmarkPickerSheet> createState() =>
      _BenchmarkPickerSheetState();
}

class _BenchmarkPickerSheetState extends ConsumerState<_BenchmarkPickerSheet> {
  late final Future<List<BenchmarkWorkout>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(benchmarkRepositoryProvider).fetchBenchmarks();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
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
                'Benchmark WODs',
                style: TextStyle(
                  color: appText,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<BenchmarkWorkout>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      errorMessageFrom(
                        snapshot.error!,
                        fallback: 'Failed to load benchmarks',
                      ),
                      style: const TextStyle(color: appSubtleText),
                    ),
                  );
                }
                final all = snapshot.data ?? const <BenchmarkWorkout>[];
                final girls =
                    all.where((item) => item.category == 'girl').toList();
                final heroes =
                    all.where((item) => item.category == 'hero').toList();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    if (girls.isNotEmpty) ...[
                      const _BenchmarkGroupHeader(label: 'The Girls'),
                      for (final workout in girls)
                        _BenchmarkTile(workout: workout),
                    ],
                    if (heroes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const _BenchmarkGroupHeader(label: 'Hero WODs'),
                      for (final workout in heroes)
                        _BenchmarkTile(workout: workout),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BenchmarkGroupHeader extends StatelessWidget {
  const _BenchmarkGroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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

class _BenchmarkTile extends StatelessWidget {
  const _BenchmarkTile({required this.workout});

  final BenchmarkWorkout workout;

  String _summary() {
    final format = _crossfitFormatLabel(workout.structure['format'] as String?);
    final count = workout.movements.length;
    return [
      ?format,
      '$count movement${count == 1 ? '' : 's'}',
    ].join(' · ');
  }

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
        leading: const AppAccentBadge(
          icon: Icons.local_fire_department_outlined,
          color: _crossfitColor,
          size: 42,
        ),
        title: Text(
          workout.name,
          style: const TextStyle(color: appText, fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          _summary(),
          style: const TextStyle(color: appSubtleText),
        ),
        trailing: const Icon(Icons.add_rounded, color: _crossfitColor),
        onTap: () => Navigator.of(context).pop(workout),
      ),
    );
  }
}

