import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/results/data/api_results_repository.dart';
import 'package:app/features/results/domain/workout_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Leaderboard (n)" under a WOD block; expands to everyone's results,
/// Rx before Scaled, ranked by score.
class BlockLeaderboard extends ConsumerStatefulWidget {
  const BlockLeaderboard({
    super.key,
    required this.workoutId,
    required this.sectionId,
    required this.count,
  });

  final int workoutId;
  final int sectionId;
  final int count;

  @override
  ConsumerState<BlockLeaderboard> createState() => _BlockLeaderboardState();
}

class _BlockLeaderboardState extends ConsumerState<BlockLeaderboard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: ValueKey('leaderboard-${widget.sectionId}'),
            onPressed: () => setState(() => _open = !_open),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
            icon: Icon(
              _open ? Icons.expand_less_rounded : Icons.leaderboard_outlined,
              size: 16,
            ),
            label: Text('Leaderboard (${widget.count})'),
          ),
        ),
        if (_open) _entries(),
      ],
    );
  }

  Widget _entries() {
    final board = ref.watch(leaderboardProvider(widget.workoutId));
    return board.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(appSpaceSm),
        child: LinearProgressIndicator(),
      ),
      error: (_, _) => const Text(
        'Could not load the leaderboard.',
        style: TextStyle(color: appDanger, fontSize: 12),
      ),
      data: (sections) {
        final entries = sections[widget.sectionId] ?? const [];
        if (entries.isEmpty) {
          return const Text(
            'No results yet.',
            style: TextStyle(color: appSubtleText, fontSize: 12),
          );
        }
        return Column(
          children: [for (final entry in entries) LeaderboardRow(entry: entry)],
        );
      },
    );
  }
}

class LeaderboardRow extends StatelessWidget {
  const LeaderboardRow({super.key, required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(
        horizontal: appSpaceSm,
        vertical: appSpaceXs,
      ),
      decoration: BoxDecoration(
        color: entry.isMe ? appPrimary.withValues(alpha: 0.12) : null,
        borderRadius: BorderRadius.circular(appRadiusMd),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '${entry.rank}',
              style: appMono(fontSize: 12, color: appMutedText),
            ),
          ),
          AppAvatar(
            displayName: entry.name,
            imageUrl: entry.avatarUrl.isEmpty ? null : entry.avatarUrl,
            size: 24,
          ),
          const SizedBox(width: appSpaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.isMe ? '${entry.name} (you)' : entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: appText, fontSize: 13),
                ),
                if (entry.notes.isNotEmpty)
                  Text(
                    entry.notes,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: appSubtleText, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (entry.isPr) ...[
            const AppPill(
              label: 'PR',
              intent: AppPillIntent.warning,
              dense: true,
            ),
            const SizedBox(width: appSpaceSm),
          ],
          Text(
            entry.scoreLabel,
            style: const TextStyle(
              color: appText,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: appSpaceSm),
          SizedBox(
            width: 48,
            child: Text(
              entry.division == ResultDivision.rx ? 'Rx' : 'Scaled',
              textAlign: TextAlign.end,
              style: const TextStyle(color: appMutedText, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
