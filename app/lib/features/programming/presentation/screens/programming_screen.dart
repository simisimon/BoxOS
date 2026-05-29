import 'dart:ui';

import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/mobile_content.dart';
import 'package:app/features/logbook/data/repositories/api_logbook_repository.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProgrammingScreen extends ConsumerStatefulWidget {
  const ProgrammingScreen({super.key});

  @override
  ConsumerState<ProgrammingScreen> createState() => _ProgrammingScreenState();
}

class _ProgrammingScreenState extends ConsumerState<ProgrammingScreen> {
  late Future<List<DailyWorkout>> _workoutsFuture;

  @override
  void initState() {
    super.initState();
    _workoutsFuture = _loadWorkouts();
  }

  Future<List<DailyWorkout>> _loadWorkouts() {
    return ref.read(programmingRepositoryProvider).fetchWorkouts();
  }

  Future<void> _refresh() async {
    setState(() {
      _workoutsFuture = _loadWorkouts();
    });
  }

  Future<void> _openEditor({DailyWorkout? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _WorkoutEditorDialog(existing: existing),
    );
    if (saved == true) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final profileRole = profile?.role;
    final activeGym = profile?.activeGym;
    final canManage =
        activeGym != null &&
        (profileRole == UserRole.admin || profileRole == UserRole.trainer);
    final roleLabel = profileRole?.label ?? 'Athlete';
    final gymName = activeGym?.name;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(title: const Text('Programming')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFFFF6B2C),
              foregroundColor: Colors.white,
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('New WOD'),
            )
          : null,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF5F9FF),
              Color(0xFFEAF2FF),
              Color(0xFFF9FBFF),
            ],
          ),
        ),
        child: MobileContent(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
              children: [
                _ProgrammingHero(
                  canManage: canManage,
                  roleLabel: roleLabel,
                  gymName: gymName,
                ),
                const SizedBox(height: 16),
                _ProgrammingIntroBand(canManage: canManage),
                const SizedBox(height: 16),
                if (profile?.activeGym == null)
                  const _ProgrammingStateCard(
                    icon: Icons.store_mall_directory_outlined,
                    title: 'No active gym selected',
                    message:
                        'Join or switch to a gym to unlock the workout stream, whiteboard, and personal logging.',
                    accentColor: Color(0xFF5FB2FF),
                  )
                else
                  FutureBuilder<List<DailyWorkout>>(
                    future: _workoutsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        return _ProgrammingStateCard(
                          icon: Icons.error_outline,
                          title: 'Failed to load programming',
                          message: errorMessageFrom(
                            snapshot.error!,
                            fallback: 'Failed to load programming',
                          ),
                          accentColor: const Color(0xFFFF6B2C),
                        );
                      }

                      final workouts = snapshot.data ?? const <DailyWorkout>[];
                      if (workouts.isEmpty) {
                        return _ProgrammingStateCard(
                          icon: canManage
                              ? Icons.edit_calendar_outlined
                              : Icons.calendar_month_outlined,
                          title: canManage
                              ? 'No workouts programmed yet'
                              : 'No workouts published yet',
                          message: canManage
                              ? 'Add the first daily WOD to give coaches and athletes a proper training runway.'
                              : 'This gym has no scheduled workout yet. Pull to refresh or check back after your coach publishes the next block.',
                          accentColor: canManage
                              ? const Color(0xFFFF6B2C)
                              : const Color(0xFF7EE7C6),
                        );
                      }

                      return Column(
                        children: [
                          for (final workout in workouts) ...[
                            _WorkoutCard(
                              workout: workout,
                              canSubmitWhiteboard: profile?.activeGym != null,
                              canLogWorkout: profile?.activeGym != null,
                              onEdit: canManage && workout.canEdit
                                  ? () => _openEditor(existing: workout)
                                  : null,
                              onSubmitWhiteboard: () async {
                                final updated = await showDialog<bool>(
                                  context: context,
                                  builder: (context) =>
                                      _WhiteboardResultDialog(workout: workout),
                                );
                                if (updated == true) {
                                  await _refresh();
                                }
                              },
                              onLogWorkout: () async {
                                final updated = await showDialog<bool>(
                                  context: context,
                                  builder: (context) =>
                                      _WorkoutLogDialog(workout: workout),
                                );
                                if (updated == true) {
                                  await _refresh();
                                }
                              },
                            ),
                            const SizedBox(height: 14),
                          ],
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgrammingHero extends StatelessWidget {
  const _ProgrammingHero({
    required this.canManage,
    required this.roleLabel,
    required this.gymName,
  });

  final bool canManage;
  final String roleLabel;
  final String? gymName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = canManage
        ? const Color(0xFFFF6B2C)
        : const Color(0xFF7EE7C6);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withOpacity(0.24),
            const Color(0xFFFFFFFF),
            const Color(0xFFF3F8FF),
          ],
        ),
        border: Border.all(color: const Color(0xFFD8E4F2)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.14),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -12,
            top: -12,
            child: _GlowOrb(color: accentColor, size: 84),
          ),
          Positioned(
            right: 40,
            bottom: -28,
            child: _GlowOrb(
              color: const Color(0xFF5FB2FF).withOpacity(0.6),
              size: 88,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _HeroPill(label: roleLabel, color: accentColor),
                  _HeroPill(
                    label: gymName ?? 'No active gym',
                    color: const Color(0xFF7EE7C6),
                    outlined: true,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Programming',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF2563EB),
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                canManage
                    ? 'Shape the training week.'
                    : 'See the next training hit.',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: const Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                  height: 0.96,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                canManage
                    ? 'Build each daily WOD with cleaner structure, stronger hierarchy, and faster access to whiteboard and athlete logs.'
                    : 'Track the current WOD, whiteboard standings, and your own result history in one tighter workout stream.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF475569),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgrammingIntroBand extends StatelessWidget {
  const _ProgrammingIntroBand({required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _InfoBand(
          icon: canManage
              ? Icons.edit_calendar_outlined
              : Icons.local_fire_department_outlined,
          title: canManage ? 'Coach flow' : 'Athlete flow',
          subtitle: canManage
              ? 'Publish structure, notes, and benchmark context for each day.'
              : 'Read the plan quickly, then log your result without leaving the stream.',
          accentColor: canManage
              ? const Color(0xFFFF6B2C)
              : const Color(0xFF7EE7C6),
        ),
        const SizedBox(height: 12),
        const _InfoBand(
          icon: Icons.emoji_events_outlined,
          title: 'Whiteboard',
          subtitle: 'Live ranking, score type, notes, and personal updates stay attached to the workout card.',
          accentColor: Color(0xFF5FB2FF),
        ),
      ],
    );
  }
}

class _InfoBand extends StatelessWidget {
  const _InfoBand({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101826),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD8E4F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AccentBadge(icon: icon, color: accentColor),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgrammingStateCard extends StatelessWidget {
  const _ProgrammingStateCard({
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
        color: const Color(0xFF101826),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD8E4F2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AccentBadge(icon: icon, color: accentColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
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

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({
    required this.workout,
    required this.canSubmitWhiteboard,
    required this.canLogWorkout,
    this.onEdit,
    this.onSubmitWhiteboard,
    this.onLogWorkout,
  });

  final DailyWorkout workout;
  final bool canSubmitWhiteboard;
  final bool canLogWorkout;
  final VoidCallback? onEdit;
  final VoidCallback? onSubmitWhiteboard;
  final VoidCallback? onLogWorkout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final scheduledDate = localizations.formatFullDate(workout.scheduledDate);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101826),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFD8E4F2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5FB2FF).withOpacity(0.08),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scheduledDate.toUpperCase(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: const Color(0xFF7EE7C6),
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      workout.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: const Color(0xFF0F172A),
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              if (onEdit != null)
                IconButton.filledTonal(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit workout',
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (workout.strengthText.isNotEmpty)
                _WorkoutPill(label: 'Strength', color: const Color(0xFF5FB2FF)),
              if (workout.metconText.isNotEmpty)
                _WorkoutPill(label: 'MetCon', color: const Color(0xFFFF6B2C)),
              if (workout.notesText.isNotEmpty)
                _WorkoutPill(label: 'Notes', color: const Color(0xFFB98CFF)),
            ],
          ),
          if (workout.strengthText.isNotEmpty) ...[
            const SizedBox(height: 16),
            _WorkoutSection(
              label: 'Strength',
              value: workout.strengthText,
              accentColor: const Color(0xFF5FB2FF),
            ),
          ],
          if (workout.metconText.isNotEmpty) ...[
            const SizedBox(height: 14),
            _WorkoutSection(
              label: 'MetCon',
              value: workout.metconText,
              accentColor: const Color(0xFFFF6B2C),
            ),
          ],
          if (workout.notesText.isNotEmpty) ...[
            const SizedBox(height: 14),
            _WorkoutSection(
              label: 'Notes',
              value: workout.notesText,
              accentColor: const Color(0xFFB98CFF),
            ),
          ],
          const SizedBox(height: 18),
          _PanelSection(
            child: _WhiteboardSection(
              workout: workout,
              canSubmit: canSubmitWhiteboard,
              onSubmit: onSubmitWhiteboard,
            ),
          ),
          const SizedBox(height: 14),
          _PanelSection(
            child: _WorkoutLogSection(
              workout: workout,
              canLog: canLogWorkout,
              onLog: onLogWorkout,
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelSection extends StatelessWidget {
  const _PanelSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD8E4F2)),
      ),
      child: child,
    );
  }
}

class _WorkoutLogSection extends StatelessWidget {
  const _WorkoutLogSection({
    required this.workout,
    required this.canLog,
    this.onLog,
  });

  final DailyWorkout workout;
  final bool canLog;
  final VoidCallback? onLog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'My log',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (canLog && onLog != null)
              OutlinedButton.icon(
                onPressed: onLog,
                icon: const Icon(Icons.edit_note_outlined),
                label: Text(
                  workout.myWorkoutLog == null ? 'Log Workout' : 'Update Log',
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (workout.myWorkoutLog == null)
          Text(
            'No personal workout log yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF64748B),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF151F31),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${workout.myWorkoutLog!.scoreLabel} (${_scoreTypeLabel(workout.myWorkoutLog!.scoreType)})',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: const Color(0xFF0F172A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (workout.myWorkoutLog!.isPr)
                      const Chip(label: Text('PR')),
                  ],
                ),
                if (workout.myWorkoutLog!.notesText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    workout.myWorkoutLog!.notesText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
                if (!workout.myWorkoutLog!.isPr &&
                    workout.myWorkoutLog!.prRank != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Benchmark rank: #${workout.myWorkoutLog!.prRank}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF7EE7C6),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _WhiteboardSection extends StatelessWidget {
  const _WhiteboardSection({
    required this.workout,
    required this.canSubmit,
    this.onSubmit,
  });

  final DailyWorkout workout;
  final bool canSubmit;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Whiteboard',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (canSubmit && onSubmit != null)
              OutlinedButton.icon(
                onPressed: onSubmit,
                icon: const Icon(Icons.emoji_events_outlined),
                label: Text(
                  workout.myWhiteboardResult == null
                      ? 'Submit Result'
                      : 'Update Result',
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (workout.myWhiteboardResult != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF151F31),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My result: ${workout.myWhiteboardResult!.scoreLabel} (${_scoreTypeLabel(workout.myWhiteboardResult!.scoreType)})',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (workout.myWhiteboardResult!.notesText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    workout.myWhiteboardResult!.notesText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (workout.whiteboardResults.isEmpty)
          Text(
            'No whiteboard results yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF64748B),
            ),
          )
        else
          Column(
            children: [
              for (final result in workout.whiteboardResults) ...[
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFF1E2A43),
                        child: Text(
                          '${result.rank}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: const Color(0xFF0F172A),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              result.athleteName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: const Color(0xFF0F172A),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              result.notesText.isEmpty
                                  ? _scoreTypeLabel(result.scoreType)
                                  : '${_scoreTypeLabel(result.scoreType)} • ${result.notesText}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        result.scoreLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: const Color(0xFF7EE7C6),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0x1FFFFFFF)),
              ],
            ],
          ),
      ],
    );
  }
}

String _scoreTypeLabel(String value) {
  switch (value) {
    case 'time':
      return 'For time';
    case 'reps':
      return 'Reps';
    case 'load':
      return 'Load';
    default:
      return value;
  }
}

class _WorkoutPill extends StatelessWidget {
  const _WorkoutPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: const Color(0xFF0F172A),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _WorkoutSection extends StatelessWidget {
  const _WorkoutSection({
    required this.label,
    required this.value,
    required this.accentColor,
  });

  final String label;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accentColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: accentColor,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF0F172A),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({
    required this.label,
    required this.color,
    this.outlined = false,
  });

  final String label;
  final Color color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(outlined ? 0.55 : 0.3)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: const Color(0xFF0F172A),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withOpacity(0.95),
              color.withOpacity(0.0),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentBadge extends StatelessWidget {
  const _AccentBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(0.28),
                color.withOpacity(0.12),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.28)),
          ),
          child: Icon(icon, color: color),
        ),
      ),
    );
  }
}

