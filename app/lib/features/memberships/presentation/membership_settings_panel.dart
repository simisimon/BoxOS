import 'package:app/core/errors/error_message.dart';
import 'package:app/core/platform/open_external_url.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/memberships/data/membership_repository.dart';
import 'package:app/features/memberships/domain/membership_models.dart';
import 'package:app/features/memberships/presentation/extra_tokens_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Box settings → Memberships: the currency, whether bookings require an
/// active plan, extra tokens, and the box's Stripe account. The plans
/// themselves live on the Memberships page. Every change is saved right away.
class MembershipSettingsPanel extends ConsumerStatefulWidget {
  const MembershipSettingsPanel({super.key});

  @override
  ConsumerState<MembershipSettingsPanel> createState() =>
      _MembershipSettingsPanelState();
}

class _MembershipSettingsPanelState
    extends ConsumerState<MembershipSettingsPanel> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  MembershipSettings? _settings;
  StripeConnectState _stripe = StripeConnectState.unavailable;

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
      final settings = await _repository.fetchSettings();
      if (!mounted) return;
      setState(() => _settings = settings);
      await _loadStripe();
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = errorMessageFrom(
          error,
          fallback: 'Could not load membership settings',
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Payments are optional: when the status cannot be read the card stays
  /// hidden instead of failing the panel.
  Future<void> _loadStripe() async {
    try {
      final state = await _repository.fetchStripeState();
      if (mounted) setState(() => _stripe = state);
    } catch (_) {
      if (mounted) setState(() => _stripe = StripeConnectState.unavailable);
    }
  }

  Future<void> _connectStripe() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final url = await _repository.createStripeOnboardingLink();
      final opened = await openExternalUrl(url);
      if (!opened) {
        await Clipboard.setData(ClipboardData(text: url));
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Stripe link copied. Open it in your browser to continue.',
            ),
          ),
        );
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Could not open Stripe'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
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

  Future<void> _updateSettings({
    String? currency,
    bool? requirePlanForBooking,
    int? extraTokenPriceCents,
    bool stopSellingExtraTokens = false,
  }) async {
    await _run(
      () async {
        final settings = await _repository.updateSettings(
          currency: currency,
          requirePlanForBooking: requirePlanForBooking,
          extraTokenPriceCents: extraTokenPriceCents,
          stopSellingExtraTokens: stopSellingExtraTokens,
        );
        if (mounted) setState(() => _settings = settings);
        // Prices are shown in the box currency.
        if (currency != null) await _load();
      },
      done: 'Membership settings saved.',
      failed: 'Could not save membership settings',
    );
  }

  Future<void> _editExtraTokenPrice(MembershipSettings settings) async {
    final choice = await showExtraTokenPriceDialog(
      context,
      currentPriceCents: settings.extraTokenPriceCents,
      currency: settings.currency,
    );
    if (choice == null) return;
    final price = choice.priceCents;
    await _updateSettings(
      extraTokenPriceCents: price,
      stopSellingExtraTokens: price == null,
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
          title: 'Could not load membership settings',
          subtitle: _error,
          actionLabel: 'Retry',
          onAction: _load,
          compact: true,
        ),
      );
    }
    final settings = _settings!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                          'When on, each booking spends one of the athlete\'s '
                          'tokens, on the class types and dates their plan '
                          'covers. Owners and trainers are never blocked.',
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
                        DropdownMenuItem(
                          value: currency,
                          child: Text(currency),
                        ),
                    ],
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
                          'Extra tokens',
                          style: TextStyle(
                            color: appText,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          settings.extraTokenPriceCents == null
                              ? 'Not offered. Set a price to sell single '
                                    'tokens on top of a plan, valid for one '
                                    'month.'
                              : '${formatPrice(settings.extraTokenPriceCents!, settings.currency)} '
                                    'per token, valid for one month. Used '
                                    'when a member\'s plan cannot cover a '
                                    'class.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: appSubtleText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: appSpaceMd),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _editExtraTokenPrice(settings),
                    child: Text(
                      settings.extraTokenPriceCents == null
                          ? 'Set price'
                          : 'Change',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_stripe != StripeConnectState.unavailable) ...[
          const SizedBox(height: appSpaceLg),
          _StripeCard(state: _stripe, busy: _busy, onConnect: _connectStripe),
        ],
      ],
    );
  }
}

/// Settings → Memberships: connect the box's own Stripe account.
class _StripeCard extends StatelessWidget {
  const _StripeCard({
    required this.state,
    required this.busy,
    required this.onConnect,
  });

  final StripeConnectState state;
  final bool busy;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (pill, intent, text, action) = switch (state) {
      StripeConnectState.ready => (
        'Ready',
        AppPillIntent.success,
        'Your box can take payments. In Stripe, turn on customer emails for '
            'invoices and successful payments so members get their invoices.',
        null,
      ),
      StripeConnectState.onboarding => (
        'Setup incomplete',
        AppPillIntent.warning,
        'Stripe still needs a few details (business, ID check, bank account) '
            'before your box can take payments.',
        'Continue Stripe setup',
      ),
      _ => (
        'Not connected',
        AppPillIntent.neutral,
        'Connect your box\'s own Stripe account to collect monthly fees and '
            'extra tokens by SEPA direct debit or card. Money goes straight '
            'to your bank account; Stripe\'s fees are deducted there.',
        'Connect Stripe',
      ),
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'PAYMENTS',
                  style: appMono(fontSize: 10, letterSpacing: 1.4),
                ),
              ),
              AppPill(label: pill, intent: intent, dense: true),
            ],
          ),
          const SizedBox(height: appSpaceMd),
          const Text(
            'Online payments with Stripe',
            style: TextStyle(
              color: appText,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: appSubtleText),
          ),
          if (action != null) ...[
            const SizedBox(height: appSpaceMd),
            Align(
              alignment: Alignment.centerLeft,
              child: AppPrimaryButton(
                label: action,
                icon: Icons.open_in_new_rounded,
                onPressed: busy ? null : onConnect,
                busy: busy,
                size: AppButtonSize.md,
                expand: false,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
