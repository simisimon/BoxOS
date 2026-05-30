import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/features/logbook/data/repositories/api_logbook_repository.dart';
import 'package:app/features/logbook/domain/models/workout_log_entry.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    setState(() {
      _entriesFuture = _loadEntries();
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final gymName = profile?.activeGym?.name;

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
            _LogbookHero(gymName: gymName),
            const SizedBox(height: 16),
            if (profile?.activeGym == null)
              const _StateCard(
                icon: Icons.store_mall_directory_outlined,
                title: 'No active gym selected',
                message:
                    'Join or switch to a gym to unlock your workout history, PR trail, and recent result log.',
                accentColor: appPrimary,
              )
            else
              FutureBuilder<List<WorkoutLogEntry>>(
                future: _entriesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
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
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionTitle(
                        eyebrow: 'Snapshot',
                        title: 'Performance board',
                        subtitle:
                            'Quick read on training volume, freshest score, and recent PR momentum.',
                      ),
                      const SizedBox(height: 12),
                      _SnapshotGrid(entries: entries),
                      const SizedBox(height: 20),
                      const _SectionTitle(
                        eyebrow: 'Recent Training',
                        title: 'Logged history',
                        subtitle:
                            'Every workout result stays readable, ranked, and tied back to class context.',
                      ),
                      const SizedBox(height: 12),
                      if (entries.isEmpty)
                        const _StateCard(
                          icon: Icons.menu_book_outlined,
                          title: 'No workout logs yet',
                          message:
                              'Log a result from Programming to start building your personal training history.',
                          accentColor: appPrimary,
                        )
                      else
                        Column(
                          children: [
                            for (var i = 0; i < entries.length; i++) ...[
                              _HistoryCard(entry: entries[i]),
                              if (i != entries.length - 1)
                                const SizedBox(height: 12),
                            ],
                          ],
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _LogbookHero extends StatelessWidget {
  const _LogbookHero({required this.gymName});

  final String? gymName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const accentColor = appPrimary;

    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentColor.withOpacity(0.24), appSurface, appSurfaceAlt],
        ),
        border: Border.all(color: appBorder),
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
            right: 38,
            bottom: -28,
            child: _GlowOrb(color: appPrimary.withOpacity(0.6), size: 88),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  const _HeroPill(label: 'Logbook', color: accentColor),
                  _HeroPill(
                    label: gymName ?? 'No active gym',
                    color: appPrimary,
                    outlined: true,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Logbook',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: appPrimary,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your training block, archived cleanly.',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: appText,
                  fontWeight: FontWeight.w900,
                  height: 0.96,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Track workout history, result quality, class context, and PR momentum in one more readable performance stream.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: appMutedText,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _HeroPill(label: 'Workout History', color: appPrimary),
                  _HeroPill(label: 'Result Logging', color: appPrimary),
                  _HeroPill(label: 'PR Tracking', color: appPrimary),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: appPrimary,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: appText,
            fontWeight: FontWeight.w800,
            height: 0.96,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: appSubtleText,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _SnapshotGrid extends StatelessWidget {
  const _SnapshotGrid({required this.entries});

  final List<WorkoutLogEntry> entries;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final thisWeekCount = entries
        .where(
          (entry) => entry.scheduledDate.isAfter(
            now.subtract(const Duration(days: 7)),
          ),
        )
        .length;
    final latest = entries.isEmpty ? 'Not yet' : entries.first.scoreLabel;
    WorkoutLogEntry? latestPr;
    for (final entry in entries) {
      if (entry.isPr) {
        latestPr = entry;
        break;
      }
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SnapshotStat(
                label: 'Workouts This Week',
                value: '$thisWeekCount',
                accentColor: appPrimary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SnapshotStat(
                label: 'Total Logged',
                value: '${entries.length}',
                accentColor: appPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SnapshotStat(
                label: 'Latest Score',
                value: latest,
                accentColor: appPrimary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SnapshotStat(
                label: 'Latest PR',
                value: latestPr?.scoreLabel ?? 'Not yet',
                accentColor: appPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SnapshotStat extends StatelessWidget {
  const _SnapshotStat({
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accentColor.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: accentColor,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              color: appText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry});

  final WorkoutLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel = MaterialLocalizations.of(
      context,
    ).formatFullDate(entry.scheduledDate);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: appBorder),
        boxShadow: [
          BoxShadow(
            color: appPrimary.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Row(
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
                      borderRadius: BorderRadius.circular(18),
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
        borderRadius: BorderRadius.circular(24),
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
          color: appText,
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
            colors: [color.withOpacity(0.95), color.withOpacity(0.0)],
          ),
        ),
      ),
    );
  }
}
