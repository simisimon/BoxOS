import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_form_dialog.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/memberships/data/membership_repository.dart';
import 'package:app/features/memberships/domain/membership_models.dart';
import 'package:app/features/memberships/presentation/plan_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Box configuration → Memberships: the plans the box offers, the currency,
/// and whether bookings require an active plan. Every change is saved right
/// away.
class MembershipPlansPanel extends ConsumerStatefulWidget {
  const MembershipPlansPanel({super.key});

  @override
  ConsumerState<MembershipPlansPanel> createState() =>
      _MembershipPlansPanelState();
}

class _MembershipPlansPanelState extends ConsumerState<MembershipPlansPanel> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  MembershipSettings? _settings;
  List<MembershipPlan> _plans = const [];
  bool _showArchived = false;

  MembershipRepository get _repository =>
      ref.read(membershipRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        _repository.fetchSettings(),
        _repository.fetchPlans(includeArchived: true),
      ]);
      if (!mounted) return;
      setState(() {
        _settings = results[0] as MembershipSettings;
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
    } finally {
      if (mounted) setState(() => _loading = false);
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
    setState(() {
      final exists = _plans.any((item) => item.id == plan.id);
      _plans = exists
          ? [for (final item in _plans) item.id == plan.id ? plan : item]
          : [..._plans, plan];
    });
  }

  Future<void> _createPlan() async {
    final draft = await showPlanEditorDialog(
      context,
      currency: _settings?.currency ?? 'EUR',
    );
    if (draft == null) return;
    await _run(
      () async => _replacePlan(await _repository.createPlan(draft)),
      done: 'Created ${draft.name}.',
      failed: 'Could not create the plan',
    );
  }

  Future<void> _editPlan(MembershipPlan plan) async {
    final draft = await showPlanEditorDialog(
      context,
      plan: plan,
      currency: _settings?.currency ?? 'EUR',
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

  Future<void> _updateSettings({
    String? currency,
    bool? requirePlanForBooking,
  }) async {
    await _run(
      () async {
        final settings = await _repository.updateSettings(
          currency: currency,
          requirePlanForBooking: requirePlanForBooking,
        );
        if (mounted) setState(() => _settings = settings);
        // Prices are shown in the box currency.
        if (currency != null) await _load();
      },
      done: 'Membership settings saved.',
      failed: 'Could not save membership settings',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _settings == null) {
      return const AppCard(child: AppLoadingState());
    }
    if (_error != null && _settings == null) {
      return AppCard(
        child: AppEmptyState.error(
          title: 'Could not load membership plans',
          subtitle: _error,
          actionLabel: 'Retry',
          onAction: _load,
          compact: true,
        ),
      );
    }
    final settings = _settings!;
    final active = [
      for (final plan in _plans)
        if (!plan.isArchived) plan,
    ];
    final archived = [
      for (final plan in _plans)
        if (plan.isArchived) plan,
    ];
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MEMBERSHIPS',
                          style: appMono(
                            fontSize: 10,
                            letterSpacing: 1.5,
                            color: appPrimary,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Membership plans',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AppPrimaryButton(
                    label: 'New plan',
                    icon: Icons.add_rounded,
                    onPressed: _busy ? null : _createPlan,
                    size: AppButtonSize.md,
                    expand: false,
                  ),
                ],
              ),
              const SizedBox(height: appSpaceSm),
              Text(
                'Athletes see these plans and request one; you approve the '
                'request under Members → Requests, or assign a plan from a '
                'member\'s detail.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: appSubtleText,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: appSpaceLg),
              if (active.isEmpty)
                AppEmptyState(
                  icon: Icons.workspace_premium_outlined,
                  title: 'No plans yet',
                  subtitle:
                      'Create your first plan, e.g. Unlimited, 2x per week '
                      'or a 10-class card.',
                  actionLabel: 'New plan',
                  onAction: _busy ? null : _createPlan,
                  compact: true,
                )
              else
                for (final plan in active) ...[
                  _PlanTile(
                    plan: plan,
                    enabled: !_busy,
                    onEdit: () => _editPlan(plan),
                    onArchive: () => _setArchived(plan, true),
                  ),
                  const SizedBox(height: appSpaceSm),
                ],
              if (archived.isNotEmpty) ...[
                const SizedBox(height: appSpaceSm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        setState(() => _showArchived = !_showArchived),
                    icon: Icon(
                      _showArchived
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                    ),
                    label: Text('Archived plans (${archived.length})'),
                  ),
                ),
                if (_showArchived)
                  for (final plan in archived) ...[
                    _PlanTile(
                      plan: plan,
                      enabled: !_busy,
                      onEdit: () => _editPlan(plan),
                      onRestore: () => _setArchived(plan, false),
                    ),
                    const SizedBox(height: appSpaceSm),
                  ],
              ],
            ],
          ),
        ),
        const SizedBox(height: appSpaceLg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'BOOKING & BILLING',
                style: appMono(fontSize: 10, letterSpacing: 1.4),
              ),
              const SizedBox(height: appSpaceLg),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Block booking without an active plan',
                          style: TextStyle(
                            color: appText,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'When on, athletes can only book classes their plan '
                          'covers: dates, class types, weekly limits and '
                          'punch-card classes. Owners and trainers are never '
                          'blocked.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: appSubtleText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: appSpaceMd),
                  Switch(
                    value: settings.requirePlanForBooking,
                    onChanged: _busy
                        ? null
                        : (value) =>
                              _updateSettings(requirePlanForBooking: value),
                  ),
                ],
              ),
              const Divider(height: appSpace2xl),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Currency',
                          style: TextStyle(
                            color: appText,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Used for every plan price. Payments are tracked by '
                          'hand on the Members tab for now.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: appSubtleText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: appSpaceMd),
                  DropdownButton<String>(
                    value: settings.currency,
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null && value != settings.currency) {
                              _updateSettings(currency: value);
                            }
                          },
                    items: [
                      for (final currency in settings.currencies)
                        DropdownMenuItem(value: currency, child: Text(currency)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.enabled,
    required this.onEdit,
    this.onArchive,
    this.onRestore,
  });

  final MembershipPlan plan;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = [
      plan.limitLabel,
      classTypesLabel(plan.allowedClassTypes),
      '${plan.activeMemberCount} '
          '${plan.activeMemberCount == 1 ? 'member' : 'members'}',
    ].join(' · ');
    return AppCard.inset(
      onTap: enabled ? onEdit : null,
      child: Row(
        children: [
          AppAccentBadge(
            icon: switch (plan.type) {
              PlanType.unlimited => Icons.all_inclusive_rounded,
              PlanType.weekly => Icons.date_range_rounded,
              PlanType.punchCard => Icons.confirmation_number_outlined,
            },
            color: plan.isArchived ? appSubtleText : appPrimary,
            size: 38,
          ),
          const SizedBox(width: appSpaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        plan.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: appText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (plan.isArchived) ...[
                      const SizedBox(width: appSpaceSm),
                      const AppPill(label: 'Archived', dense: true),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  details,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: appSubtleText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: appSpaceSm),
          Text(
            plan.priceLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              color: appText,
              fontWeight: FontWeight.w800,
            ),
          ),
          PopupMenuButton<String>(
            enabled: enabled,
            tooltip: 'Plan actions',
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  onEdit();
                case 'archive':
                  onArchive?.call();
                case 'restore':
                  onRestore?.call();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              if (onArchive != null)
                const PopupMenuItem(value: 'archive', child: Text('Archive')),
              if (onRestore != null)
                const PopupMenuItem(value: 'restore', child: Text('Restore')),
            ],
          ),
        ],
      ),
    );
  }
}
