import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/mobile_content.dart';
import 'package:app/features/gyms/data/repositories/api_gym_repository.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CreateGymScreen extends ConsumerStatefulWidget {
  const CreateGymScreen({super.key});

  @override
  ConsumerState<CreateGymScreen> createState() => _CreateGymScreenState();
}

class _CreateGymScreenState extends ConsumerState<CreateGymScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _timezoneController = TextEditingController(text: 'Europe/Berlin');
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _logoUrlController.dispose();
    _timezoneController.dispose();
    super.dispose();
  }

  String? _requiredValidator(String? value, String label) {
    if ((value ?? '').trim().isEmpty) {
      return '$label is required';
    }
    return null;
  }

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid || _isSubmitting) {
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final gym = await ref
          .read(gymRepositoryProvider)
          .createGym(
            name: _nameController.text.trim(),
            logoUrl: _logoUrlController.text.trim(),
            timezone: _timezoneController.text.trim(),
          );
      ref.invalidate(currentProfileProvider);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${gym.name} created.')));
      context.go('/home');
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to create gym'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Gym')),
      body: MobileScrollableContent(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Gym Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => _requiredValidator(value, 'Gym name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _logoUrlController,
                decoration: const InputDecoration(
                  labelText: 'Logo URL',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => _requiredValidator(value, 'Logo URL'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _timezoneController,
                decoration: const InputDecoration(
                  labelText: 'Timezone',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => _requiredValidator(value, 'Timezone'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Gym'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
