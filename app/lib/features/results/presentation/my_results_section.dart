import 'package:app/core/errors/error_message.dart';
import 'package:app/core/platform/save_text_file.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/results/data/api_results_repository.dart';
import 'package:app/features/results/domain/workout_result.dart';
import 'package:app/features/results/presentation/log_personal_result_panel.dart';
import 'package:app/features/results/presentation/log_result_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _number(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

/// Profile › Results: the athlete's results, newest first, filtered to one
/// movement or named workout; a lift also shows its percentage chart.
///
/// With [memberId] it shows that member's results at the owner's gym
/// (Member details › Results), without export and privacy.
class MyResultsSection extends ConsumerStatefulWidget {
  const MyResultsSection({super.key, this.memberId});

  final int? memberId;

  @override
  ConsumerState<MyResultsSection> createState() => _MyResultsSectionState();
}

class _MyResultsSectionState extends ConsumerState<MyResultsSection> {
  ResultFilter? _filter;
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final csv = await ref.read(resultsRepositoryProvider).exportResultsCsv();
      final saved = await saveTextFile(
        'boxos-results.csv',
        csv,
        mimeType: 'text/csv',
      );
      if (!saved) await Clipboard.setData(ClipboardData(text: csv));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            saved ? 'Results downloaded.' : 'Results copied as CSV.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Something went wrong.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _logWorkout([WorkoutResult? existing]) async {
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await showLogPersonalResultPanel(
      context,
      existing: existing,
    );
    if (outcome == null || !mounted) return;
    ref.invalidate(myResultsProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (outcome) {
          LogResultOutcome.savedPr => 'Saved. New PR!',
          LogResultOutcome.saved => 'Saved to your logbook.',
          LogResultOutcome.deleted => 'Result deleted.',
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final memberId = widget.memberId;
    final all = memberId == null
        ? ref.watch(myResultsProvider(null))
        : ref.watch(memberResultsProvider((memberId, null)));
    final shown = memberId == null
        ? ref.watch(myResultsProvider(_filter))
        : ref.watch(memberResultsProvider((memberId, _filter)));
    final filters = all.value?.filters ?? const <ResultFilter>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: appSpaceMd,
          runSpacing: appSpaceSm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: DropdownButtonFormField<ResultFilter?>(
                key: ValueKey(_filter),
                initialValue: _filter,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Movement or workout',
                ),
                items: [
                  const DropdownMenuItem<ResultFilter?>(
                    value: null,
                    child: Text('All results'),
                  ),
                  for (final filter in filters)
                    DropdownMenuItem<ResultFilter?>(
                      value: filter,
                      child: Text('${filter.label} (${filter.count})'),
                    ),
                ],
                onChanged: (value) => setState(() => _filter = value),
              ),
            ),
            if (memberId == null)
              FilledButton.icon(
                onPressed: () => _logWorkout(),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Log workout'),
              ),
            if (memberId == null)
              OutlinedButton.icon(
                onPressed: _exporting || filters.isEmpty ? null : _export,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Download CSV'),
              ),
          ],
        ),
        const SizedBox(height: appSpaceMd),
        shown.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Text(
            'Could not load your results.',
            style: TextStyle(color: appDanger),
          ),
          data: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_filter?.movementId != null && data.bestSets.isNotEmpty) ...[
                PercentageChart(bestSets: data.bestSets),
                const SizedBox(height: appSpaceMd),
              ],
              _ResultsCard(
                results: data.results,
                emptyText: memberId == null
                    ? 'No results yet. Log one from the WOD of the day on '
                          'Home, or log a workout of your own.'
                    : 'No results logged at your gym yet.',
                onEditPersonal: memberId == null ? _logWorkout : null,
              ),
            ],
          ),
        ),
        if (memberId == null) ...[
          const SizedBox(height: appSpaceLg),
          const ResultsPrivacyCard(),
        ],
      ],
    );
  }
}

/// Who sees the athlete's results on gym leaderboards.
class ResultsPrivacyCard extends ConsumerStatefulWidget {
  const ResultsPrivacyCard({super.key});

  @override
  ConsumerState<ResultsPrivacyCard> createState() => _ResultsPrivacyCardState();
}

class _ResultsPrivacyCardState extends ConsumerState<ResultsPrivacyCard> {
  bool _saving = false;

