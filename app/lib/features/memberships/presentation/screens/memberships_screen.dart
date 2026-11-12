import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_form_dialog.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/calendar/domain/models/class_type.dart';
import 'package:app/features/calendar/presentation/widgets/class_type_badge.dart';
import 'package:app/features/memberships/data/membership_repository.dart';
import 'package:app/features/memberships/domain/membership_models.dart';
import 'package:app/features/memberships/presentation/plan_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Memberships page (docs/admin-ui-reference.md §9): the plans members can
/// buy, as a Plans | Archived table. Create and edit open the plan panel.
/// Booking & billing settings and Stripe stay under Settings.
class MembershipsScreen extends ConsumerStatefulWidget {
  const MembershipsScreen({super.key});

  @override
  ConsumerState<MembershipsScreen> createState() => _MembershipsScreenState();
}

class _MembershipsScreenState extends ConsumerState<MembershipsScreen> {
  List<MembershipPlan>? _plans;
  String _currency = 'EUR';
  String? _error;
  bool _busy = false;
  bool _showArchived = false;
  String _query = '';

  MembershipRepository get _repository =>
      ref.read(membershipRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait<Object>([
        _repository.fetchSettings(),
        _repository.fetchPlans(includeArchived: true),
      ]);
      if (!mounted) return;
      setState(() {
        _currency = (results[0] as MembershipSettings).currency;
        _plans = results[1] as List<MembershipPlan>;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = errorMessageFrom(
          error,
          fallback: 'Could not load membership plans',
        ),
      );
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String done,
    required String failed,
  }) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessageFrom(error, fallback: failed))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _replacePlan(MembershipPlan plan) {
    final plans = _plans ?? const [];
    setState(() {
      _plans = plans.any((item) => item.id == plan.id)
          ? [for (final item in plans) item.id == plan.id ? plan : item]
          : [...plans, plan];
    });
  }

  Future<void> _createPlan() async {
    final draft = await showPlanEditorPanel(context, currency: _currency);
    if (draft == null) return;
    await _run(
      () async => _replacePlan(await _repository.createPlan(draft)),
      done: 'Created ${draft.name}.',
      failed: 'Could not create the plan',
    );
  }

  Future<void> _editPlan(MembershipPlan plan) async {
    final draft = await showPlanEditorPanel(
      context,
      plan: plan,
      currency: _currency,
      menu: [
        plan.isArchived
            ? ('Restore plan', () => _setArchived(plan, false))
            : ('Archive plan', () => _setArchived(plan, true)),
      ],
    );
    if (draft == null) return;
    await _run(
      () async => _replacePlan(await _repository.updatePlan(plan.id, draft)),
      done: 'Saved ${draft.name}.',
      failed: 'Could not save the plan',
    );
  }

  Future<void> _setArchived(MembershipPlan plan, bool archived) async {
    if (archived) {
      final confirmed = await showAppConfirmDialog(
        context,
        title: 'Archive ${plan.name}?',
        message:
            'Athletes can no longer request this plan and open requests for '
            'it are withdrawn. Members already on it keep it until it ends.',
        confirmLabel: 'Archive plan',
      );
      if (!confirmed) return;
    }
    await _run(
      () async => _replacePlan(
        await _repository.setPlanArchived(plan.id, archived: archived),
      ),
      done: archived ? 'Archived ${plan.name}.' : 'Restored ${plan.name}.',
      failed: 'Could not update the plan',
    );
  }

  @override
  Widget build(BuildContext context) {
    final plans = _plans;
    if (plans == null) {
      return _error == null
          ? const AppLoadingState()
          : Padding(
              padding: const EdgeInsets.all(appSpaceLg),
              child: AppEmptyState.error(
                title: 'Could not load membership plans',
                subtitle: _error,
                actionLabel: 'Retry',
                onAction: _load,
              ),
            );
    }
    final active = plans.where((p) => !p.isArchived).toList();
    final archived = plans.where((p) => p.isArchived).toList();
    final query = _query.trim().toLowerCase();
    final rows = (_showArchived ? archived : active)
        .where((p) => query.isEmpty || p.name.toLowerCase().contains(query))
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(appSpaceLg, appSpaceLg, appSpaceLg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: appSpaceMd,
            runSpacing: appSpaceSm,
            children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text('Plans ${active.length}'),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Archived ${archived.length}'),
                  ),
                ],
                selected: {_showArchived},
                onSelectionChanged: (s) =>
                    setState(() => _showArchived = s.first),
              ),
              Wrap(
                spacing: appSpaceSm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    child: TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Search plan',
                        prefixIcon: Icon(Icons.search_rounded, size: 18),
                      ),
                    ),
                  ),
                  AppPrimaryButton(
                    label: 'Create plan',
                    icon: Icons.add_rounded,
                    onPressed: _busy ? null : _createPlan,
                    size: AppButtonSize.md,
                    expand: false,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: appSpaceMd),
          Expanded(
            child: AppDataTable<MembershipPlan>(
              columns: const [
                AppTableColumn('Name', flex: 3),
                AppTableColumn('Type', flex: 2, hideWhenNarrow: true),
                AppTableColumn('Price', flex: 2),
                AppTableColumn('Access', flex: 3, hideWhenNarrow: true),
                AppTableColumn('Active members', flex: 2, hideWhenNarrow: true),
              ],
              rows: rows,
              total: _showArchived ? archived.length : active.length,
              onRowTap: _busy ? null : _editPlan,
              emptyText: _showArchived
                  ? 'No archived plans.'
                  : 'No plans yet. Create your first plan, e.g. Unlimited, '
                        '12 tokens a month or a 10-token pack.',
              cells: (plan) => [
                Text(
                  plan.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: appText,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AppPill(label: plan.type.label, dense: true),
                _MutedText(plan.priceLabel),
                _AccessDots(types: plan.allowedClassTypes),
                _MutedText('${plan.activeMemberCount}'),
              ],
            ),
          ),
          const SizedBox(height: appSpaceLg),
        ],
      ),
    );
  }
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(color: appMutedText, fontSize: 13),
  );
}

/// Class types a plan grants, as colour dot + name; empty means all.
class _AccessDots extends StatelessWidget {
  const _AccessDots({required this.types});

  final List<String> types;

  @override
  Widget build(BuildContext context) {
    if (types.isEmpty) return const _MutedText('All class types');
    return Wrap(
      spacing: appSpaceSm,
      runSpacing: appSpaceXs,
      children: [
        for (final type in types)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: classTypeColor(ClassType.fromWire(type)),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: appSpaceXs),
              Text(
                type,
                style: const TextStyle(color: appMutedText, fontSize: 12.5),
              ),
            ],
          ),
      ],
    );
  }
}
