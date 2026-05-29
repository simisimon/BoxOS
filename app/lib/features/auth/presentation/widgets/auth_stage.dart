import 'dart:ui';

import 'package:app/features/home/presentation/widgets/app_shell.dart';
import 'package:flutter/material.dart';

class AuthStage extends StatelessWidget {
  const AuthStage({
    super.key,
    required this.title,
    required this.headline,
    required this.description,
    required this.child,
    this.eyebrow,
    this.footer,
    this.accentColor = const Color(0xFF2563EB),
    this.backgroundColor = const Color(0xFFF4F8FF),
  });

  final String title;
  final String headline;
  final String description;
  final Widget child;
  final String? eyebrow;
  final Widget? footer;
  final Color accentColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: backgroundColor,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              backgroundColor,
              const Color(0xFFEAF2FF),
              const Color(0xFFF8FBFF),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(accentColor: accentColor),
                const SizedBox(height: 16),
                _HeroCard(
                  title: title,
                  headline: headline,
                  description: description,
                  accentColor: accentColor,
                ),
                const SizedBox(height: 18),
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
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: const Color(0xFFD7E3F4)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x140F172A),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: child,
                ),
                if (footer != null) ...[
                  const SizedBox(height: 14),
                  footer!,
                ],
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
    this.accentColor = const Color(0xFF2563EB),
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
          fillColor: const Color(0xFFF8FBFF),
          labelStyle: const TextStyle(color: Color(0xFF475569)),
          hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
          floatingLabelStyle: TextStyle(color: accentColor),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFD7E3F4)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: accentColor, width: 1.6),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFDC2626)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
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
              _AccentBadge(icon: icon, color: accentColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF0F172A),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF475569),
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
    this.accentColor = const Color(0xFF7EE7C6),
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
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: const Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF334155),
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
        color: const Color(0xFFFFE4E6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDA4AF)),
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
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD7E3F4)),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
            ),
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accentColor.withOpacity(0.24)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                boxOsLogoAsset,
                width: 22,
                height: 22,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 8),
              Text(
                'BoxOS',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF0F172A),
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
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFFFFFF),
            const Color(0xFFF3F8FF),
            accentColor.withOpacity(0.14),
          ],
        ),
        border: Border.all(color: const Color(0xFFD7E3F4)),
      ),
      child: Stack(
        children: [
          Positioned(right: -16, top: -16, child: _GlowOrb(color: accentColor, size: 92)),
          Positioned(
            right: 24,
            bottom: -28,
            child: _GlowOrb(color: const Color(0xFF93C5FD).withOpacity(0.45), size: 88),
          ),
          Column(
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
                  color: const Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                  height: 0.96,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF475569),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccentBadge extends StatelessWidget {
  const _AccentBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withOpacity(0.20), color.withOpacity(0.08)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.20)),
          ),
          child: Icon(icon, color: color),
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withOpacity(0.34), color.withOpacity(0.0)],
          ),
        ),
      ),
    );
  }
}
