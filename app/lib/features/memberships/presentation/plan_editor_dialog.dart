import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_form_dialog.dart';
import 'package:app/features/memberships/domain/membership_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Create or edit a membership plan. Resolves to the draft on save, null on
/// cancel. Saving is left to the caller.
Future<MembershipPlanDraft?> showPlanEditorDialog(
  BuildContext context, {
  MembershipPlan? plan,
  required String currency,
}) {
  return showDialog<MembershipPlanDraft>(
    context: context,
    builder: (_) => _PlanEditorDialog(plan: plan, currency: currency),
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
  const _PlanEditorDialog({required this.plan, required this.currency});

  final MembershipPlan? plan;
  final String currency;

  @override
  State<_PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends State<_PlanEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _perWeek;
  late final TextEditingController _classCount;
  late final TextEditingController _validity;
  late PlanType _type;
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
    _perWeek = TextEditingController(text: '${plan?.classesPerWeek ?? 2}');
    _classCount = TextEditingController(text: '${plan?.classCount ?? 10}');
    _validity = TextEditingController(
      text: plan == null
          ? '90'
          : (plan.validityDays == null ? '' : '${plan.validityDays}'),
    );
    _type = plan?.type ?? PlanType.unlimited;
    _billing = plan?.billingPeriod ?? BillingPeriod.monthly;
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
    _perWeek.dispose();
    _classCount.dispose();
    _validity.dispose();
    super.dispose();
  }

  void _setType(PlanType type) {
    setState(() {
      _type = type;
      // Punch cards are usually paid once; the others usually monthly.
      if (type == PlanType.punchCard) {
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
        classesPerWeek: _type == PlanType.weekly
            ? int.parse(_perWeek.text.trim())
            : null,
        classCount: _type == PlanType.punchCard
            ? int.parse(_classCount.text.trim())
            : null,
        validityDays: _type == PlanType.punchCard && validityText.isNotEmpty
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
    return AppFormDialog(
      title: isEdit ? 'Edit plan' : 'New plan',
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
                hintText: 'e.g. Unlimited, 2x per week, 10-class card',
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
                ButtonSegment(value: PlanType.weekly, label: Text('Per week')),
                ButtonSegment(
                  value: PlanType.punchCard,
                  label: Text('Punch card'),
                ),
              ],
              selected: {_type},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => _setType(selection.first),
            ),
            const SizedBox(height: appSpaceMd),
            if (_type == PlanType.weekly)
              TextFormField(
                controller: _perWeek,
                keyboardType: TextInputType.number,
                inputFormatters: digitsOnly,
                decoration: const InputDecoration(
                  labelText: 'Classes per week',
                  helperText: 'Counted Monday to Sunday.',
                ),
                validator: (value) => _wholeNumber(value, min: 1, max: 14),
              ),
            if (_type == PlanType.punchCard)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _classCount,
                      keyboardType: TextInputType.number,
                      inputFormatters: digitsOnly,
                      decoration: const InputDecoration(
                        labelText: 'Classes on the card',
                      ),
                      validator: (value) =>
                          _wholeNumber(value, min: 1, max: 200),
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
            if (_type == PlanType.unlimited)
              Text(
                'Members can book as many classes as they like.',
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
                    // initialValue is read once; the key resets it when the
                    // plan type switches the billing period.
                    key: ValueKey(_billing),
                    initialValue: _billing,
                    decoration: const InputDecoration(labelText: 'Billed'),
                    items: [
                      for (final period in BillingPeriod.values)
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
            const _FieldLabel('Included class types'),
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
