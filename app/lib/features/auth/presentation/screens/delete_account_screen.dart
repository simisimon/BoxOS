import 'package:app/core/presentation/app_form_dialog.dart';
import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/mobile_content.dart';
import 'package:app/features/auth/application/auth_controller.dart';
import 'package:app/features/auth/data/repositories/api_auth_repository.dart';
import 'package:app/features/auth/domain/models/account_deletion_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  bool _isSubmitting = false;
  AccountDeletionCheck? _check;
  Object? _checkError;
  int? _handingOverGymId;

  @override
  void initState() {
    super.initState();
    _loadCheck();
  }

  Future<void> _loadCheck() async {
    setState(() => _checkError = null);
    try {
      final check = await ref
          .read(authRepositoryProvider)
          .fetchAccountDeletionCheck();
      if (mounted) {
        setState(() => _check = check);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _checkError = error);
      }
    }
  }

  Future<void> _chooseNewOwner(SoleOwnedGym gym) async {
    final candidate = await showDialog<OwnerCandidate>(
      context: context,
      builder: (_) => _ChooseOwnerDialog(gym: gym),
    );
    if (candidate == null || !mounted) {
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Make ${candidate.label} owner?',
      message:
          '${candidate.label} gets full owner access to ${gym.name}, '
          'including members, plans and settings.',
      confirmLabel: 'Make Owner',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _handingOverGymId = gym.id);
    try {
      await ref
          .read(authRepositoryProvider)
          .addGymOwner(gymId: gym.id, userId: candidate.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${candidate.label} is now an owner of ${gym.name}.'),
        ),
      );
      await _loadCheck();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to add the new owner'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _handingOverGymId = null);
      }
    }
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    super.dispose();
  }

  String? _passwordValidator(String? value) {
    if ((value ?? '').isEmpty) {
      return 'Current password is required';
    }
    return null;
  }

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    final check = _check;
    if (!isValid || _isSubmitting || check == null || !check.canDelete) {
      return;
    }

    final emptyGymNames = check.emptyGyms.map((gym) => gym.name).join(', ');
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Delete Account?',
      message:
          'This will immediately remove your account access, anonymize your '
          'profile data, and schedule permanent deletion after 30 days.'
          '${check.emptyGyms.isEmpty ? '' : '\n\n$emptyGymNames has no other members and will be deleted with all its data.'}',
      confirmLabel: 'Delete',
      destructive: true,
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .deleteAccount(
            currentPassword: _currentPasswordController.text,
            deleteEmptyGyms: check.emptyGyms.isNotEmpty,
          );
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Account scheduled for deletion. Personal data anonymized; permanent purge in 30 days.',
          ),
        ),
      );
      context.go('/login');
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to delete account'),
          ),
        ),
      );
      // Ownership may have changed elsewhere; show the current blockers.
      await _loadCheck();
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  List<Widget> _ownershipSection() {
    final check = _check;
    if (_checkError != null) {
      return [
        _NoticeCard(
          icon: Icons.error_outline,
          color: appDanger,
          title: 'Could not check your boxes',
          message: errorMessageFrom(
            _checkError!,
            fallback: 'Your box ownership could not be loaded.',
          ),
          action: OutlinedButton(
            onPressed: _loadCheck,
            child: const Text('Try Again'),
          ),
        ),
        const SizedBox(height: 12),
      ];
    }
    if (check == null) {
      return const [
        Center(child: CircularProgressIndicator()),
        SizedBox(height: 12),
      ];
    }
    return [
      for (final gym in check.gymsNeedingOwner) ...[
        _NoticeCard(
          icon: Icons.key_outlined,
          color: appWarning,
          title: 'Hand over ${gym.name}',
          message:
              'You are the only owner of ${gym.name}. Make another member '
              'owner before you delete your account.',
          action: FilledButton(
            onPressed: _handingOverGymId == null
                ? () => _chooseNewOwner(gym)
                : null,
            child: _handingOverGymId == gym.id
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Choose New Owner'),
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (check.emptyGyms.isNotEmpty) ...[
        _NoticeCard(
          icon: Icons.delete_forever_outlined,
          color: appDanger,
          title: 'Your box will be deleted',
          message:
              '${check.emptyGyms.map((gym) => gym.name).join(', ')} has no '
              'other members, so nobody can take it over. It is deleted with '
              'your account, including its schedule, workouts and plans.',
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = _check?.canDelete ?? false;
    return Scaffold(
      backgroundColor: appPageBackground,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              appPageBackground,
              appPageBackgroundSoft,
              Color(0xFF0B1320),
            ],
          ),
        ),
        child: SafeArea(
          child: MobileScrollableContent(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SecurityHero(
                    title: 'Delete Account',
                    headline: 'Make the irreversible choice carefully.',
                    description:
                        'Confirm your password before removing account access, anonymizing profile data, and scheduling permanent deletion.',
                    accentColor: appDanger,
                  ),
                  const SizedBox(height: 16),
                  const _SectionTitle(
                    eyebrow: 'Danger Zone',
                    title: 'Permanent account removal',
                    subtitle:
                        'This action is intentionally frictional. Read the consequences, confirm the password, then delete only if you are sure.',
                  ),
                  const SizedBox(height: 12),
                  const _WarningCard(),
                  const SizedBox(height: 12),
                  ..._ownershipSection(),
                  _FieldCard(
                    icon: Icons.lock_outline,
                    title: 'Current Password',
                    subtitle:
                        'Enter your password to confirm ownership of the account.',
                    accentColor: appDanger,
                    child: TextFormField(
                      controller: _currentPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Current Password',
                        border: OutlineInputBorder(),
                      ),
                      validator: _passwordValidator,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSubmitting || !canDelete ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: appDanger,
                        foregroundColor: Colors.white,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Delete Account'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChooseOwnerDialog extends StatefulWidget {
  const _ChooseOwnerDialog({required this.gym});

  final SoleOwnedGym gym;

  @override
  State<_ChooseOwnerDialog> createState() => _ChooseOwnerDialogState();
}

class _ChooseOwnerDialogState extends State<_ChooseOwnerDialog> {
  OwnerCandidate? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppFormDialog(
      title: 'Choose New Owner',
      subtitle: 'Pick a member of ${widget.gym.name} to take over as owner.',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.of(context).pop(_selected),
          child: const Text('Continue'),
        ),
      ],
      child: RadioGroup<int>(
        groupValue: _selected?.id,
        onChanged: (id) => setState(
          () => _selected = widget.gym.members.firstWhere(
            (member) => member.id == id,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final member in widget.gym.members)
              RadioListTile<int>(
                value: member.id,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  member.label,
                  style: theme.textTheme.bodyLarge?.copyWith(color: appText),
                ),
                subtitle: Text(
                  member.role == 'trainer'
                      ? 'Trainer · ${member.email}'
                      : member.email,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: appSubtleText,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAccentBadge(icon: icon, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: appMutedText,
                    height: 1.45,
                  ),
                ),
                if (action != null) ...[const SizedBox(height: 14), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityHero extends StatelessWidget {
  const _SecurityHero({
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
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentColor.withOpacity(0.24), appSurface, appSurfaceAlt],
        ),
        border: Border.all(color: appBorder),
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
            child: _GlowOrb(color: appPrimary.withOpacity(0.45), size: 88),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _HeaderIconButton(),
                  const SizedBox(width: 8),
                  _HeroPill(label: title, color: accentColor),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: appPrimary,
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
                  color: appMutedText,
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
            color: appDanger,
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
            color: appSubtleText,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appDanger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: appDanger.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What happens next',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '• Account access is removed immediately\n'
            '• Profile data is anonymized\n'
            '• Permanent deletion happens after 30 days',
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

class _FieldCard extends StatelessWidget {
  const _FieldCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.accentColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: appBorder),
      ),
      child: Row(
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
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: appSubtleText,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label, required this.color});

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
  const _HeaderIconButton();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Back',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => Navigator.of(context).maybePop(),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: appSurfaceAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: appSurfaceAlt),
          ),
          child: const Icon(Icons.arrow_back_rounded, color: Colors.white),
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