  Future<void> _save(ResultsVisibility visibility) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(resultsRepositoryProvider).saveResultsPrivacy(visibility);
      ref.invalidate(resultsPrivacyProvider);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Something went wrong.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(resultsPrivacyProvider).value;
    return Container(
      decoration: _card(),
      padding: const EdgeInsets.all(appSpaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('WHO SEES MY RESULTS', style: appMono(fontSize: 10)),
          const SizedBox(height: appSpaceSm),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: DropdownButtonFormField<ResultsVisibility>(
                key: ValueKey(current),
                initialValue: current,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Leaderboards'),
                items: [
                  for (final value in ResultsVisibility.values)
                    DropdownMenuItem(value: value, child: Text(value.label)),
                ],
                onChanged: current == null || _saving
                    ? null
                    : (value) {
                        if (value != null && value != current) _save(value);
                      },
              ),
            ),
          ),
          const SizedBox(height: appSpaceSm),
          Text(switch (current) {
            ResultsVisibility.private =>
              'Other athletes don\'t see your results on the leaderboards '
                  'or in their feed. Your coaches still do.',
            ResultsVisibility.followers =>
              'Everyone in your gym sees your results on the leaderboards. '
                  'People you accept as followers see all of them in their '
                  'feed, your logbook too.',
            _ =>
              'Everyone in your gym sees your results on the leaderboards. '
                  'Followers only see results from gyms you share.',
          }, style: const TextStyle(color: appSubtleText, fontSize: 12)),
        ],
      ),
    );
  }
}

BoxDecoration _card() => BoxDecoration(
  color: appSurface,
  borderRadius: BorderRadius.circular(appRadiusLg),
  border: Border.all(color: appBorder),
);

class _ResultsCard extends StatelessWidget {
  const _ResultsCard({
    required this.results,
    required this.emptyText,
    this.onEditPersonal,
  });

  final List<WorkoutResult> results;
  final String emptyText;

  /// Opens a personal result for editing; gym results are edited on the WOD.
  final ValueChanged<WorkoutResult>? onEditPersonal;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return Container(
      decoration: _card(),
      padding: const EdgeInsets.all(appSpaceLg),
      child: results.isEmpty
          ? Text(emptyText, style: const TextStyle(color: appSubtleText))
          : Column(
              children: [
                for (final result in results)
                  InkWell(
                    key: ValueKey('my-result-${result.id}'),
                    onTap: result.isPersonal && onEditPersonal != null
                        ? () => onEditPersonal!(result)
                        : null,
                    borderRadius: BorderRadius.circular(appRadiusMd),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: appSpaceSm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 110,
                            child: Text(
                              localizations.formatMediumDate(
                                result.performedOn,
                              ),
                              style: const TextStyle(
                                color: appSubtleText,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  result.sectionTitle.isEmpty
                                      ? 'Workout'
                                      : result.sectionTitle,
                                  style: const TextStyle(color: appText),
                                ),
                                if (result.notes.isNotEmpty)
                                  Text(
                                    result.notes,
                                    style: const TextStyle(
                                      color: appSubtleText,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (result.isPersonal) ...[
                            const AppPill(label: 'Personal', dense: true),
                            const SizedBox(width: appSpaceSm),
                          ],
                          if (result.isPr) ...[
                            const AppPill(
                              label: 'PR',
                              intent: AppPillIntent.warning,
                              dense: true,
                            ),
                            const SizedBox(width: appSpaceSm),
                          ],
                          Text(
                            result.scoreLabel,
                            style: const TextStyle(
                              color: appText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: Text(
                              result.divisionLabel,
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                color: appMutedText,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Best kg per rep count, the estimated 1RM, and 50–100 % of it.
class PercentageChart extends StatelessWidget {
  const PercentageChart({super.key, required this.bestSets});

  final List<BestSet> bestSets;

  @override
  Widget build(BuildContext context) {
    final oneRepMax = estimatedOneRepMax(bestSets);
    if (oneRepMax == null) return const SizedBox.shrink();
    final style = const TextStyle(color: appText, fontSize: 13);
    final muted = const TextStyle(color: appSubtleText, fontSize: 12);
    return Container(
      decoration: _card(),
      padding: const EdgeInsets.all(appSpaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PERCENTAGES', style: appMono(fontSize: 10)),
          const SizedBox(height: appSpaceSm),
          Text(
            'Estimated 1RM ${_number(oneRepMax)} kg',
            style: style.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: appSpaceSm),
          Wrap(
            spacing: appSpaceLg,
            runSpacing: appSpaceSm,
            children: [
              for (final set in bestSets)
                Text('${set.reps}RM ${_number(set.kg)} kg', style: muted),
            ],
          ),
          const SizedBox(height: appSpaceMd),
          Wrap(
            spacing: appSpaceLg,
            runSpacing: appSpaceSm,
            children: [
              for (var percent = 100; percent >= 50; percent -= 5)
                Text(
                  '$percent %  ${_number((oneRepMax * percent / 100 * 2).round() / 2)} kg',
                  style: style,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
