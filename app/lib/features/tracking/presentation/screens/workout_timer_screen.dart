import 'dart:async';

import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/features/tracking/data/repositories/api_tracking_repository.dart';
import 'package:app/features/tracking/domain/models/trackable_workout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkoutTimerScreen extends ConsumerStatefulWidget {
  const WorkoutTimerScreen({super.key, required this.workout});

  final TrackableWorkout workout;

  @override
  ConsumerState<WorkoutTimerScreen> createState() => _WorkoutTimerScreenState();
}

class _WorkoutTimerScreenState extends ConsumerState<WorkoutTimerScreen> {
  static const _tickInterval = Duration(milliseconds: 100);

  late TimerMode _mode;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  int _capMinutes = 12;
  int _intervalSeconds = 60;
  int _lastEmomInterval = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.workout.suggestedMode;
    _capMinutes = widget.workout.suggestedMinutes ?? _defaultCapForMode(_mode);
    _intervalSeconds = widget.workout.suggestedIntervalSeconds ?? 60;
  }

  int _defaultCapForMode(TimerMode mode) {
    switch (mode) {
      case TimerMode.stopwatch:
        return 0;
      case TimerMode.amrap:
        return 12;
      case TimerMode.emom:
        return 10;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  bool get _running => _stopwatch.isRunning;

  Duration get _capDuration => Duration(minutes: _capMinutes);

  void _start() {
    if (_finished) return;
    _stopwatch.start();
    _ticker?.cancel();
    _ticker = Timer.periodic(_tickInterval, (_) => _onTick());
    setState(() {});
  }

  void _pause() {
    _stopwatch.stop();
    _ticker?.cancel();
    setState(() {});
  }

  void _reset() {
    _ticker?.cancel();
    _stopwatch.stop();
    _stopwatch.reset();
    setState(() {
      _elapsed = Duration.zero;
      _lastEmomInterval = 0;
      _finished = false;
    });
  }

  void _onTick() {
    final elapsed = _stopwatch.elapsed;

    if (_mode == TimerMode.emom) {
      final intervalIndex = elapsed.inSeconds ~/ _intervalSeconds;
      if (intervalIndex > _lastEmomInterval &&
          intervalIndex < (_capMinutes * 60) ~/ _intervalSeconds) {
        _lastEmomInterval = intervalIndex;
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.alert);
      }
    }

    final shouldFinish =
        _mode != TimerMode.stopwatch && elapsed >= _capDuration;
    if (shouldFinish) {
      _stopwatch.stop();
      _ticker?.cancel();
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
      if (mounted) {
        setState(() {
          _elapsed = _capDuration;
          _finished = true;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _elapsed = elapsed);
    }
  }

  void _onModeChanged(TimerMode mode) {
    if (mode == _mode) return;
    _reset();
    setState(() {
      _mode = mode;
      if (widget.workout.suggestedMode == mode &&
          widget.workout.suggestedMinutes != null) {
        _capMinutes = widget.workout.suggestedMinutes!;
      } else {
        _capMinutes = _defaultCapForMode(mode);
      }
    });
  }

  Duration get _displayDuration {
    switch (_mode) {
      case TimerMode.stopwatch:
        return _elapsed;
      case TimerMode.amrap:
      case TimerMode.emom:
        final remaining = _capDuration - _elapsed;
        return remaining.isNegative ? Duration.zero : remaining;
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _saveResult() async {
    if (_running) {
      _pause();
    }
    final defaultScoreType = widget.workout.suggestedScoreType;
    final defaultValue = defaultScoreType == TrackingScoreType.time
        ? _formatDuration(_elapsed)
        : '';
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SaveResultDialog(
        workout: widget.workout,
        defaultScoreType: defaultScoreType,
        defaultValue: defaultValue,
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Result saved.')),
      );
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appPageBackground,
      appBar: AppBar(
        backgroundColor: appPageBackground,
        foregroundColor: appText,
        elevation: 0,
        title: const Text(
          'Tracking',
          style: TextStyle(color: appText, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WorkoutSummaryCard(workout: widget.workout),
              const SizedBox(height: 20),
              _ModeSelector(mode: _mode, onChanged: _onModeChanged),
              const SizedBox(height: 16),
              if (_mode != TimerMode.stopwatch)
                _CapConfig(
                  mode: _mode,
                  capMinutes: _capMinutes,
                  intervalSeconds: _intervalSeconds,
                  enabled: !_running && _elapsed == Duration.zero,
                  onCapChanged: (value) =>
                      setState(() => _capMinutes = value),
                  onIntervalChanged: (value) =>
                      setState(() => _intervalSeconds = value),
                ),
              const SizedBox(height: 24),
              _TimerDisplay(
                label: _modeLabel(),
                value: _formatDuration(_displayDuration),
                meta: _modeMeta(),
                finished: _finished,
              ),
              const SizedBox(height: 24),
              _TimerControls(
                running: _running,
                hasElapsed: _elapsed > Duration.zero,
                finished: _finished,
                onStart: _start,
                onPause: _pause,
                onReset: _reset,
              ),
              if (_elapsed > Duration.zero || _finished) ...[
                const SizedBox(height: 12),
                _SaveResultButton(onTap: _saveResult),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _modeLabel() {
    switch (_mode) {
      case TimerMode.stopwatch:
        return _finished ? 'FINISHED' : 'ELAPSED';
      case TimerMode.amrap:
        return _finished ? 'TIME' : 'REMAINING';
      case TimerMode.emom:
        return _finished ? 'COMPLETE' : 'REMAINING';
    }
  }

  String? _modeMeta() {
    switch (_mode) {
      case TimerMode.stopwatch:
        return null;
      case TimerMode.amrap:
        return 'AMRAP $_capMinutes min';
      case TimerMode.emom:
        final totalIntervals =
            (_capMinutes * 60) ~/ _intervalSeconds;
        final currentInterval = _elapsed.inSeconds ~/ _intervalSeconds + 1;
        final shown = currentInterval > totalIntervals
            ? totalIntervals
            : currentInterval;
        return 'Round $shown / $totalIntervals';
    }
  }
}

class _WorkoutSummaryCard extends StatelessWidget {
  const _WorkoutSummaryCard({required this.workout});

  final TrackableWorkout workout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(appRadiusLg),
        border: Border.all(color: appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAccentBadge(
                icon: Icons.fitness_center_outlined,
                color: workout.accent,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workout.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (workout.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        workout.subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: appSubtleText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (workout.movements.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(color: appBorder, height: 1),
            const SizedBox(height: 14),
            for (var i = 0; i < workout.movements.length; i++) ...[
              _MovementRow(movement: workout.movements[i]),
              if (i != workout.movements.length - 1)
                const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.movement});

  final TrackableMovement movement;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 8, right: 12),
          decoration: const BoxDecoration(
            color: appSubtleText,
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                movement.name,
                style: const TextStyle(
                  color: appText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (movement.detail != null && movement.detail!.isNotEmpty)
                Text(
                  movement.detail!,
                  style: const TextStyle(
                    color: appSubtleText,
                    height: 1.35,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});

  final TimerMode mode;
  final ValueChanged<TimerMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: appSurfaceAlt,
        borderRadius: BorderRadius.circular(appRadiusMd),
        border: Border.all(color: appBorder),
      ),
      child: Row(
        children: [
          for (final m in TimerMode.values)
            Expanded(
              child: _ModeChip(
                label: timerModeLabel(m),
                selected: m == mode,
                onTap: () => onChanged(m),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(appRadiusSm),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? appPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(appRadiusSm),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : appMutedText,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _CapConfig extends StatelessWidget {
  const _CapConfig({
    required this.mode,
    required this.capMinutes,
    required this.intervalSeconds,
    required this.enabled,
    required this.onCapChanged,
    required this.onIntervalChanged,
  });

  final TimerMode mode;
  final int capMinutes;
  final int intervalSeconds;
  final bool enabled;
  final ValueChanged<int> onCapChanged;
  final ValueChanged<int> onIntervalChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _NumberStepper(
            label: mode == TimerMode.emom ? 'Total min' : 'Time cap (min)',
            value: capMinutes,
            min: 1,
            max: 60,
            step: 1,
            enabled: enabled,
            onChanged: onCapChanged,
          ),
        ),
        if (mode == TimerMode.emom) ...[
          const SizedBox(width: 12),
          Expanded(
            child: _NumberStepper(
              label: 'Interval (sec)',
              value: intervalSeconds,
              min: 10,
              max: 300,
              step: 10,
              enabled: enabled,
              onChanged: onIntervalChanged,
            ),
          ),
        ],
      ],
    );
  }
}

class _NumberStepper extends StatelessWidget {
  const _NumberStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(appRadiusMd),
        border: Border.all(color: appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: appSubtleText,
              fontSize: 11,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _StepperButton(
                icon: Icons.remove_rounded,
                enabled: enabled && value > min,
                onTap: () => onChanged((value - step).clamp(min, max)),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '$value',
                    style: const TextStyle(
                      color: appText,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              _StepperButton(
                icon: Icons.add_rounded,
                enabled: enabled && value < max,
                onTap: () => onChanged((value + step).clamp(min, max)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(appRadiusPill),
        onTap: enabled ? onTap : null,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? appSurfaceAlt : appSurface,
            shape: BoxShape.circle,
            border: Border.all(color: appBorder),
          ),
          child: Icon(
            icon,
            color: enabled ? appText : appSubtleText,
            size: 18,
          ),
        ),
      ),
    );
  }
}

class _TimerDisplay extends StatelessWidget {
  const _TimerDisplay({
    required this.label,
    required this.value,
    required this.meta,
    required this.finished,
  });

  final String label;
  final String value;
  final String? meta;
  final bool finished;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(appRadiusXl),
        border: Border.all(
          color: finished ? appPrimaryHairline : appBorder,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: appSubtleText,
              fontSize: 12,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: finished ? appPrimary : appText,
              fontSize: 72,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: -2,
              height: 1,
            ),
          ),
          if (meta != null) ...[
            const SizedBox(height: 10),
            Text(
              meta!,
              style: const TextStyle(
                color: appMutedText,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimerControls extends StatelessWidget {
  const _TimerControls({
    required this.running,
    required this.hasElapsed,
    required this.finished,
    required this.onStart,
    required this.onPause,
    required this.onReset,
  });

  final bool running;
  final bool hasElapsed;
  final bool finished;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: _PrimaryTimerButton(
            icon: running ? Icons.pause_rounded : Icons.play_arrow_rounded,
            label: running ? 'Pause' : (hasElapsed ? 'Resume' : 'Start'),
            disabled: finished,
            onTap: running ? onPause : onStart,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SecondaryTimerButton(
            icon: Icons.refresh_rounded,
            label: 'Reset',
            disabled: !hasElapsed && !finished,
            onTap: onReset,
          ),
        ),
      ],
    );
  }
}

class _PrimaryTimerButton extends StatelessWidget {
  const _PrimaryTimerButton({
    required this.icon,
    required this.label,
    required this.disabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(appRadiusLg),
        onTap: disabled ? null : onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: disabled ? appSurfaceAlt : appPrimary,
            borderRadius: BorderRadius.circular(appRadiusLg),
            border: Border.all(
              color: disabled ? appBorder : appPrimary,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: disabled ? appSubtleText : Colors.white,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: disabled ? appSubtleText : Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryTimerButton extends StatelessWidget {
  const _SecondaryTimerButton({
    required this.icon,
    required this.label,
    required this.disabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(appRadiusLg),
        onTap: disabled ? null : onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: appSurface,
            borderRadius: BorderRadius.circular(appRadiusLg),
            border: Border.all(color: appBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: disabled ? appSubtleText : appText,
                size: 22,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: disabled ? appSubtleText : appText,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaveResultButton extends StatelessWidget {
  const _SaveResultButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(appRadiusLg),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: appSurface,
            borderRadius: BorderRadius.circular(appRadiusLg),
            border: Border.all(color: appPrimaryHairline),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.bookmark_added_outlined,
                color: appPrimary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'Save result',
                style: const TextStyle(
                  color: appPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaveResultDialog extends ConsumerStatefulWidget {
  const _SaveResultDialog({
    required this.workout,
    required this.defaultScoreType,
    required this.defaultValue,
  });

  final TrackableWorkout workout;
  final TrackingScoreType defaultScoreType;
  final String defaultValue;

  @override
  ConsumerState<_SaveResultDialog> createState() => _SaveResultDialogState();
}

class _SaveResultDialogState extends ConsumerState<_SaveResultDialog> {
  late TrackingScoreType _scoreType;
  late TextEditingController _valueController;
  late TextEditingController _notesController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scoreType = widget.defaultScoreType;
    _valueController = TextEditingController(text: widget.defaultValue);
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _valueController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _valueController.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Enter a score.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(trackingRepositoryProvider).saveSession(
            source: widget.workout.source,
            sourceKey: widget.workout.sourceKey,
            workoutTitle: widget.workout.title,
            scoreType: _scoreType,
            scoreValue: value,
            notesText: _notesController.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = errorMessageFrom(error, fallback: 'Failed to save result');
      });
    }
  }

  String _valueHint() {
    switch (_scoreType) {
      case TrackingScoreType.time:
        return 'mm:ss (e.g. 4:23)';
      case TrackingScoreType.roundsReps:
        return 'rounds+reps (e.g. 5+12)';
      case TrackingScoreType.load:
        return 'kg (e.g. 82.5)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: appSurface,
      title: const Text('Save result', style: TextStyle(color: appText)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<TrackingScoreType>(
              initialValue: _scoreType,
              decoration: const InputDecoration(labelText: 'Score type'),
              items: [
                for (final type in TrackingScoreType.values)
                  DropdownMenuItem(value: type, child: Text(type.label)),
              ],
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => _scoreType = value);
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _valueController,
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: 'Score',
                hintText: _valueHint(),
              ),
              keyboardType: _scoreType == TrackingScoreType.load
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              enabled: !_saving,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(color: appDanger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
