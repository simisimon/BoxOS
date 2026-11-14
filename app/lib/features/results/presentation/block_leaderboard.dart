import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/results/data/api_results_repository.dart';
import 'package:app/features/results/domain/workout_result.dart';
import 'package:app/features/results/presentation/result_detail_panel.dart';
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
          children: [
            for (final entry in entries)
              LeaderboardRow(entry: entry, workoutId: widget.workoutId),
          ],
        );
      },
    );
  }
}

/// One leaderboard line: rank, athlete, score, division, and the fist
/// bump, comment and photo marks. Tapping opens the result with its
/// photo and comments; the fist bumps it straight away.
class LeaderboardRow extends ConsumerWidget {
  const LeaderboardRow({super.key, required this.entry, this.workoutId});

  final LeaderboardEntry entry;

  /// Refreshed after a bump or comment, so counts stay in step.
  final int? workoutId;

  Future<void> _bump(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(resultsRepositoryProvider)
          .setBump(entry.resultId, bumped: !entry.bumpedByMe);
      final id = workoutId;
      if (id != null) ref.invalidate(leaderboardProvider(id));
      ref.invalidate(resultDetailProvider(entry.resultId));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send the fist bump.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final social = entry.resultId != 0;
    const mark = TextStyle(color: appSubtleText, fontSize: 11);
    return Material(
      color: entry.isMe
          ? appPrimary.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(appRadiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(appRadiusMd),
        onTap: social
            ? () => showResultDetailPanel(
                context,
                resultId: entry.resultId,
                workoutId: workoutId,
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: appSpaceSm,
            vertical: appSpaceXs,
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
                        style: const TextStyle(
                          color: appSubtleText,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              if (entry.photoUrl.isNotEmpty) ...[
                const Icon(
                  Icons.photo_camera_outlined,
                  size: 14,
                  color: appSubtleText,
                ),
                const SizedBox(width: appSpaceSm),
              ],
              if (entry.commentCount > 0) ...[
                const Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 13,
                  color: appSubtleText,
                ),
                const SizedBox(width: 2),
                Text('${entry.commentCount}', style: mark),
                const SizedBox(width: appSpaceSm),
              ],
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
              if (social)
                FistBumpButton(
                  key: ValueKey('bump-${entry.resultId}'),
                  count: entry.bumpCount,
                  bumped: entry.bumpedByMe,
                  onPressed: () => _bump(context, ref),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 👊 and the count; filled when the viewer bumped.
class FistBumpButton extends StatelessWidget {
  const FistBumpButton({
    super.key,
    required this.count,
    required this.bumped,
    required this.onPressed,
  });

  final int count;
  final bool bumped;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: bumped ? 'Take back your fist bump' : 'Fist bump',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          margin: const EdgeInsets.only(left: appSpaceSm),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: bumped ? appPrimary.withValues(alpha: 0.18) : null,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: bumped ? appPrimary : appBorder),
          ),
          child: Text(
            count > 0 ? '👊 $count' : '👊',
            style: TextStyle(
              color: bumped ? appText : appMutedText,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
