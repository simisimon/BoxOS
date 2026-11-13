import 'package:app/core/platform/open_external_url.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:flutter/material.dart';

const legalImprintUrl = 'https://boxos-app.de/impressum';
const legalPrivacyUrl = 'https://boxos-app.de/datenschutz';

/// Small "Impressum · Datenschutz" links; open the marketing site's legal
/// pages in a new tab.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      foregroundColor: appSubtleText,
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      minimumSize: const Size(0, 32),
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          style: style,
          onPressed: () => openExternalUrl(legalImprintUrl, newTab: true),
          child: const Text('Impressum'),
        ),
        const Text('·', style: TextStyle(color: appSubtleText)),
        TextButton(
          style: style,
          onPressed: () => openExternalUrl(legalPrivacyUrl, newTab: true),
          child: const Text('Datenschutz'),
        ),
      ],
    );
  }
}
