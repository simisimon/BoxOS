import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_form_dialog.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/memberships/data/membership_repository.dart';
import 'package:app/features/memberships/domain/membership_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Null when the box cannot be reached; the card then hides itself instead of
/// failing (and being retried) on Profile.
final myMembershipProvider = FutureProvider.autoDispose<MyMembership?>((
  ref,
) async {
  try {
    return await ref.read(membershipRepositoryProvider).fetchMyMembership();
  } catch (_) {
    return null;
  }
});

/// Outcome of [showPlanPickerDialog]: [plan] is null when the athlete chose
/// to go on without a plan ([skipLabel]).
class PlanChoice {
  const PlanChoice(this.plan);

  final MembershipPlan? plan;
}

/// Pick one of [plans]. Resolves to the choice, null on cancel. With
/// [skipLabel], the athlete can also go on without picking a plan.
Future<PlanChoice?> showPlanPickerDialog(
  BuildContext context, {
  required List<MembershipPlan> plans,
  required String title,
  required String confirmLabel,
  String? subtitle,
  String? skipLabel,
}) {
  return showDialog<PlanChoice>(
    context: context,
    builder: (_) => _PlanPickerDialog(
      plans: plans,
      title: title,
      subtitle: subtitle,
      confirmLabel: confirmLabel,
      skipLabel: skipLabel,
    ),
  );
}

class _PlanPickerDialog extends StatefulWidget {
  const _PlanPickerDialog({
    required this.plans,
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
    required this.skipLabel,
  });

  final List<MembershipPlan> plans;
  final String title;
  final String? subtitle;
  final String confirmLabel;
  final String? skipLabel;

  @override
  State<_PlanPickerDialog> createState() => _PlanPickerDialogState();
}

class _PlanPickerDialogState extends State<_PlanPickerDialog> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    MembershipPlan? selected;
    for (final plan in widget.plans) {
      if (plan.id == _selected) selected = plan;
    }
    return AppFormDialog(
      title: widget.title,
      subtitle: widget.subtitle,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (widget.skipLabel != null)
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(const PlanChoice(null)),
            child: Text(widget.skipLabel!),
          ),
        FilledButton(
          onPressed: selected == null
              ? null
              : () => Navigator.of(context).pop(PlanChoice(selected)),
          child: Text(widget.confirmLabel),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final plan in widget.plans) ...[
            AppCard.inset(
              onTap: () => setState(() => _selected = plan.id),
              child: Row(
                children: [
                  Icon(
                    plan.id == _selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: plan.id == _selected ? appPrimary : appSubtleText,
                    size: 20,
                  ),
                  const SizedBox(width: appSpaceMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: appText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${plan.limitLabel} · '
                          '${classTypesLabel(plan.allowedClassTypes)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: appSubtleText,
                          ),
                        ),
                        if (plan.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            plan.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: appMutedText,
                            ),
                          ),
                        ],
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
                ],
              ),
            ),
            const SizedBox(height: appSpaceSm),
          ],
          const SizedBox(height: appSpaceSm),
          Text(
            'Your box confirms the plan and the start date. Payment is '
            'arranged with the box directly.',
            style: theme.textTheme.bodySmall?.copyWith(color: appSubtleText),
          ),
        ],
      ),
    );
  }
}

/// Profile → Membership: the athlete's plan at the active box, what is left
/// of it, and requesting a (different) plan.
class MyMembershipCard extends ConsumerStatefulWidget {
  const MyMembershipCard({super.key});

  @override
  ConsumerState<MyMembershipCard> createState() => _MyMembershipCardState();
}

class _MyMembershipCardState extends ConsumerState<MyMembershipCard> {
  bool _busy = false;

  Future<void> _request(MyMembership membership) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final repository = ref.read(membershipRepositoryProvider);
      final plans = await repository.fetchPlans();
      if (!mounted) return;
      if (plans.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Your box has not set up plans yet.')),
        );
        return;
      }
      final choice = await showPlanPickerDialog(
        context,
        plans: plans,
        title: membership.current == null ? 'Request a plan' : 'Change plan',
        subtitle: membership.request == null
            ? null
            : 'This replaces your open request for '
                  '${membership.request!.planName}.',
        confirmLabel: 'Send request',
      );
      final plan = choice?.plan;
      if (plan == null || !mounted) return;
      await repository.requestPlan(plan.id);
      if (mounted) ref.invalidate(myMembershipProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('Requested ${plan.name}.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Could not send the request'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw(MemberPlan request) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Withdraw request?',
      message: 'Your request for ${request.planName} is cancelled.',
      confirmLabel: 'Withdraw',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await ref.read(membershipRepositoryProvider).withdrawPlanRequest();
      if (mounted) ref.invalidate(myMembershipProvider);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(errorMessageFrom(error, fallback: 'Withdraw failed')),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final membership = ref.watch(myMembershipProvider).value;
    // The card is an addition to Profile: stay out of the way while loading
    // or when the box cannot be reached.
    if (membership == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final current = membership.current;
    final upcoming = membership.upcoming;
    final request = membership.request;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'MEMBERSHIP',
            style: appMono(fontSize: 10, letterSpacing: 1.5, color: appPrimary),
          ),
          const SizedBox(height: 5),
          Text(
            current?.planName ?? 'No active plan',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: appSpaceXs),
          if (current != null)
            Text(
              [
                current.limitLabel,
                ?current.usageLabel,
                ?current.periodLabel,
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: appSubtleText),
            )
          else
            Text(
              membership.requirePlanForBooking
                  ? 'You need a plan to book classes at this box.'
                  : 'Request a plan to train regularly at this box.',
              style: theme.textTheme.bodySmall?.copyWith(color: appSubtleText),
            ),
          if (current != null && current.allowedClassTypes.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Includes ${classTypesLabel(current.allowedClassTypes)}',
              style: theme.textTheme.bodySmall?.copyWith(color: appSubtleText),
            ),
          ],
          if (membership.extraTokens.summaryLabel case final extra?) ...[
            const SizedBox(height: appSpaceMd),
            Row(
              children: [
                const AppPill(
                  label: 'Extra',
                  intent: AppPillIntent.primary,
                  dense: true,
                ),
                const SizedBox(width: appSpaceSm),
                Expanded(
                  child: Text(
                    extra,
                    style: theme.textTheme.bodySmall?.copyWith(color: appText),
                  ),
                ),
              ],
            ),
          ],
          if (upcoming != null) ...[
            const SizedBox(height: appSpaceMd),
            Row(
              children: [
                const AppPill(
                  label: 'Next',
                  intent: AppPillIntent.primary,
                  dense: true,
                ),
                const SizedBox(width: appSpaceSm),
                Expanded(
                  child: Text(
                    '${upcoming.planName} · ${upcoming.periodLabel ?? ''}',
                    style: theme.textTheme.bodySmall?.copyWith(color: appText),
                  ),
                ),
              ],
            ),
          ],
          if (request != null) ...[
            const SizedBox(height: appSpaceMd),
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
                    '${request.planName} · waiting for your box',
                    style: theme.textTheme.bodySmall?.copyWith(color: appText),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _withdraw(request),
                  child: const Text('Withdraw'),
                ),
              ],
            ),
          ],
          const SizedBox(height: appSpaceLg),
          Align(
            alignment: Alignment.centerLeft,
            child: AppSecondaryButton(
              label: current == null ? 'Request a plan' : 'Change plan',
              icon: Icons.workspace_premium_outlined,
              onPressed: _busy ? null : () => _request(membership),
              busy: _busy,
              size: AppButtonSize.md,
              expand: false,
            ),
          ),
        ],
      ),
    );
  }
}
