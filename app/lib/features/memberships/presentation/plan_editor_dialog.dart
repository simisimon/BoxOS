import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/core/presentation/app_side_panel.dart';
import 'package:app/features/memberships/domain/membership_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Create or edit a membership plan in a side panel. Resolves to the draft on
/// save, null on cancel. Saving is left to the caller. [menu] fills the
/// panel's `⋯` menu (e.g. Archive).
Future<MembershipPlanDraft?> showPlanEditorPanel(
  BuildContext context, {
  MembershipPlan? plan,
  required String currency,
  List<(String, VoidCallback)> menu = const [],
}) {
  return showAppSidePanel<MembershipPlanDraft>(
    context,
    builder: (_) =>
        _PlanEditorDialog(plan: plan, currency: currency, menu: menu),
  );
}

/// "129", "129.5", "129,50" → cents. Null when not a valid amount.
int? parsePriceCents(String text) {
  final normalized = text.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  final match = RegExp(r'^(\d{1,6})(?:\.(\d{1,2}))?$').firstMatch(normalized);
  if (match == null) return null;
  final whole = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return whole * 100 + int.parse(fraction);
}

String priceInputText(int cents) {
  final whole = cents ~/ 100;
  final rest = cents % 100;
  return rest == 0 ? '$whole' : '$whole.${rest.toString().padLeft(2, '0')}';
}

class _PlanEditorDialog extends StatefulWidget {
  const _PlanEditorDialog({
    required this.plan,
    required this.currency,
    required this.menu,
  });

  final MembershipPlan? plan;
  final String currency;
  final List<(String, VoidCallback)> menu;