class _WorkoutEditorDialog extends ConsumerStatefulWidget {
  const _WorkoutEditorDialog({this.existing});

  final DailyWorkout? existing;

  @override
  ConsumerState<_WorkoutEditorDialog> createState() =>
      _WorkoutEditorDialogState();
}

class _WorkoutEditorDialogState extends ConsumerState<_WorkoutEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _selectedDate;
  late TextEditingController _titleController;
  late TextEditingController _strengthController;
  late TextEditingController _metconController;
  late TextEditingController _notesController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.existing?.scheduledDate ?? DateTime.now();
    _titleController = TextEditingController(text: widget.existing?.title ?? 'Daily WOD');
    _strengthController = TextEditingController(text: widget.existing?.strengthText ?? '');
    _metconController = TextEditingController(text: widget.existing?.metconText ?? '');
    _notesController = TextEditingController(text: widget.existing?.notesText ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _strengthController.dispose();
    _metconController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 0)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      final repository = ref.read(programmingRepositoryProvider);
      if (widget.existing == null) {
        await repository.createWorkout(
          scheduledDate: _selectedDate,
          title: _titleController.text.trim(),
          strengthText: _strengthController.text.trim(),
          metconText: _metconController.text.trim(),
          notesText: _notesController.text.trim(),
        );
      } else {
        await repository.updateWorkout(
          id: widget.existing!.id,
          scheduledDate: _selectedDate,
          title: _titleController.text.trim(),
          strengthText: _strengthController.text.trim(),
          metconText: _metconController.text.trim(),
          notesText: _notesController.text.trim(),
        );
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to save workout'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = MaterialLocalizations.of(context).formatFullDate(_selectedDate);
    return AlertDialog(
      title: Text(widget.existing == null ? 'New Daily WOD' : 'Edit Daily WOD'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(dateLabel),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Enter a workout title';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _strengthController,
                  decoration: const InputDecoration(labelText: 'Strength'),
                  minLines: 3,
                  maxLines: 5,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _metconController,
                  decoration: const InputDecoration(labelText: 'MetCon'),
                  minLines: 3,
                  maxLines: 5,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _WhiteboardResultDialog extends ConsumerStatefulWidget {
  const _WhiteboardResultDialog({required this.workout});

  final DailyWorkout workout;

  @override
  ConsumerState<_WhiteboardResultDialog> createState() =>
      _WhiteboardResultDialogState();
}

class _WhiteboardResultDialogState extends ConsumerState<_WhiteboardResultDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _scoreType;
  late TextEditingController _scoreValueController;
  late TextEditingController _notesController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _scoreType = widget.workout.myWhiteboardResult?.scoreType ?? 'time';
    _scoreValueController = TextEditingController(
      text: widget.workout.myWhiteboardResult?.scoreLabel ?? '',
    );
    _notesController = TextEditingController(
      text: widget.workout.myWhiteboardResult?.notesText ?? '',
    );
  }

  @override
  void dispose() {
    _scoreValueController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      await ref.read(programmingRepositoryProvider).submitWhiteboardResult(
            workoutId: widget.workout.id,
            scoreType: _scoreType,
            scoreValue: _scoreValueController.text.trim(),
            notesText: _notesController.text.trim(),
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to save whiteboard result'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Submit Whiteboard Result'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _scoreType,
                  decoration: const InputDecoration(labelText: 'Score Type'),
                  items: const [
                    DropdownMenuItem(value: 'time', child: Text('For time')),
                    DropdownMenuItem(value: 'reps', child: Text('Reps')),
                    DropdownMenuItem(value: 'load', child: Text('Load')),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _scoreType = value);
                          }
                        },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _scoreValueController,
                  decoration: InputDecoration(
                    labelText: _scoreType == 'time'
                        ? 'Score (mm:ss or hh:mm:ss)'
                        : _scoreType == 'reps'
                            ? 'Score (reps)'
                            : 'Score (load)',
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Enter a score';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _WorkoutLogDialog extends ConsumerStatefulWidget {
  const _WorkoutLogDialog({required this.workout});

  final DailyWorkout workout;

  @override
  ConsumerState<_WorkoutLogDialog> createState() => _WorkoutLogDialogState();
}

class _WorkoutLogDialogState extends ConsumerState<_WorkoutLogDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _scoreType;
  late TextEditingController _scoreValueController;
  late TextEditingController _notesController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _scoreType = widget.workout.myWorkoutLog?.scoreType ?? 'time';
    _scoreValueController = TextEditingController(
      text: widget.workout.myWorkoutLog?.scoreLabel ?? '',
    );
    _notesController = TextEditingController(
      text: widget.workout.myWorkoutLog?.notesText ?? '',
    );
  }

  @override
  void dispose() {
    _scoreValueController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      await ref.read(logbookRepositoryProvider).submitEntry(
            workoutId: widget.workout.id,
            scoreType: _scoreType,
            scoreValue: _scoreValueController.text.trim(),
            notesText: _notesController.text.trim(),
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to save workout log'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Log Workout Result'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _scoreType,
                  decoration: const InputDecoration(labelText: 'Score Type'),
                  items: const [
                    DropdownMenuItem(value: 'time', child: Text('For time')),
                    DropdownMenuItem(value: 'reps', child: Text('Reps')),
                    DropdownMenuItem(value: 'load', child: Text('Load')),
                  ],
                  onChanged: _isSaving ? null : (value) {
                    if (value != null) {
                      setState(() => _scoreType = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _scoreValueController,
                  decoration: InputDecoration(
                    labelText: _scoreType == 'time'
                        ? 'Score (mm:ss or hh:mm:ss)'
                        : _scoreType == 'reps'
                            ? 'Score (reps)'
                            : 'Score (load)',
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty ? 'Enter a score' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
