import 'package:app/features/profile/application/profile_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LogbookScreen extends ConsumerWidget {
  const LogbookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(currentProfileProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _LogbookHero(),
        SizedBox(height: 16),
        _SectionTitle('Snapshot'),
        SizedBox(height: 8),
        _SnapshotGrid(),
        SizedBox(height: 16),
        _SectionTitle('Recent Training'),
        SizedBox(height: 8),
        _PlaceholderHistoryCard(),
        SizedBox(height: 16),
        _SectionTitle('PRs & Benchmarks'),
        SizedBox(height: 8),
        _PlaceholderPrCard(),
        SizedBox(height: 16),
        _SectionTitle('Trends'),
        SizedBox(height: 8),
        _PlaceholderTrendCard(),
      ],
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
              'This is where your training history, PRs, benchmarks, and long-term progress will live.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                Chip(label: Text('Workout History: Planned')),
                Chip(label: Text('PR Tracking: Planned')),
                Chip(label: Text('Trends: Planned')),
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
  const _SnapshotGrid();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _SnapshotStat(label: 'Workouts This Week', value: '0'),
        _SnapshotStat(label: 'Current Streak', value: '0 days'),
        _SnapshotStat(label: 'Latest PR', value: 'Not yet'),
        _SnapshotStat(label: 'Benchmarks Logged', value: '0'),
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

class _PlaceholderHistoryCard extends StatelessWidget {
  const _PlaceholderHistoryCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Recent Entries'),
            SizedBox(height: 12),
            _PlaceholderRow(
              title: 'Today\'s WOD',
              subtitle: 'Logged score, notes, and scaling details will appear here.',
            ),
            Divider(),
            _PlaceholderRow(
              title: 'Previous Classes',
              subtitle: 'Completed classes and attendance will populate this list.',
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderPrCard extends StatelessWidget {
  const _PlaceholderPrCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('PR Shelf'),
            SizedBox(height: 12),
            _PlaceholderRow(
              title: 'Strength PRs',
              subtitle: 'Back squat, deadlift, clean, snatch, and more.',
            ),
            Divider(),
            _PlaceholderRow(
              title: 'Benchmark PRs',
              subtitle: 'Named workouts and repeat benchmark comparisons.',
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderTrendCard extends StatelessWidget {
  const _PlaceholderTrendCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Progress Trends'),
            SizedBox(height: 12),
            _PlaceholderRow(
              title: 'Consistency',
              subtitle: 'Training frequency and streaks over time.',
            ),
            Divider(),
            _PlaceholderRow(
              title: 'Performance',
              subtitle: 'Loads, times, rounds, and benchmark trendlines.',
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderRow extends StatelessWidget {
  const _PlaceholderRow({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
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
          child: const Icon(Icons.insights_outlined),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(subtitle),
            ],
          ),
        ),
      ],
    );
  }
}
