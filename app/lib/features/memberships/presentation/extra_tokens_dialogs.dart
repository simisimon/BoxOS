import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_form_dialog.dart';
import 'package:app/features/memberships/domain/membership_models.dart';
import 'package:app/features/memberships/presentation/plan_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Outcome of [showExtraTokenPriceDialog]: the new price of one extra token,
/// or null when the box stops selling extra tokens.
class ExtraTokenPriceChoice {
  const ExtraTokenPriceChoice(this.priceCents);

  final int? priceCents;
}

/// Set the price of one extra token. Resolves to the choice, null on cancel.
Future<ExtraTokenPriceChoice?> showExtraTokenPriceDialog(
  BuildContext context, {
  required int? currentPriceCents,
  required String currency,
}) {
  return showDialog<ExtraTokenPriceChoice>(
    context: context,
    builder: (_) => _ExtraTokenPriceDialog(
      currentPriceCents: currentPriceCents,
      currency: currency,
    ),
  );
}

class _ExtraTokenPriceDialog extends StatefulWidget {
  const _ExtraTokenPriceDialog({
    required this.currentPriceCents,
    required this.currency,
  });

  final int? currentPriceCents;
  final String currency;

  @override
  State<_ExtraTokenPriceDialog> createState() => _ExtraTokenPriceDialogState();
}

class _ExtraTokenPriceDialogState extends State<_ExtraTokenPriceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _price;

  @override
  void initState() {
    super.initState();
    final current = widget.currentPriceCents;
    _price = TextEditingController(
      text: current == null ? '' : priceInputText(current),
    );
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(
      context,
    ).pop(ExtraTokenPriceChoice(parsePriceCents(_price.text)!));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppFormDialog(
      title: 'Extra tokens',
      subtitle:
          'Members can get single tokens on top of their plan. Each token is '
          'valid for one month and is used when their plan cannot cover a '
          'class.',
      fitContent: true,
      actions: [
        if (widget.currentPriceCents != null)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const ExtraTokenPriceChoice(null)),
            child: const Text('Stop selling'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save price')),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _price,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Price per token',
                suffixText: widget.currency,
              ),
              validator: (value) => parsePriceCents(value ?? '') == null
                  ? 'Enter a price, e.g. 15 or 12.50'
                  : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: appSpaceSm),
            Text(
              'Online payment comes later; for now you add tokens by hand '
              'from a member\'s detail.',
              style: theme.textTheme.bodySmall?.copyWith(color: appSubtleText),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the owner enters in [showGrantExtraTokensDialog].
class ExtraTokenGrant {
  const ExtraTokenGrant({required this.tokens, required this.priceCents});

  final int tokens;

  /// Total paid for the tokens.
  final int priceCents;
}

/// Add extra tokens to a member. Resolves to the grant, null on cancel.
Future<ExtraTokenGrant?> showGrantExtraTokensDialog(
  BuildContext context, {
  required String memberName,
  required int? unitPriceCents,
  required String currency,
}) {
  return showDialog<ExtraTokenGrant>(
    context: context,
    builder: (_) => _GrantExtraTokensDialog(
      memberName: memberName,
      unitPriceCents: unitPriceCents,
      currency: currency,
    ),
  );
}

class _GrantExtraTokensDialog extends StatefulWidget {
  const _GrantExtraTokensDialog({
    required this.memberName,
    required this.unitPriceCents,
    required this.currency,
  });

  final String memberName;
  final int? unitPriceCents;
  final String currency;

  @override
  State<_GrantExtraTokensDialog> createState() =>
      _GrantExtraTokensDialogState();
}

class _GrantExtraTokensDialogState extends State<_GrantExtraTokensDialog> {
  static const maxTokens = 50;

  final _formKey = GlobalKey<FormState>();
  final _tokens = TextEditingController(text: '1');
  late final TextEditingController _price;

  /// The price follows the token count until the owner edits it.
  bool _priceEdited = false;

  @override
  void initState() {
    super.initState();
    _price = TextEditingController(text: _defaultPrice(1));
  }

  @override
  void dispose() {
    _tokens.dispose();
    _price.dispose();
    super.dispose();
  }

  String _defaultPrice(int tokens) =>
      priceInputText((widget.unitPriceCents ?? 0) * tokens);

  void _tokensChanged(String value) {
    if (_priceEdited) return;
    final count = int.tryParse(value.trim());
    if (count == null) return;
    _price.text = _defaultPrice(count);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      ExtraTokenGrant(
        tokens: int.parse(_tokens.text.trim()),
        priceCents: parsePriceCents(_price.text)!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unitPrice = widget.unitPriceCents;
    return AppFormDialog(
      title: 'Add extra tokens',
      subtitle:
          'For ${widget.memberName}. Valid for one month from today, used '
          'when their plan cannot cover a class.',
      fitContent: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add tokens')),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _tokens,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Tokens'),
                    onChanged: _tokensChanged,
                    validator: (value) {
                      final count = int.tryParse((value ?? '').trim());
                      if (count == null || count < 1 || count > maxTokens) {
                        return 'Enter 1 to $maxTokens';
                      }
                      return null;
                    },
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
                      labelText: 'Paid',
                      suffixText: widget.currency,
                    ),
                    onChanged: (_) => _priceEdited = true,
                    validator: (value) => parsePriceCents(value ?? '') == null
                        ? 'Enter an amount, e.g. 0 or 15'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: appSpaceSm),
            Text(
              unitPrice == null
                  ? 'Set a price per token under Settings → Memberships to '
                        'fill in the amount.'
                  : '${formatPrice(unitPrice, widget.currency)} per token. '
                        'Enter 0 for free tokens.',
              style: theme.textTheme.bodySmall?.copyWith(color: appSubtleText),
            ),
          ],
        ),
      ),
    );
  }
}
