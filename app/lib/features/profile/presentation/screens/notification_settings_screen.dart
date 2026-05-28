import 'dart:ui';

import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/mobile_content.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/data/repositories/api_profile_repository.dart';
import 'package:app/features/profile/domain/models/notification_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  NotificationPreferences? _preferences;
  bool _isSubmitting = false;

  Future<void> _save() async {
    final preferences = _preferences;
    if (preferences == null || _isSubmitting) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateNotificationPreferences(preferences: preferences);
      ref.invalidate(notificationPreferencesProvider);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification settings updated.')),
      );
      context.go('/profile');
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(
              error,
              fallback: 'Failed to update notification settings',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _updatePreferences(NotificationPreferences nextPreferences) {
    setState(() => _preferences = nextPreferences);
  }

  @override
  Widget build(BuildContext context) {
    final preferencesAsync = ref.watch(notificationPreferencesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF09111E),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF09111E),
              Color(0xFF10192A),
              Color(0xFF0B1320),
            ],
          ),
        ),
        child: SafeArea(
          child: preferencesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => MobileContent(
              padding: const EdgeInsets.all(16),
              child: _StateCard(
                icon: Icons.error_outline,
                title: 'Failed to load notification settings',
                message: errorMessageFrom(
                  error,
                  fallback: 'Failed to load notification settings',
                ),
                accentColor: const Color(0xFFFF6B2C),
              ),
            ),
            data: (preferences) {
              _preferences ??= preferences;
              final currentPreferences = _preferences!;
              return MobileContent(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SettingsHero(
                      onBack: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView(
                        children: [
                          const _SectionTitle(
                            eyebrow: 'Preferences',
                            title: 'Control what reaches you',
                            subtitle:
                                'Shape which operational alerts, workout updates, and achievement signals BoxOS sends to this account.',
                          ),
                          const SizedBox(height: 12),
                          _PreferenceCard(
                            title: 'Booking Confirmations',
                            subtitle: 'Class booking success and changes.',
                            accentColor: const Color(0xFF5FB2FF),
                            value: currentPreferences.bookingConfirmations,
                            onChanged: (value) {
                              _updatePreferences(
                                currentPreferences.copyWith(
                                  bookingConfirmations: value,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _PreferenceCard(
                            title: 'Waitlist Promotions',
                            subtitle: 'You moved from the waitlist into class.',
                            accentColor: const Color(0xFF7EE7C6),
                            value: currentPreferences.waitlistPromotions,
                            onChanged: (value) {
                              _updatePreferences(
                                currentPreferences.copyWith(
                                  waitlistPromotions: value,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _PreferenceCard(
                            title: 'Payment Issues',
                            subtitle:
                                'Membership payment failures and billing alerts.',
                            accentColor: const Color(0xFFFF7A7A),
                            value: currentPreferences.paymentIssues,
                            onChanged: (value) {
                              _updatePreferences(
                                currentPreferences.copyWith(paymentIssues: value),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _PreferenceCard(
                            title: 'WOD Posted',
                            subtitle: 'A new workout is published for your gym.',
                            accentColor: const Color(0xFFFF6B2C),
                            value: currentPreferences.wodPosted,
                            onChanged: (value) {
                              _updatePreferences(
                                currentPreferences.copyWith(wodPosted: value),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _PreferenceCard(
                            title: 'PR Achievements',
                            subtitle:
                                'Personal-record and milestone notifications.',
                            accentColor: const Color(0xFFB98CFF),
                            value: currentPreferences.prAchievements,
                            onChanged: (value) {
                              _updatePreferences(
                                currentPreferences.copyWith(prAchievements: value),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _save,
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save Settings'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SettingsHero extends StatelessWidget {
  const _SettingsHero({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const accentColor = Color(0xFF5FB2FF);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withOpacity(0.24),
            const Color(0xFF11192A),
            const Color(0xFF070B12),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.14),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -12,
            top: -12,
            child: _GlowOrb(color: accentColor, size: 84),
          ),
          Positioned(
            right: 38,
            bottom: -28,
            child: _GlowOrb(
              color: const Color(0xFFB98CFF).withOpacity(0.6),
              size: 88,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _HeaderIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onTap: onBack,
                  ),
                  const SizedBox(width: 8),
                  const _HeroPill(
                    label: 'Notification Settings',
                    color: accentColor,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Notification Settings',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: const Color(0xFFE8EEF8),
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tune the signal, not the noise.',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  height: 0.96,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Choose which updates BoxOS should send to this account so operational alerts stay helpful instead of noisy.',
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

class _PreferenceCard extends StatelessWidget {
  const _PreferenceCard({
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final Color accentColor;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101826),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AccentBadge(icon: Icons.tune_rounded, color: accentColor),
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
          const SizedBox(width: 12),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: const Color(0xFF7EE7C6),
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            height: 0.96,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFFB8C4D9),
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.accentColor,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101826),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
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
                const SizedBox(height: 6),
                Text(
                  message,
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
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Icon(icon, color: Colors.white),
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
            colors: [
              color.withOpacity(0.95),
              color.withOpacity(0.0),
            ],
          ),
        ),
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
              colors: [
                color.withOpacity(0.28),
                color.withOpacity(0.12),
              ],
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
