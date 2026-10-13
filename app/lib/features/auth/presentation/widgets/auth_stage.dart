import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/mobile_content.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _boxOsLogoAsset = 'assets/images/boxOS_logo.png';

class AuthStage extends StatelessWidget {
  const AuthStage({
    super.key,
    required this.title,
    required this.headline,
    required this.description,
    required this.child,
    this.eyebrow,
    this.footer,
    this.showBrandHero = false,
    this.accentColor = appPrimary,
    this.backgroundColor = appPageBackground,
  });

  final String title;
  final String headline;
  final String description;
  final Widget child;
  final String? eyebrow;
  final Widget? footer;
  final bool showBrandHero;
  final Color accentColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: backgroundColor,
      body: DecoratedBox(
        decoration: appPageDecoration(),
        child: SafeArea(
          child: MobileScrollableContent(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showBrandHero) ...[
                  const SizedBox(height: 18),
                  _BrandHero(accentColor: accentColor),
                  const SizedBox(height: 28),
                ] else ...[
                  _TopBar(accentColor: accentColor),
                  const SizedBox(height: 16),
                  _HeroCard(
                    title: title,
                    headline: headline,
                    description: description,
                    accentColor: accentColor,
                  ),
                  const SizedBox(height: 18),
                ],
                if (eyebrow != null)
                  Text(
                    eyebrow!.toUpperCase(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: accentColor,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (eyebrow != null) const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: appPanelDecoration(radius: 26),
                  child: child,
                ),
                if (footer != null) ...[const SizedBox(height: 14), footer!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AuthFieldGroup extends StatelessWidget {
  const AuthFieldGroup({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.accentColor = appPrimary,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inputTheme = theme.inputDecorationTheme;

    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: inputTheme.copyWith(
          filled: true,
          fillColor: appSurfaceAlt,
          labelStyle: const TextStyle(color: appMutedText),
          hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
          floatingLabelStyle: TextStyle(color: accentColor),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: appBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: accentColor, width: 1.6),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFFDC2626)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.6),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAccentBadge(icon: icon, color: accentColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: appMutedText,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class AuthNoteCard extends StatelessWidget {
  const AuthNoteCard({
    super.key,
    required this.title,
    required this.body,
    this.accentColor = appPrimary,
  });

  final String title;
  final String body;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appSurfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: appText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: appMutedText,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class AuthInlineError extends StatelessWidget {
  const AuthInlineError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFECDD3)),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF991B1B),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class AuthActionRow extends StatelessWidget {
  const AuthActionRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(children: children);
  }
}

class _BrandHero extends StatelessWidget {
  const _BrandHero({required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: 'BoxOS logo',
            image: true,
            child: Image.asset(
              _boxOsLogoAsset,
              width: 340,
              height: 340,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  Icon(Icons.fitness_center, size: 170, color: accentColor),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'BoxOS',
            style: GoogleFonts.oswald(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              color: appText,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: appSurface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: appBorder),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: appText),
            ),
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: appSurface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: appBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                _boxOsLogoAsset,
                width: 22,
                height: 22,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.fitness_center,
                  size: 20,
                  color: appPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'BoxOS',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: appText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.headline,
    required this.description,
    required this.accentColor,
  });

  final String title;
  final String headline;
  final String description;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: appHeroDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: accentColor,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            headline,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: appText,
              fontWeight: FontWeight.w900,
              height: 0.96,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: appMutedText,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
