import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/repositories/programming_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Settings › Programming: the box's WOD release time. Coaches "Schedule
/// release" a WOD on the Programs board and it goes live for athletes, with
/// the "New workout posted" push, at this time. Every change is saved right
/// away; turning it off moves scheduled WODs back to draft.
class ReleaseSettingsPanel extends ConsumerStatefulWidget {
  const ReleaseSettingsPanel({super.key});

  @override
  ConsumerState<ReleaseSettingsPanel> createState() =>
      _ReleaseSettingsPanelState();
}

/// Half-hour steps, "00:00" to "23:30".
final List<String> _releaseTimes = [
  for (var minutes = 0; minutes < 24 * 60; minutes += 30)
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutes % 60).toString().padLeft(2, '0')}',
];

class _ReleaseSettingsPanelState extends ConsumerState<ReleaseSettingsPanel> {
  WodReleaseSettings? _settings;
  String? _error;
  bool _busy = false;

  ProgrammingRepository get _repository =>
      ref.read(programmingRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final settings = await _repository.fetchReleaseSettings();
      if (mounted) setState(() => _settings = settings);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = errorMessageFrom(
          error,
          fallback: 'Could not load programming settings',
        ),
      );
    }
  }

  Future<void> _save({
    required String? releaseTime,
    required bool releaseDayBefore,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final settings = await _repository.updateReleaseSettings(
        releaseTime: releaseTime,
        releaseDayBefore: releaseDayBefore,
      );
      if (!mounted) return;
      setState(() => _settings = settings);
      ref.invalidate(programmingListProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('WOD release: ${settings.summary}')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Could not save release time'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      return AppCard(
        child: _error == null
            ? const AppLoadingState()
            : AppEmptyState.error(
                title: 'Could not load programming settings',
                subtitle: _error,
                actionLabel: 'Retry',
                onAction: _load,
                compact: true,
              ),
      );
    }
    final theme = Theme.of(context);
    final time = settings.releaseTime;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('WOD RELEASE', style: appMono(fontSize: 10, letterSpacing: 1.4)),
          const SizedBox(height: appSpaceLg),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Release WODs at a set time',
                      style: TextStyle(
                        color: appText,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Coaches write WODs ahead and choose "Schedule release" '
                      'on the Programs board. Athletes see the WOD, and get '
                      'the push, at this time.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: appSubtleText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: appSpaceMd),
              Switch(
                value: settings.enabled,
                onChanged: _busy
                    ? null
                    : (on) => _save(
                        releaseTime: on ? '20:00' : null,
                        releaseDayBefore: settings.releaseDayBefore,
                      ),
              ),
            ],
          ),
          if (time != null) ...[
            const Divider(height: appSpace2xl),
            Wrap(
              spacing: appSpaceMd,
              runSpacing: appSpaceSm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Release time',
                  style: TextStyle(
                    color: appText,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                DropdownButton<String>(
                  value: _releaseTimes.contains(time) ? time : null,
                  hint: Text(time),
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value != null && value != time) {
                            _save(
                              releaseTime: value,
                              releaseDayBefore: settings.releaseDayBefore,
                            );
                          }
                        },
                  items: [
                    for (final option in _releaseTimes)
                      DropdownMenuItem(value: option, child: Text(option)),
                  ],
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Evening before')),
                    ButtonSegment(value: false, label: Text('On the day')),
                  ],
                  selected: {settings.releaseDayBefore},
                  showSelectedIcon: false,
                  onSelectionChanged: _busy
                      ? null
                      : (selection) => _save(
                          releaseTime: time,
                          releaseDayBefore: selection.first,
                        ),
                ),
              ],
            ),
            const SizedBox(height: appSpaceSm),
            Text(
              'Times are in the box timezone. Changing them moves every '
              'scheduled WOD; turning release off returns them to draft.',
              style: theme.textTheme.bodySmall?.copyWith(color: appSubtleText),
            ),
          ],
        ],
      ),
    );
  }
}
