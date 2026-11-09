import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_form_dialog.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/memberships/data/membership_repository.dart';
import 'package:app/features/memberships/domain/membership_models.dart';
import 'package:app/features/memberships/presentation/plan_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

AppPillIntent paymentPillIntent(PaymentStatus status) => switch (status) {
  PaymentStatus.paid => AppPillIntent.success,
  PaymentStatus.due => AppPillIntent.warning,
  PaymentStatus.overdue => AppPillIntent.danger,
};

/// Result of the assign / approve dialog.
class PlanAssignment {
  const PlanAssignment({
    required this.planId,
    required this.startsOn,
    this.priceCents,
  });

  final int planId;

  /// YYYY-MM-DD.
  final String startsOn;

  /// Null keeps the plan's price.
  final int? priceCents;
}

/// Pick a plan (unless [fixedPlan] is given), a start date and optionally a
/// different price. Used to assign a plan and to approve a plan request.
Future<PlanAssignment?> showPlanAssignmentDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  List<MembershipPlan> plans = const [],
  MemberPlan? fixedPlan,
  String? subtitle,
}) {
  return showDialog<PlanAssignment>(
    context: context,
    builder: (_) => _PlanAssignmentDialog(
      title: title,
      subtitle: subtitle,
      confirmLabel: confirmLabel,
      plans: plans,
      fixedPlan: fixedPlan,
    ),
  );
}

class _PlanAssignmentDialog extends StatefulWidget {
  const _PlanAssignmentDialog({
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
    required this.plans,
    required this.fixedPlan,
  });

  final String title;
  final String? subtitle;
  final String confirmLabel;
  final List<MembershipPlan> plans;
  final MemberPlan? fixedPlan;

  @override
  State<_PlanAssignmentDialog> createState() => _PlanAssignmentDialogState();
}

class _PlanAssignmentDialogState extends State<_PlanAssignmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _price = TextEditingController();
  int? _planId;
  DateTime _startsOn = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.fixedPlan != null) {
      _planId = widget.fixedPlan!.planId;
      _price.text = priceInputText(widget.fixedPlan!.priceCents);
    } else if (widget.plans.isNotEmpty) {
      _selectPlan(widget.plans.first);
    }
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  void _selectPlan(MembershipPlan plan) {
    _planId = plan.id;
    _price.text = priceInputText(plan.priceCents);
  }

  int get _listPriceCents {
    if (widget.fixedPlan != null) return widget.fixedPlan!.priceCents;
    for (final plan in widget.plans) {
      if (plan.id == _planId) return plan.priceCents;
    }
    return 0;
  }

  String get _currency =>
      widget.fixedPlan?.currency ??
      (widget.plans.isEmpty ? 'EUR' : widget.plans.first.currency);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startsOn,
      firstDate: now.subtract(const Duration(days: 31)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startsOn = picked);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final planId = _planId ?? widget.fixedPlan?.id;
    if (planId == null) return;
    final cents = parsePriceCents(_price.text)!;
    Navigator.of(context).pop(
      PlanAssignment(
        planId: planId,
        startsOn: _isoDate(_startsOn),
        priceCents: cents == _listPriceCents ? null : cents,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fixed = widget.fixedPlan;
    return AppFormDialog(
      title: widget.title,
      subtitle: widget.subtitle,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: fixed == null && widget.plans.isEmpty ? null : _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (fixed != null)
              AppCard.inset(
                child: _PlanSummaryLine(
                  name: fixed.planName,
                  details:
                      '${fixed.limitLabel} · '
                      '${classTypesLabel(fixed.allowedClassTypes)}',
                  price: fixed.priceLabel,
                ),
              )
            else if (widget.plans.isEmpty)
              Text(
                'Create a plan under Box configuration → Memberships first.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: appMutedText,
                ),
              )
            else
              RadioGroup<int>(
                groupValue: _planId,
                onChanged: (value) => setState(() {
                  for (final plan in widget.plans) {
                    if (plan.id == value) _selectPlan(plan);
                  }
                }),
                child: Column(
                  children: [
                    for (final plan in widget.plans)
                      RadioListTile<int>(
                        value: plan.id,
                        contentPadding: EdgeInsets.zero,
                        title: Text(plan.name),
                        subtitle: Text(
                          '${plan.limitLabel} · ${plan.priceLabel}',
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: appSpaceLg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Starts on',
                        suffixIcon: Icon(Icons.event_rounded),
                      ),
                      child: Text(_isoDate(_startsOn)),
                    ),
                  ),
                ),
                const SizedBox(width: appSpaceMd),
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Price for this member',
                      suffixText: _currency,
                    ),
                    validator: (value) => parsePriceCents(value ?? '') == null
                        ? 'Enter a price'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: appSpaceSm),
            Text(
              'A plan the member is on now ends the day before this one '
              'starts.',
              style: theme.textTheme.bodySmall?.copyWith(color: appSubtleText),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanSummaryLine extends StatelessWidget {
  const _PlanSummaryLine({
    required this.name,
    required this.details,
    required this.price,
  });

  final String name;
  final String details;
  final String price;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: appText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                details,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: appSubtleText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: appSpaceSm),
        Text(
          price,
          style: theme.textTheme.titleSmall?.copyWith(
            color: appText,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// Approve a plan request: confirm start date and price, then PATCH.
/// Returns true when the request was handled.
Future<bool> reviewPlanRequest(
  BuildContext context,
  WidgetRef ref,
  MemberPlan request, {
  required bool approve,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final repository = ref.read(membershipRepositoryProvider);
  PlanAssignment? assignment;
  if (approve) {
    assignment = await showPlanAssignmentDialog(
      context,
      title: 'Approve plan request',
      subtitle: request.memberName == null
          ? null
          : '${request.memberName} asked for ${request.planName}.',
      confirmLabel: 'Approve',
      fixedPlan: request,
    );
    if (assignment == null) return false;
  } else {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Decline plan request?',
      message:
          '${request.memberName ?? 'The member'} asked for '
          '${request.planName}. They get a notification and can request '
          'another plan.',
      confirmLabel: 'Decline',
      destructive: true,
    );
    if (!confirmed) return false;
  }
  try {
    await repository.reviewPlanRequest(
      requestId: request.id,
      approve: approve,
      startsOn: assignment?.startsOn,
      priceCents: assignment?.priceCents,
    );
    ref.invalidate(pendingPlanRequestsProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          approve
              ? 'Approved ${request.planName}.'
              : 'Declined ${request.planName}.',
        ),
      ),
    );
    return true;
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(errorMessageFrom(error, fallback: 'Review failed')),
      ),
    );
    return false;
  }
}

