import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_form_dialog.dart';
import 'package:app/core/presentation/app_side_panel.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/results/data/movements_admin_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Settings › Movements: the movements the box added by typing exercise
/// names in the block editor. Owners rename them, archive ones they no
/// longer program, and merge duplicates ("BS", "back sqaut") into the right
/// movement so results history and PRs see one exercise.
class MovementsSettings extends ConsumerWidget {
  const MovementsSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movements = ref.watch(gymMovementsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'The built-in CrossFit movements are always there. Movements your '
          'box added by typing a new exercise name are listed here.',
          style: TextStyle(color: appSubtleText, fontSize: 13),
        ),
        const SizedBox(height: appSpaceLg),
        AppDataTable<GymMovement>(
          shrinkWrap: true,
          emptyText: movements.isLoading
              ? 'Loading…'
              : 'Your box has not added any movements yet.',
          columns: const [
            AppTableColumn('Name', flex: 3),
            AppTableColumn('Blocks', flex: 1, hideWhenNarrow: true),
            AppTableColumn('Results', flex: 1, hideWhenNarrow: true),
            AppTableColumn('', flex: 1),
          ],
          rows: movements.value ?? const [],
          cells: (movement) => [
            Row(
              children: [
                Flexible(
                  child: Text(
                    movement.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: movement.archived ? appSubtleText : appText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (movement.archived) ...[
                  const SizedBox(width: appSpaceSm),
                  const AppPill(
                    label: 'Archived',
                    intent: AppPillIntent.neutral,
                    dense: true,
                  ),
                ],
              ],
            ),
            Text(
              '${movement.blockCount}',
              style: const TextStyle(color: appMutedText),
            ),
            Text(
              '${movement.resultCount}',
              style: const TextStyle(color: appMutedText),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: PopupMenuButton<String>(
                tooltip: 'Actions for ${movement.name}',
                color: appSurfaceElevated,
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: appMutedText,
                  size: 18,
                ),
                onSelected: (action) => switch (action) {
                  'rename' => _rename(context, movement),
                  'merge' => _merge(context, movement),
                  _ => _archive(context, ref, movement),
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
                  const PopupMenuItem(
                    value: 'merge',
                    child: Text('Merge into…'),
                  ),
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(movement.archived ? 'Unarchive' : 'Archive'),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (movements.hasError) ...[
          const SizedBox(height: appSpaceSm),
          Text(
            errorMessageFrom(
              movements.error!,
              fallback: 'Could not load your movements.',
            ),
            style: const TextStyle(color: appDanger),
          ),
        ],
      ],
    );
  }

  Future<void> _rename(BuildContext context, GymMovement movement) =>
      showAppSidePanel<void>(
        context,
        builder: (_) => _RenamePanel(movement: movement),
      );

  Future<void> _merge(BuildContext context, GymMovement movement) =>
      showAppSidePanel<void>(
        context,
        builder: (_) => _MergePanel(movement: movement),
      );

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    GymMovement movement,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(movementsAdminProvider)
          .update(movement.id, archived: !movement.archived);
      ref.invalidate(gymMovementsProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            movement.archived
                ? '${movement.name} is back in the exercise picker.'
                : '${movement.name} is archived. Its results stay.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Could not change the movement.'),
          ),
        ),
      );
    }
  }
}

class _RenamePanel extends ConsumerStatefulWidget {
  const _RenamePanel({required this.movement});

  final GymMovement movement;

  @override
  ConsumerState<_RenamePanel> createState() => _RenamePanelState();
}

class _RenamePanelState extends ConsumerState<_RenamePanel> {
  late final _name = TextEditingController(text: widget.movement.name);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(movementsAdminProvider)
          .update(widget.movement.id, name: name);
      ref.invalidate(gymMovementsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = errorMessageFrom(
            error,
            fallback: 'Could not rename the movement.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSidePanel(
      title: 'Rename movement',
      subtitle: widget.movement.name,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('movement-name'),
            controller: _name,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (_) => _save(),
          ),
          const Text(
            'WOD blocks with this movement show the new name.',
            style: TextStyle(color: appSubtleText, fontSize: 12),
          ),
          if (_error != null) ...[
            const SizedBox(height: appSpaceMd),
            Text(_error!, style: const TextStyle(color: appDanger)),
          ],
        ],
      ),
    );
  }
}

class _MergePanel extends ConsumerStatefulWidget {
  const _MergePanel({required this.movement});

  final GymMovement movement;

  @override
  ConsumerState<_MergePanel> createState() => _MergePanelState();
}

class _MergePanelState extends ConsumerState<_MergePanel> {
  final _query = TextEditingController();
  List<GymMovement> _matches = const [];
  GymMovement? _target;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    try {
      final found = await ref.read(movementsAdminProvider).search(query);
      if (!mounted || query != _query.text) return;
      setState(
        () => _matches = [
          for (final movement in found)
            if (movement.id != widget.movement.id) movement,
        ],
      );
    } catch (_) {
      // Keep the last list; the owner can type again.
    }
  }

  Future<void> _merge() async {
    final target = _target;
    if (target == null) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Merge into ${target.name}?',
      message:
          'WOD blocks and results of ${widget.movement.name} move to '
          '${target.name}, and typing "${widget.movement.name}" picks '
          '${target.name} from now on. This cannot be undone.',
      confirmLabel: 'Merge',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(movementsAdminProvider)
          .merge(widget.movement.id, intoId: target.id);
      ref.invalidate(gymMovementsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = errorMessageFrom(
            error,
            fallback: 'Could not merge the movement.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSidePanel(
      title: 'Merge movement',
      subtitle: widget.movement.name,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || _target == null ? null : _merge,
          child: const Text('Merge'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Pick the movement ${widget.movement.name} is a duplicate of.',
            style: const TextStyle(color: appMutedText),
          ),
          const SizedBox(height: appSpaceMd),
          TextField(
            key: const ValueKey('merge-search'),
            controller: _query,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Search movements',
              prefixIcon: Icon(Icons.search_rounded, size: 18),
            ),
            onChanged: _search,
          ),
          const SizedBox(height: appSpaceSm),
          RadioGroup<int>(
            groupValue: _target?.id,
            onChanged: (id) => setState(
              () => _target = _matches.firstWhere((m) => m.id == id),
            ),
            child: Column(
              children: [
                for (final movement in _matches)
                  RadioListTile<int>(
                    value: movement.id,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      movement.name,
                      style: const TextStyle(color: appText),
                    ),
                    subtitle: movement.builtIn
                        ? const Text(
                            'Built-in',
                            style: TextStyle(
                              color: appSubtleText,
                              fontSize: 12,
                            ),
                          )
                        : null,
                  ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: appSpaceMd),
            Text(_error!, style: const TextStyle(color: appDanger)),
          ],
        ],
      ),
    );
  }
}
