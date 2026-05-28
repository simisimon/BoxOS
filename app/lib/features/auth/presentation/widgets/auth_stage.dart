import 'dart:ui';

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
    this.accentColor = const Color(0xFF5FB2FF),
    this.backgroundColor = const Color(0xFF09111E),
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
              const Color(0xFF10192A),
              const Color(0xFF0B1320),
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
                    color: const Color(0xFF101826),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: Colors.white.withOpacity(0.07)),
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
    this.accentColor = const Color(0xFF5FB2FF),
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
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
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFB8C4D9),
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
        color: accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFD7E0EE),
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
        color: const Color(0xFFFF7A7A).withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF7A7A).withOpacity(0.24)),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: const Color(0xFFFFC1C1),
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
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            ),
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.16),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accentColor.withOpacity(0.3)),
          ),
          child: Text(
            'BoxOS',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
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
            accentColor.withOpacity(0.22),
            const Color(0xFF11192A),
            const Color(0xFF070B12),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Stack(
        children: [
          Positioned(right: -16, top: -16, child: _GlowOrb(color: accentColor, size: 92)),
          Positioned(
            right: 24,
            bottom: -28,
            child: _GlowOrb(color: const Color(0xFFB98CFF).withOpacity(0.52), size: 88),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: const Color(0xFFE8EEF8),
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                headline,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  height: 0.96,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFFD7E0EE),
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
              colors: [color.withOpacity(0.28), color.withOpacity(0.12)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.28)),
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
            colors: [color.withOpacity(0.95), color.withOpacity(0.0)],
          ),
        ),
      ),
    );
  }
}
