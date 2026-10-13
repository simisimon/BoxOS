import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/announcements/data/repositories/api_announcement_repository.dart';
import 'package:app/features/announcements/domain/models/announcement.dart';
import 'package:app/features/announcements/presentation/widgets/announcement_composer_dialog.dart';
import 'package:app/features/announcements/presentation/widgets/announcement_feed.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Self-contained box-news section: owns the announcement load, every
/// mutation handler and the feed itself, so any surface can mount it with a
/// single widget.
///
/// This used to be inlined in the home screen together with all of its CRUD
/// handlers. Home now shows only today's WOD, the next booking and the weekly
/// stat, so the news feed lives wherever box communication belongs.
class AnnouncementFeedSection extends ConsumerStatefulWidget {
  const AnnouncementFeedSection({super.key});

  @override
  ConsumerState<AnnouncementFeedSection> createState() =>
      _AnnouncementFeedSectionState();
}

class _AnnouncementFeedSectionState
    extends ConsumerState<AnnouncementFeedSection> {
  late Future<List<Announcement>> _announcementsFuture;

  @override
  void initState() {
    super.initState();
    _announcementsFuture = _loadAnnouncements();
  }

  Future<List<Announcement>> _loadAnnouncements() {
    return ref.read(announcementRepositoryProvider).fetchAnnouncements();
  }

  Future<void> _refreshAnnouncements() async {
    setState(() {
      _announcementsFuture = _loadAnnouncements();
    });
  }

  Future<void> _openAnnouncementComposer() async {
    final repository = ref.read(announcementRepositoryProvider);
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AnnouncementComposerDialog(repository: repository),
    );
    if (saved == true) {
      await _refreshAnnouncements();
    }
  }

  Future<void> _openAnnouncementEditor(Announcement announcement) async {
    final repository = ref.read(announcementRepositoryProvider);
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AnnouncementComposerDialog(
        existing: announcement,
        repository: repository,
      ),
    );
    if (saved == true) {
      await _refreshAnnouncements();
    }
  }

  Future<void> _deleteAnnouncement(Announcement announcement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: appSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: appBorder),
        ),
        title: const Text(
          'Delete announcement',
          style: TextStyle(color: appText),
        ),
        content: Text(
          'Delete "${announcement.title}"? This can’t be undone.',
          style: const TextStyle(color: appMutedText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: appDanger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref
          .read(announcementRepositoryProvider)
          .deleteAnnouncement(id: announcement.id);
      if (!mounted) {
        return;
      }
      await _refreshAnnouncements();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to delete announcement'),
          ),
        ),
      );
    }
  }

  Future<void> _toggleAnnouncementLike(Announcement announcement) async {
    try {
      final repository = ref.read(announcementRepositoryProvider);
      if (announcement.likedByMe) {
        await repository.unlikeAnnouncement(announcementId: announcement.id);
      } else {
        await repository.likeAnnouncement(announcementId: announcement.id);
      }
      if (!mounted) {
        return;
      }
      await _refreshAnnouncements();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Like update failed.'),
          ),
        ),
      );
    }
  }

  Future<void> _createAnnouncementComment(
    Announcement announcement,
    String body,
  ) async {
    try {
      await ref
          .read(announcementRepositoryProvider)
          .createComment(announcementId: announcement.id, body: body);
      if (!mounted) {
        return;
      }
      await _refreshAnnouncements();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Comment could not be posted.'),
          ),
        ),
      );
    }
  }

  Future<void> _editAnnouncementComment(
    AnnouncementComment comment,
    String body,
  ) async {
    try {
      await ref
          .read(announcementRepositoryProvider)
          .updateComment(commentId: comment.id, body: body);
      if (!mounted) {
        return;
      }
      await _refreshAnnouncements();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Comment could not be updated.'),
          ),
        ),
      );
    }
  }

  Future<void> _deleteAnnouncementComment(AnnouncementComment comment) async {
    try {
      await ref
          .read(announcementRepositoryProvider)
          .deleteComment(commentId: comment.id);
      if (!mounted) {
        return;
      }
      await _refreshAnnouncements();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Comment could not be deleted.'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final hasActiveGym = profile?.activeGym != null;
    final canManageAnnouncements = hasActiveGym &&
        (profile?.role == UserRole.admin || profile?.role == UserRole.trainer);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSectionHeader(title: 'News', eyebrow: 'From your box'),
        const SizedBox(height: appSpaceMd),
        AnnouncementFeed(
          announcementsFuture: _announcementsFuture,
          canManageAnnouncements: canManageAnnouncements,
          hasActiveGym: hasActiveGym,
          onCreateAnnouncement: _openAnnouncementComposer,
          onEditAnnouncement: _openAnnouncementEditor,
          onDeleteAnnouncement: _deleteAnnouncement,
          onToggleLike: _toggleAnnouncementLike,
          onCreateComment: _createAnnouncementComment,
          onEditComment: _editAnnouncementComment,
          onDeleteComment: _deleteAnnouncementComment,
        ),
      ],
    );
  }
}
