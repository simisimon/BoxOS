import 'dart:typed_data';

import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/core/presentation/mobile_content.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/data/repositories/api_profile_repository.dart';
import 'package:app/features/profile/domain/models/user_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _imagePicker = ImagePicker();
  bool _initialized = false;
  bool _isSubmitting = false;
  bool _isAvatarBusy = false;
  // Optimistic preview while an upload is in flight so the avatar updates
  // instantly even before the server response lands.
  Uint8List? _pendingAvatarBytes;
  String? _currentAvatarUrl;

  @override
  void dispose() {
    _displayNameController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  String? _displayNameValidator(String? value) {
    final displayName = value?.trim() ?? '';
    if (displayName.isEmpty) {
      return 'Display name is required';
    }
    if (displayName.length > 50) {
      return 'Display name must be 50 characters or fewer';
    }
    return null;
  }

  String? _nicknameValidator(String? value) {
    final nickname = value?.trim() ?? '';
    if (nickname.length > 30) {
      return 'Nickname must be 30 characters or fewer';
    }
    return null;
  }

  Future<void> _save() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid || _isSubmitting) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateProfile(
            displayName: _displayNameController.text.trim(),
            nickname: _nicknameController.text.trim(),
          );
      ref.invalidate(currentProfileProvider);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
      context.go('/home');
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to update profile'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _initializeFromProfile(UserProfile profile) {
    if (_initialized) {
      return;
    }
    _displayNameController.text = profile.displayName;
    _nicknameController.text = profile.nickname;
    _currentAvatarUrl = profile.profileImageUrl;
    _initialized = true;
  }

  Future<void> _pickAvatar() async {
    if (_isAvatarBusy) {
      return;
    }
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null) {
      return;
    }
    final bytes = await picked.readAsBytes();
    final contentType = switch (picked.mimeType) {
      final type? when type.trim().isNotEmpty => type,
      _ when picked.name.toLowerCase().endsWith('.png') => 'image/png',
      _ when picked.name.toLowerCase().endsWith('.webp') => 'image/webp',
      _ => 'image/jpeg',
    };
    setState(() {
      _isAvatarBusy = true;
      _pendingAvatarBytes = bytes;
    });
    try {
      final updated = await ref
          .read(profileRepositoryProvider)
          .uploadProfileAvatar(
            bytes: bytes,
            filename: picked.name,
            contentType: contentType,
          );
      ref.invalidate(currentProfileProvider);
      if (!mounted) {
        return;
      }
      setState(() {
        _currentAvatarUrl = updated.profileImageUrl;
        _pendingAvatarBytes = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _pendingAvatarBytes = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to update profile photo'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isAvatarBusy = false);
      }
    }
  }

  Future<void> _removeAvatar() async {
    if (_isAvatarBusy) {
      return;
    }
    setState(() => _isAvatarBusy = true);
    try {
      final updated =
          await ref.read(profileRepositoryProvider).deleteProfileAvatar();
      ref.invalidate(currentProfileProvider);
      if (!mounted) {
        return;
      }
      setState(() {
        _currentAvatarUrl = updated.profileImageUrl;
        _pendingAvatarBytes = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to remove profile photo'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isAvatarBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);

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
              appPageBackgroundEnd,
            ],
          ),
        ),
        child: SafeArea(
          child: profileAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => MobileContent(
              padding: const EdgeInsets.all(16),
              child: _StateCard(
                icon: Icons.error_outline,
                title: 'Failed to load profile',
                message: errorMessageFrom(
                  error,
                  fallback: 'Failed to load profile',
                ),
                accentColor: appPrimary,
              ),
            ),
            data: (profile) {
              _initializeFromProfile(profile);
              return MobileScrollableContent(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _EditProfileHero(
                        onBack: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(height: 16),
                      const _SectionTitle(
                        eyebrow: 'Profile',
                        title: 'Refine your identity',
                        subtitle:
                            'Keep the public parts of your BoxOS profile clean, recognizable, and easy to trust.',
                      ),
                      const SizedBox(height: 12),
                      _AvatarCard(
                        displayName: profile.displayName,
                        currentUrl: _currentAvatarUrl ?? profile.profileImageUrl,
                        pendingBytes: _pendingAvatarBytes,
                        busy: _isAvatarBusy,
                        onPick: _pickAvatar,
                        onRemove:
                            (_currentAvatarUrl ?? profile.profileImageUrl)
                                    .trim()
                                    .isEmpty
                                ? null
                                : _removeAvatar,
                      ),
                      const SizedBox(height: 12),
                      _FieldCard(
                        icon: Icons.mail_outline,
                        title: 'Email',
                        subtitle:
                            'Your account email is shown here and cannot be edited from this screen.',
                        child: TextFormField(
                          initialValue: profile.email,
                          enabled: false,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _FieldCard(
                        icon: Icons.badge_outlined,
                        title: 'Display Name',
                        subtitle:
                            'This is how you appear across the app experience.',
                        child: TextFormField(
                          controller: _displayNameController,
                          decoration: const InputDecoration(
                            labelText: 'Display Name',
                            border: OutlineInputBorder(),
                          ),
                          validator: _displayNameValidator,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _FieldCard(
                        icon: Icons.alternate_email,
                        title: 'Nickname',
                        subtitle:
                            'Optional shorthand for faster recognition in social or class contexts.',
                        child: TextFormField(
                          controller: _nicknameController,
                          decoration: const InputDecoration(
                            labelText: 'Nickname',
                            border: OutlineInputBorder(),
                          ),
                          validator: _nicknameValidator,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _isSubmitting ? null : _save,
                          child: _isSubmitting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Save Profile'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EditProfileHero extends StatelessWidget {
  const _EditProfileHero({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const accentColor = appPrimary;

    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
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
            child: _GlowOrb(color: appPrimary.withOpacity(0.6), size: 88),
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
                  const _HeroPill(label: 'Edit Profile', color: accentColor),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Edit Profile',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: appPrimary,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sharpen how you show up.',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: appText,
                  fontWeight: FontWeight.w900,
                  height: 0.96,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Update the identity details that teammates, coaches, and gym admins see throughout BoxOS.',
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

class _FieldCard extends StatelessWidget {
  const _FieldCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: appBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAccentBadge(icon: icon, color: appPrimary),
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
            color: appPrimary,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: appText,
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
        color: appSurface,
        borderRadius: BorderRadius.circular(24),
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
                    color: appText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: appSubtleText,
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
          color: appText,
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
            color: appSurfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: appBorder),
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
            colors: [color.withOpacity(0.95), color.withOpacity(0.0)],
          ),
        ),
      ),
    );
  }
}

/// Profile photo editor: live preview, gallery picker, and remove. Optimistic
/// preview swaps to the freshly picked bytes immediately so the avatar updates
/// without waiting for the upload round-trip.
class _AvatarCard extends StatelessWidget {
  const _AvatarCard({
    required this.displayName,
    required this.currentUrl,
    required this.pendingBytes,
    required this.busy,
    required this.onPick,
    required this.onRemove,
  });

  final String displayName;
  final String currentUrl;
  final Uint8List? pendingBytes;
  final bool busy;
  final Future<void> Function() onPick;
  final Future<void> Function()? onRemove;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(appSpaceLg),
      child: Row(
        children: [
          _AvatarPreview(
            displayName: displayName,
            currentUrl: currentUrl,
            pendingBytes: pendingBytes,
          ),
          const SizedBox(width: appSpaceLg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Profile photo',
                  style: TextStyle(
                    color: appText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'JPEG, PNG or WEBP up to 2 MB.',
                  style: TextStyle(
                    color: appSubtleText,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: appSpaceMd),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppPrimaryButton(
                      label: currentUrl.trim().isEmpty
                          ? 'Add photo'
                          : 'Replace',
                      icon: Icons.photo_library_outlined,
                      onPressed: busy ? null : onPick,
                      size: AppButtonSize.md,
                      expand: false,
                      busy: busy,
                    ),
                    if (onRemove != null)
                      AppGhostButton(
                        label: 'Remove',
                        icon: Icons.delete_outline_rounded,
                        onPressed: busy ? null : onRemove,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({
    required this.displayName,
    required this.currentUrl,
    required this.pendingBytes,
  });

  final String displayName;
  final String currentUrl;
  final Uint8List? pendingBytes;

  @override
  Widget build(BuildContext context) {
    const size = 76.0;
    // Pending bytes win so the picker selection shows instantly; once the
    // upload completes the parent clears pendingBytes and the server-resolved
    // image takes over.
    if (pendingBytes != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: appPrimaryHairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.memory(pendingBytes!, fit: BoxFit.cover),
      );
    }
    return AppAvatar(
      displayName: displayName,
      imageUrl: currentUrl.isEmpty ? null : currentUrl,
      size: size,
    );
  }
}
