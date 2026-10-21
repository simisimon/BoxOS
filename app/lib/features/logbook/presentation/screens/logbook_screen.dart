import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/features/logbook/data/repositories/api_logbook_repository.dart';
import 'package:app/features/logbook/domain/models/workout_log_entry.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The athlete's training history: every WOD they logged a result for, newest
/// first, with its score and the movements it was made of. Nothing to create
/// or track here — results are logged from the WOD itself.
class LogbookScreen extends ConsumerStatefulWidget {
  const LogbookScreen({super.key});

  @override
  ConsumerState<LogbookScreen> createState() => _LogbookScreenState();
}

class _LogbookScreenState extends ConsumerState<LogbookScreen> {
  late Future<List<WorkoutLogEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = _loadEntries();
  }

  Future<List<WorkoutLogEntry>> _loadEntries() {
    return ref.read(logbookRepositoryProvider).fetchEntries();
  }

  Future<void> _refresh() async {
    setState(() => _entriesFuture = _loadEntries());
    ref.invalidate(programmingListProvider);
    await _entriesFuture;
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final hasActiveGym = profile?.activeGym != null;
    // The log only knows the WOD's title; its movements come from programming.
    final sectionsByWorkout = {
      for (final workout
          in ref.watch(programmingListProvider).value ?? const <DailyWorkout>[])
        workout.id: workout.sections,
    };

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            'Workout history',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: appText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          if (hasActiveGym)
            _buildHistory(sectionsByWorkout)
          else
            const _StateCard(
              icon: Icons.history_outlined,
              title: 'Join a gym for history',
              message: 'Your workout history appears once a gym is active.',
            ),
        ],
      ),
    );
  }

  Widget _buildHistory(Map<int, List<DailyWorkoutSection>> sectionsByWorkout) {
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
          );
        }
        final entries = snapshot.data ?? const <WorkoutLogEntry>[];
        if (entries.isEmpty) {
          return const _StateCard(
            icon: Icons.menu_book_outlined,
            title: 'No workout logs yet',
            message:
                'Open a WOD and use "Log Results" — every logged result shows up here.',
          );
        }
        return Column(
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _HistoryCard(
                entry: entries[i],
                sections:
                    sectionsByWorkout[entries[i].dailyWorkoutId] ?? const [],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// One logged WOD: title, date and class, the score (with PR flag), the
/// movements of that WOD and the athlete's own notes.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry, required this.sections});

  final WorkoutLogEntry entry;
  final List<DailyWorkoutSection> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(entry.scheduledDate);
    final className = entry.classTitle ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: appBorder),
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
                      entry.workoutTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      className.isEmpty ? date : '$date · $className',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: appSubtleText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    entry.scoreLabel,
                    style: appMono(
                      fontSize: 18,
                      color: appText,
                      letterSpacing: 0,
                    ),
                  ),
                  if (entry.isPr) ...[
                    const SizedBox(height: 4),
                    const _PrBadge(),
                  ],
                ],
              ),
            ],
          ),
          if (sections.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final section in sections)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  _sectionLine(section),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: appMutedText,
                    height: 1.35,
                  ),
                ),
              ),
          ],
          if (entry.notesText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              entry.notesText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: appText,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// "Back Squat — 5-5-3-3-1" or just the description when untitled.
  static String _sectionLine(DailyWorkoutSection section) {
    final title = section.title.trim();
    final detail = section.description.trim().split('\n').first.trim();
    if (title.isEmpty) return detail;
    if (detail.isEmpty) return title;
    return '$title — $detail';
  }
}

class _PrBadge extends StatelessWidget {
  const _PrBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: appPrimary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: appPrimary.withValues(alpha: 0.45)),
      ),
      child: Text('PR', style: appMono(fontSize: 10, color: appPrimary)),
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
        borderRadius: BorderRadius.circular(8),
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
