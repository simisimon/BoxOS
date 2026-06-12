import 'dart:typed_data';

import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/features/auth/presentation/widgets/auth_stage.dart';
import 'package:app/features/gyms/data/repositories/api_gym_repository.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class CreateGymScreen extends ConsumerStatefulWidget {
  const CreateGymScreen({super.key});

  @override
  ConsumerState<CreateGymScreen> createState() => _CreateGymScreenState();
}

class _CreateGymScreenState extends ConsumerState<CreateGymScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  final _websiteController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _imagePicker = ImagePicker();
  bool _isSubmitting = false;
  bool _isUploadingLogo = false;
  String? _errorMessage;
  Uint8List? _selectedLogoBytes;
  String? _logoUrl;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _websiteController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String? _requiredValidator(String? value, String label) {
    if ((value ?? '').trim().isEmpty) {
      return '$label is required';
    }
    return null;
  }

  String? _emailValidator(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return null; // Optional field
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) return 'Enter a valid email';
    return null;
  }

  String? _urlValidator(String? value) {
    final url = value?.trim() ?? '';
    if (url.isEmpty) return null; // Optional field
    try {
      Uri.parse(url);
      return null;
    } catch (_) {
      return 'Enter a valid URL';
    }
  }

  Future<void> _pickLogoFromGallery() async {
    if (_isSubmitting || _isUploadingLogo) return;

    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1200,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final contentType = switch (picked.mimeType) {
        final type? when type.trim().isNotEmpty => type,
        _ when picked.name.toLowerCase().endsWith('.png') => 'image/png',
        _ when picked.name.toLowerCase().endsWith('.webp') => 'image/webp',
        _ => 'image/jpeg',
      };

      setState(() {
        _isUploadingLogo = true;
        _selectedLogoBytes = bytes;
      });

      final logoUrl = await ref.read(gymRepositoryProvider).uploadGymLogo(
            bytes: bytes,
            filename: picked.name,
            contentType: contentType,
          );

      if (!mounted) return;

      setState(() {
        _logoUrl = logoUrl;
        _isUploadingLogo = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isUploadingLogo = false;
        _selectedLogoBytes = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to upload logo'),
          ),
        ),
      );
    }
  }

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid || _isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final gym = await ref.read(gymRepositoryProvider).createGym(
            name: _nameController.text.trim(),
            logoUrl: _logoUrl ?? '',
            timezone: 'UTC',
          );
      ref.invalidate(currentProfileProvider);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${gym.name} created successfully!')),
      );
      context.go('/home');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = errorMessageFrom(error, fallback: 'Failed to create box');
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final hasAccess = profile?.accountType == AccountType.admin;

    if (!hasAccess) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 64, color: appMutedText),
                const SizedBox(height: 16),
                Text(
                  'Access Denied',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Only admin accounts can create a box.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: appMutedText),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Go to Home'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return AuthStage(
      title: 'CREATE YOUR BOX',
      headline: 'Launch your box.',
      description:
          'Set up your box details to unlock scheduling, member management, and workout programming.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Required Fields Section
            AuthFieldGroup(
              icon: Icons.storefront_outlined,
              title: 'Box Details',
              subtitle: 'Choose a name for your box.',
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Box Name *',
                      hintText: 'CrossFit Downtown',
                    ),
                    validator: (value) => _requiredValidator(value, 'Box name'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // Optional Fields Section
            AuthFieldGroup(
              icon: Icons.tune_outlined,
              title: 'Additional Details',
              subtitle: 'Optional information to complete your box profile.',
              child: Column(
                children: [
                  // Logo Upload
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: appSurfaceAlt,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: appBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Box Logo (optional)',
                          style: TextStyle(
                            color: appMutedText,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_selectedLogoBytes != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              _selectedLogoBytes!,
                              height: 120,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        FilledButton.icon(
                          onPressed: _isUploadingLogo || _isSubmitting
                              ? null
                              : _pickLogoFromGallery,
                          icon: _isUploadingLogo
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  _selectedLogoBytes != null
                                      ? Icons.edit
                                      : Icons.add_photo_alternate_outlined,
                                ),
                          label: Text(
                            _isUploadingLogo
                                ? 'Uploading...'
                                : (_selectedLogoBytes != null
                                    ? 'Change Logo'
                                    : 'Pick from Gallery'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descriptionController,
                    textInputAction: TextInputAction.next,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      hintText: 'Tell members about your box...',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Address (optional)',
                      hintText: 'Main Street 123, Berlin',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _websiteController,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Website (optional)',
                      hintText: 'https://mybox.com',
                    ),
                    validator: _urlValidator,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailController,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Contact Email (optional)',
                      hintText: 'contact@mybox.com',
                    ),
                    validator: _emailValidator,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    textInputAction: TextInputAction.done,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone (optional)',
                      hintText: '+49 123 456 789',
                    ),
                  ),
                ],
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              AuthInlineError(message: _errorMessage!),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Create Box'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _isSubmitting ? null : () => context.go('/home'),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