  @override
  State<_PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends State<_PlanEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _tokens;
  late final TextEditingController _validity;
  late PlanType _type;
  late TokenPeriod _tokenPeriod;
  late BillingPeriod _billing;
  late Set<String> _classTypes;

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    _name = TextEditingController(text: plan?.name ?? '');
    _description = TextEditingController(text: plan?.description ?? '');
    _price = TextEditingController(
      text: plan == null ? '' : priceInputText(plan.priceCents),
    );
    _tokens = TextEditingController(text: '${plan?.tokenCount ?? 12}');
    _validity = TextEditingController(
      text: plan == null
          ? '90'
          : (plan.validityDays == null ? '' : '${plan.validityDays}'),
    );
    _type = plan?.type ?? PlanType.unlimited;
    _tokenPeriod = plan?.tokenPeriod ?? TokenPeriod.month;
    // Yearly billing is no longer offered; an older yearly plan is saved as
    // monthly from now on.
    final billing = plan?.billingPeriod ?? BillingPeriod.monthly;
    _billing = BillingPeriod.offered.contains(billing)
        ? billing
        : BillingPeriod.monthly;
    // Empty on the server means "all"; show that as every chip selected.
    _classTypes = plan == null || plan.allowedClassTypes.isEmpty
        ? planClassTypes.toSet()
        : plan.allowedClassTypes.toSet();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _tokens.dispose();
    _validity.dispose();
    super.dispose();
  }

  void _setType(PlanType type) {
    setState(() {
      _type = type;
      // Token packs are usually paid once; the others usually monthly.
      if (type == PlanType.tokenPack) {
        _billing = BillingPeriod.oneTime;
      } else if (_billing == BillingPeriod.oneTime) {
        _billing = BillingPeriod.monthly;
      }
    });
  }

  String? _wholeNumber(String? value, {required int min, required int max}) {
    final number = int.tryParse((value ?? '').trim());
    if (number == null || number < min || number > max) {
      return 'Enter a number from $min to $max';
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_classTypes.isEmpty) return;
    final validityText = _validity.text.trim();
    Navigator.of(context).pop(
      MembershipPlanDraft(
        name: _name.text.trim(),
        description: _description.text.trim(),
        type: _type,
        priceCents: parsePriceCents(_price.text)!,
        billingPeriod: _billing,
        tokenCount: _type == PlanType.unlimited
            ? null
            : int.parse(_tokens.text.trim()),
        tokenPeriod: _type == PlanType.tokens ? _tokenPeriod : null,
        validityDays: _type == PlanType.tokenPack && validityText.isNotEmpty
            ? int.parse(validityText)
            : null,
        allowedClassTypes: _classTypes.length == planClassTypes.length
            ? const []
            : [
                for (final type in planClassTypes)
                  if (_classTypes.contains(type)) type,
              ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.plan != null;
    final digitsOnly = [FilteringTextInputFormatter.digitsOnly];
    return AppSidePanel(
      title: isEdit ? widget.plan!.name : 'Create plan',
      status: widget.plan?.isArchived ?? false
          ? const AppPill(label: 'Archived', dense: true)
          : null,
      menu: widget.menu,
      subtitle: isEdit
          ? 'Changes apply to new members. Members already on this plan keep '
                'their price and limits.'
          : 'Members see this plan and can request it.',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEdit ? 'Save plan' : 'Create plan'),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Plan name',
                hintText: 'e.g. Unlimited, 12 tokens / month, 10-token pack',
                counterText: '',
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Give the plan a name' : null,
            ),
            const SizedBox(height: appSpaceMd),
            TextFormField(
              controller: _description,
              maxLength: 300,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                counterText: '',
              ),
            ),
            const SizedBox(height: appSpaceLg),
            const _FieldLabel('Plan type'),
            const SizedBox(height: appSpaceSm),
            SegmentedButton<PlanType>(
              segments: const [
                ButtonSegment(
                  value: PlanType.unlimited,
                  label: Text('Unlimited'),
                ),
                ButtonSegment(
                  value: PlanType.tokens,
                  label: Text('Tokens / period'),
                ),
                ButtonSegment(
                  value: PlanType.tokenPack,
                  label: Text('Token pack'),
                ),
              ],
              selected: {_type},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => _setType(selection.first),
            ),
            const SizedBox(height: appSpaceMd),
            if (_type == PlanType.tokens)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tokens,
                      keyboardType: TextInputType.number,
                      inputFormatters: digitsOnly,
                      decoration: const InputDecoration(labelText: 'Tokens'),
                      validator: (value) =>
                          _wholeNumber(value, min: 1, max: 400),
                    ),
                  ),
                  const SizedBox(width: appSpaceMd),
                  Expanded(
                    child: DropdownButtonFormField<TokenPeriod>(
                      isExpanded: true,
                      initialValue: _tokenPeriod,
                      decoration: const InputDecoration(labelText: 'Every'),
                      items: [
                        for (final period in TokenPeriod.values)
                          DropdownMenuItem(
                            value: period,
                            child: Text(period.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _tokenPeriod = value);
                        }
                      },
                    ),
                  ),
                ],
              ),
            if (_type == PlanType.tokenPack)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tokens,
                      keyboardType: TextInputType.number,
                      inputFormatters: digitsOnly,
                      decoration: const InputDecoration(
                        labelText: 'Tokens in the pack',
                      ),
                      validator: (value) =>
                          _wholeNumber(value, min: 1, max: 400),
                    ),
                  ),
                  const SizedBox(width: appSpaceMd),
                  Expanded(
                    child: TextFormField(
                      controller: _validity,
                      keyboardType: TextInputType.number,
                      inputFormatters: digitsOnly,
                      decoration: const InputDecoration(
                        labelText: 'Valid for (days)',
                        helperText: 'Empty = no expiry',
                      ),
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? null
                          : _wholeNumber(value, min: 1, max: 730),
                    ),
                  ),
                ],
              ),
            if (_type != PlanType.unlimited) ...[
              const SizedBox(height: appSpaceSm),
              Text(
                _type == PlanType.tokens
                    ? 'One token per booked class. Tokens refill each period '
                          'from the member\'s start date; unused tokens expire. '
                          'Cancelling gives the token back.'
                    : 'One token per booked class. Cancelling gives the token '
                          'back.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: appSubtleText,
                ),
              ),
            ],
            if (_type == PlanType.unlimited)
              Text(
                'Unlimited tokens: members book as many classes as they like.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: appSubtleText,
                ),
              ),
            const SizedBox(height: appSpaceLg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Price',
                      suffixText: widget.currency,
                    ),
                    validator: (value) => parsePriceCents(value ?? '') == null
                        ? 'Enter a price, e.g. 129 or 89.50'
                        : null,
                  ),
                ),
                const SizedBox(width: appSpaceMd),
                Expanded(
                  child: DropdownButtonFormField<BillingPeriod>(
                    isExpanded: true,
                    // initialValue is read once; the key resets it when the
                    // plan type switches the billing period.
                    key: ValueKey(_billing),
                    initialValue: _billing,
                    decoration: const InputDecoration(labelText: 'Billed'),
                    items: [
                      for (final period in BillingPeriod.offered)
                        DropdownMenuItem(
                          value: period,
                          child: Text(period.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _billing = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: appSpaceLg),
            const _FieldLabel('Tokens can be spent on'),
            const SizedBox(height: appSpaceSm),
            Wrap(
              spacing: appSpaceSm,
              runSpacing: appSpaceSm,
              children: [
                for (final type in planClassTypes)
                  FilterChip(
                    label: Text(type),
                    selected: _classTypes.contains(type),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _classTypes.add(type);
                      } else {
                        _classTypes.remove(type);
                      }
                    }),
                  ),
              ],
            ),
            if (_classTypes.isEmpty) ...[
              const SizedBox(height: appSpaceSm),
              Text(
                'Pick at least one class type.',
                style: theme.textTheme.bodySmall?.copyWith(color: appDanger),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: appMono(fontSize: 10, letterSpacing: 1.4),
    );
  }
}
