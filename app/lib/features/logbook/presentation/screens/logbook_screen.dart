import 'package:app/core/errors/error_message.dart';
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
    final profile = ref.watch(currentProfileProvider).valueOrNull;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _LogbookHero(),
          const SizedBox(height: 16),
          if (profile?.activeGym == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No active gym selected. Join or switch to a gym to view your logbook.'),
              ),
            )
          else
            FutureBuilder<List<WorkoutLogEntry>>(
              future: _entriesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        errorMessageFrom(snapshot.error!, fallback: 'Failed to load logbook'),
                      ),
                    ),
                  );
                }

                final entries = snapshot.data ?? const <WorkoutLogEntry>[];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle('Snapshot'),
                    const SizedBox(height: 8),
                    _SnapshotGrid(entries: entries),
                    const SizedBox(height: 16),
                    _SectionTitle('Recent Training'),
                    const SizedBox(height: 8),
                    if (entries.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No workout logs yet. Log a result from Programming to start your history.'),
                        ),
                      )
                    else
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              for (var i = 0; i < entries.length; i++) ...[
                                _HistoryRow(entry: entries[i]),
                                if (i != entries.length - 1) const Divider(),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _LogbookHero extends StatelessWidget {
  const _LogbookHero();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Logbook', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              'Your personal training history lives here, including logged workout results and workout-linked notes.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                Chip(label: Text('Workout History: Live')),
                Chip(label: Text('Result Logging: Live')),
                Chip(label: Text('PR Tracking: Next')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleLarge);
  }
}

class _SnapshotGrid extends StatelessWidget {
  const _SnapshotGrid({required this.entries});

  final List<WorkoutLogEntry> entries;

  @override
  Widget build(BuildContext context) {
    final thisWeekCount = entries.where((entry) {
      final now = DateTime.now();
      return entry.scheduledDate.isAfter(now.subtract(const Duration(days: 7)));
    }).length;
    final latest = entries.isEmpty ? 'Not yet' : entries.first.scoreLabel;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _SnapshotStat(label: 'Workouts This Week', value: '$thisWeekCount'),
        _SnapshotStat(label: 'Total Logged', value: '${entries.length}'),
        _SnapshotStat(label: 'Latest Score', value: latest),
      ],
    );
  }
}

class _SnapshotStat extends StatelessWidget {
  const _SnapshotStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 212,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final WorkoutLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final dateLabel = MaterialLocalizations.of(context).formatFullDate(entry.scheduledDate);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.fitness_center_outlined),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.workoutTitle, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('$dateLabel • ${entry.scoreLabel}'),
              if (entry.classTitle != null && entry.classTitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Class: ${entry.classTitle!}'),
              ],
              if (entry.notesText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(entry.notesText),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
