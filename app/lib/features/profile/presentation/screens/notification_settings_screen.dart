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
      appBar: AppBar(title: const Text('Notification Settings')),
      body: preferencesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              errorMessageFrom(
                error,
                fallback: 'Failed to load notification settings',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (preferences) {
          _preferences ??= preferences;
          final currentPreferences = _preferences!;
          return MobileContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Choose which updates BoxOS should send to this account.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    children: [
                      _PreferenceTile(
                        title: 'Booking Confirmations',
                        subtitle: 'Class booking success and changes.',
                        value: currentPreferences.bookingConfirmations,
                        onChanged: (value) {
                          _updatePreferences(
                            currentPreferences.copyWith(
                              bookingConfirmations: value,
                            ),
                          );
                        },
                      ),
                      _PreferenceTile(
                        title: 'Waitlist Promotions',
                        subtitle: 'You moved from the waitlist into class.',
                        value: currentPreferences.waitlistPromotions,
                        onChanged: (value) {
                          _updatePreferences(
                            currentPreferences.copyWith(
                              waitlistPromotions: value,
                            ),
                          );
                        },
                      ),
                      _PreferenceTile(
                        title: 'Payment Issues',
                        subtitle:
                            'Membership payment failures and billing alerts.',
                        value: currentPreferences.paymentIssues,
                        onChanged: (value) {
                          _updatePreferences(
                            currentPreferences.copyWith(paymentIssues: value),
                          );
                        },
                      ),
                      _PreferenceTile(
                        title: 'WOD Posted',
                        subtitle: 'A new workout is published for your gym.',
                        value: currentPreferences.wodPosted,
                        onChanged: (value) {
                          _updatePreferences(
                            currentPreferences.copyWith(wodPosted: value),
                          );
                        },
                      ),
                      _PreferenceTile(
                        title: 'PR Achievements',
                        subtitle:
                            'Personal-record and milestone notifications.',
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
    );
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}
