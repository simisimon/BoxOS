import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/results/data/api_results_repository.dart';
import 'package:app/features/results/domain/workout_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _number(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

/// Profile › Results: the athlete's results, newest first, filtered to one
/// movement or named workout; a lift also shows its percentage chart.
class MyResultsSection extends ConsumerStatefulWidget {
  const MyResultsSection({super.key});

  @override
  ConsumerState<MyResultsSection> createState() => _MyResultsSectionState();
}

class _MyResultsSectionState extends ConsumerState<MyResultsSection> {
  ResultFilter? _filter;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(myResultsProvider(null));
    final shown = ref.watch(myResultsProvider(_filter));
    final filters = all.value?.filters ?? const <ResultFilter>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
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
              _ResultsCard(results: data.results),
            ],
          ),
        ),
      ],
    );
  }
}

BoxDecoration _card() => BoxDecoration(
  color: appSurface,
  borderRadius: BorderRadius.circular(appRadiusLg),
  border: Border.all(color: appBorder),
);

class _ResultsCard extends StatelessWidget {
  const _ResultsCard({required this.results});

  final List<WorkoutResult> results;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return Container(
      decoration: _card(),
      padding: const EdgeInsets.all(appSpaceLg),
      child: results.isEmpty
          ? const Text(
              'No results yet. Log one from the WOD of the day on Home.',
              style: TextStyle(color: appSubtleText),
            )
          : Column(
              children: [
                for (final result in results)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: appSpaceSm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 110,
                          child: Text(
                            localizations.formatMediumDate(result.performedOn),
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