/// Plan request card for Members → Requests.
class PlanRequestCard extends StatelessWidget {
  const PlanRequestCard({
    super.key,
    required this.request,
    required this.isPending,
    required this.onApprove,
    required this.onReject,
  });

  final MemberPlan request;
  final bool isPending;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = request.currentPlanName;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppAccentBadge(
                icon: Icons.workspace_premium_outlined,
                color: appWarning,
              ),
              const SizedBox(width: appSpaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.memberName ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      current == null
                          ? 'Requests a plan'
                          : 'Requests a change from $current',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: appSubtleText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: appSpaceMd),
          AppCard.inset(
            child: _PlanSummaryLine(
              name: request.planName,
              details: request.limitLabel,
              price: request.priceLabel,
            ),
          ),
          const SizedBox(height: appSpaceLg),
          Row(
            children: [
              Expanded(
                child: AppSecondaryButton(
                  label: 'Decline',
                  onPressed: isPending ? null : onReject,
                  size: AppButtonSize.md,
                  busy: isPending,
                ),
              ),
              const SizedBox(width: appSpaceSm),
              Expanded(
                child: AppPrimaryButton(
                  label: 'Approve',
                  onPressed: isPending ? null : onApprove,
                  size: AppButtonSize.md,
                  busy: isPending,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Member detail (owner): the member's plan, payment state, open request and
/// past plans, with assign / end actions.
class MemberPlanSection extends ConsumerStatefulWidget {
  const MemberPlanSection({
    super.key,
    required this.userId,
    required this.memberName,
    this.onChanged,
  });

  final int userId;
  final String memberName;

  /// Called after any change so the roster can refresh its plan pills.
  final VoidCallback? onChanged;

  @override
  ConsumerState<MemberPlanSection> createState() => _MemberPlanSectionState();
}

class _MemberPlanSectionState extends ConsumerState<MemberPlanSection> {
  List<MemberPlan>? _plans;
  String? _error;
  bool _busy = false;
  bool _showHistory = false;

  MembershipRepository get _repository =>
      ref.read(membershipRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MemberPlanSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _plans = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final plans = await _repository.fetchMemberPlans(widget.userId);
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () =>
            _error = errorMessageFrom(error, fallback: 'Could not load plans'),
      );
    }
  }

  Future<void> _act(Future<void> Function() action, String failed) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
      widget.onChanged?.call();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessageFrom(error, fallback: failed))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assign() async {
    List<MembershipPlan> plans;
    try {
      plans = await _repository.fetchPlans();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Could not load plans'),
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    final assignment = await showPlanAssignmentDialog(
      context,
      title: 'Assign plan',
      subtitle: 'Give ${widget.memberName} a plan.',
      confirmLabel: 'Assign plan',
      plans: plans,
    );
    if (assignment == null) return;
    await _act(
      () => _repository.assignPlan(
        userId: widget.userId,
        planId: assignment.planId,
        startsOn: assignment.startsOn,
        priceCents: assignment.priceCents,
      ),
      'Could not assign the plan',
    );
  }

  Future<void> _end(MemberPlan plan) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'End ${plan.planName}?',
      message:
          '${widget.memberName} keeps bookings already made, but the plan no '
          'longer covers new ones from today.',
      confirmLabel: 'End plan',
      destructive: true,
    );
    if (!confirmed) return;
    await _act(
      () => _repository.endMemberPlan(plan.id),
      'Could not end the plan',
    );
  }

  Future<void> _review(MemberPlan request, bool approve) async {
    setState(() => _busy = true);
    final handled = await reviewPlanRequest(
      context,
      ref,
      request,
      approve: approve,
    );
    if (handled) {
      await _load();
      widget.onChanged?.call();
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plans = _plans;
    Widget body;
    if (plans == null) {
      body = _error == null
          ? const AppLoadingState(height: 80)
          : Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(color: appDanger),
            );
    } else {
      final active = [
        for (final plan in plans)
          if (plan.isActive) plan,
      ];
      final requests = [
        for (final plan in plans)
          if (plan.state == MemberPlanState.requested) plan,
      ];
      final history = [
        for (final plan in plans)
          if (!plan.isActive && plan.state != MemberPlanState.requested) plan,
      ];
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (active.isEmpty && requests.isEmpty)
            Text(
              'No plan yet.',
              style: theme.textTheme.bodyMedium?.copyWith(color: appMutedText),
            ),
          for (final plan in active) ...[
            _ActivePlanTile(
              plan: plan,
              enabled: !_busy,
              onPaymentChanged: (status) => _act(
                () => _repository.updatePaymentStatus(plan.id, status),
                'Could not update payment',
              ),
              onEnd: () => _end(plan),
            ),
            const SizedBox(height: appSpaceSm),
          ],
          for (final request in requests) ...[
            AppCard.inset(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const AppPill(
                        label: 'Requested',
                        intent: AppPillIntent.warning,
                        dense: true,
                      ),
                      const SizedBox(width: appSpaceSm),
                      Expanded(
                        child: Text(
                          '${request.planName} · ${request.priceLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: appText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: appSpaceSm),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: appSpaceSm,
                    children: [
                      TextButton(
                        onPressed: _busy ? null : () => _review(request, false),
                        child: const Text('Decline'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 40),
                        ),
                        onPressed: _busy ? null : () => _review(request, true),
                        child: const Text('Approve'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: appSpaceSm),
          ],
          if (history.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _showHistory = !_showHistory),
                icon: Icon(
                  _showHistory
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                ),
                label: Text('Past plans (${history.length})'),
              ),
            ),
            if (_showHistory)
              for (final plan in history)
                Padding(
                  padding: const EdgeInsets.only(bottom: appSpaceXs),
                  child: Text(
                    [
                      plan.planName,
                      plan.state.label,
                      ?plan.periodLabel,
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: appSubtleText,
                    ),
                  ),
                ),
          ],
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(appSpaceLg, 0, appSpaceLg, appSpaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'MEMBERSHIP PLAN',
                  style: appMono(fontSize: 10, letterSpacing: 1.4),
                ),
              ),
              TextButton.icon(
                onPressed: _busy || plans == null ? null : _assign,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Assign plan'),
              ),
            ],
          ),
          const SizedBox(height: appSpaceXs),
          body,
          const Divider(height: appSpaceXl),
        ],
      ),
    );
  }
}

