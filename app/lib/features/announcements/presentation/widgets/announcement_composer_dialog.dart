import 'dart:typed_data';

import 'package:app/core/presentation/app_form_dialog.dart';
import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/features/announcements/domain/models/announcement.dart';
import 'package:app/features/announcements/domain/repositories/announcement_repository.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Create/edit dialog for a single announcement, including the optional
/// header image upload. Pops `true` when something was saved.

class AnnouncementComposerDialog extends StatefulWidget {
  const AnnouncementComposerDialog({
    super.key,
    this.existing,
    required this.repository,
  });

  final Announcement? existing;
  final AnnouncementRepository repository;

  @override
  State<AnnouncementComposerDialog> createState() =>
      _AnnouncementComposerDialogState();
}

class _AnnouncementComposerDialogState
    extends State<AnnouncementComposerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _imagePicker = ImagePicker();
  bool _isSaving = false;
  bool _isUploadingImage = false;
  Uint8List? _selectedImageBytes;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _titleController.text = existing.title;
      _descriptionController.text = existing.description;
      _imageUrlController.text = existing.imageUrl ?? '';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickImageFromGallery() async {
    if (_isSaving || _isUploadingImage) {
      return;
    }
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1800,
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
        _isUploadingImage = true;
        _selectedImageBytes = bytes;
      });
      final imageUrl = await widget.repository.uploadAnnouncementImage(
        bytes: bytes,
        filename: picked.name,
        contentType: contentType,
      );
      if (!mounted) {
        return;
      }
      _imageUrlController.text = imageUrl;
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to upload image'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_isSaving || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      if (_isEditing) {
        await widget.repository.updateAnnouncement(
          id: widget.existing!.id,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          imageUrl: _imageUrlController.text.trim().isEmpty
              ? null
              : _imageUrlController.text.trim(),
        );
      } else {
        await widget.repository.createAnnouncement(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          imageUrl: _imageUrlController.text.trim().isEmpty
              ? null
              : _imageUrlController.text.trim(),
        );
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(
              error,
              fallback: _isEditing
                  ? 'Failed to update announcement'
                  : 'Failed to create announcement',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppFormDialog(
      title: _isEditing ? 'Edit Announcement' : 'Create Announcement',
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: Text(
            _isSaving
                ? (_isEditing ? 'Saving...' : 'Posting...')
                : (_isEditing ? 'Save Changes' : 'Post Announcement'),
          ),
        ),
      ],
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(appRadiusLg),
                  color: appSurfaceAlt,
                  border: Border.all(color: appBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Add a gallery image',
                      style: TextStyle(
                        color: appText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Pick a photo from your phone. It will upload and attach automatically.',
                      style: TextStyle(color: appMutedText, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    if (_selectedImageBytes != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Image.memory(
                            _selectedImageBytes!,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _isUploadingImage
                              ? null
                              : _pickImageFromGallery,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 44),
                          ),
                          icon: _isUploadingImage
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.photo_library_outlined),
                          label: Text(
                            _isUploadingImage
                                ? 'Uploading...'
                                : 'Choose from gallery',
                          ),
                        ),
                        if (_imageUrlController.text.trim().isNotEmpty)
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _imageUrlController.clear();
                                _selectedImageBytes = null;
                              });
                            },
                            child: const Text('Remove image'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _titleController,
                style: const TextStyle(color: appText),
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'Saturday schedule update',
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Title is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _descriptionController,
                minLines: 4,
                maxLines: 7,
                style: const TextStyle(color: appText),
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Write the actual update athletes should read.',
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Description is required';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