class _ActivePlanTile extends StatelessWidget {
  const _ActivePlanTile({
    required this.plan,
    required this.enabled,
    required this.onPaymentChanged,
    required this.onEnd,
  });

  final MemberPlan plan;
  final bool enabled;
  final ValueChanged<PaymentStatus> onPaymentChanged;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = [
      plan.priceLabel,
      plan.limitLabel,
      ?plan.periodLabel,
      ?plan.usageLabel,
    ].join(' · ');
    return AppCard.inset(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.planName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: appText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (plan.state == MemberPlanState.upcoming) ...[
                const AppPill(
                  label: 'Upcoming',
                  intent: AppPillIntent.primary,
                  dense: true,
                ),
                const SizedBox(width: appSpaceXs),
              ],
              PopupMenuButton<PaymentStatus>(
                enabled: enabled,
                tooltip: 'Payment status',
                onSelected: onPaymentChanged,
                itemBuilder: (_) => [
                  for (final status in PaymentStatus.values)
                    PopupMenuItem(value: status, child: Text(status.label)),
                ],
                child: AppPill(
                  label: plan.paymentStatus.label,
                  icon: Icons.expand_more_rounded,
                  intent: paymentPillIntent(plan.paymentStatus),
                  dense: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            details,
            style: theme.textTheme.bodySmall?.copyWith(color: appSubtleText),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: enabled ? onEnd : null,
              style: TextButton.styleFrom(foregroundColor: appDanger),
              child: const Text('End plan'),
            ),
          ),
        ],
      ),
    );
  }
}
