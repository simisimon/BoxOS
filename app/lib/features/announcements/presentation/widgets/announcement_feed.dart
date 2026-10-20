import 'package:app/core/presentation/app_form_dialog.dart';
import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/announcements/domain/models/announcement.dart';
import 'package:flutter/material.dart';

/// The box news feed: announcement cards with likes and comment threads.
///
/// Moved out of the home screen when home was reduced to its three entry
/// blocks (today's WOD, next booking, weekly stat). All mutations are
/// delegated to the parent via callbacks, so this widget stays stateless
/// apart from caching the last successful load.

class AnnouncementFeed extends StatefulWidget {
  const AnnouncementFeed({
    super.key,
    required this.announcementsFuture,
    required this.canManageAnnouncements,
    required this.hasActiveGym,
    required this.onCreateAnnouncement,
    required this.onEditAnnouncement,
    required this.onDeleteAnnouncement,
    required this.onToggleLike,
    required this.onCreateComment,
    required this.onEditComment,
    required this.onDeleteComment,
  });

  final Future<List<Announcement>> announcementsFuture;
  final bool canManageAnnouncements;
  final bool hasActiveGym;
  final Future<void> Function() onCreateAnnouncement;
  final Future<void> Function(Announcement announcement) onEditAnnouncement;
  final Future<void> Function(Announcement announcement) onDeleteAnnouncement;
  final Future<void> Function(Announcement announcement) onToggleLike;
  final Future<void> Function(Announcement announcement, String body)
  onCreateComment;
  final Future<void> Function(AnnouncementComment comment, String body)
  onEditComment;
  final Future<void> Function(AnnouncementComment comment) onDeleteComment;

  @override
  State<AnnouncementFeed> createState() => _AnnouncementFeedState();
}

class _AnnouncementFeedState extends State<AnnouncementFeed> {
  List<Announcement>? _cached;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Announcement>>(
      future: widget.announcementsFuture,
      builder: (context, snapshot) {
        if (!widget.hasActiveGym) {
          return _AnnouncementEmptyState(
            icon: Icons.campaign_outlined,
            title: 'No active box selected',
            subtitle:
                'Announcements appear once you are inside an active box context.',
            actionLabel: null,
            onTap: null,
          );
        }

        // Keep the cached list up-to-date whenever fresh data arrives.
        if (snapshot.hasData) {
          _cached = snapshot.data;
        }

        // On initial load (no cache yet) show a spinner.
        if (snapshot.connectionState == ConnectionState.waiting &&
            _cached == null) {
          return const AppLoadingState(height: 180);
        }

        // Show errors only when there is no cached data to fall back on.
        if (snapshot.hasError && _cached == null) {
          return _AnnouncementEmptyState(
            icon: Icons.error_outline,
            title: 'Failed to load announcements',
            subtitle: errorMessageFrom(
              snapshot.error!,
              fallback: 'Announcements could not be loaded.',
            ),
            actionLabel:
                widget.canManageAnnouncements ? 'Try posting instead' : null,
            onTap:
                widget.canManageAnnouncements
                    ? widget.onCreateAnnouncement
                    : null,
          );
        }

        final announcements = _cached ?? const <Announcement>[];
        if (announcements.isEmpty) {
          return _AnnouncementEmptyState(
            icon: Icons.campaign_outlined,
            title: 'No announcements yet',
            subtitle: widget.canManageAnnouncements
                ? 'Post the first update so athletes see a real gym news feed instead of placeholders.'
                : 'Your coaches and admins have not posted any announcements yet.',
            actionLabel:
                widget.canManageAnnouncements ? 'Create Announcement' : null,
            onTap:
                widget.canManageAnnouncements
                    ? widget.onCreateAnnouncement
                    : null,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.canManageAnnouncements) ...[
              _AnnouncementComposerBanner(onTap: widget.onCreateAnnouncement),
              const SizedBox(height: 12),
            ],
            for (final (index, announcement) in announcements.indexed) ...[
              _AnnouncementCard(
                key: ValueKey(announcement.id),
                announcement: announcement,
                canManage: announcement.canManage,
                onEdit: () => widget.onEditAnnouncement(announcement),
                onDelete: () => widget.onDeleteAnnouncement(announcement),
                onToggleLike: () => widget.onToggleLike(announcement),
                onCreateComment: (body) =>
                    widget.onCreateComment(announcement, body),
                onEditComment: widget.onEditComment,
                onDeleteComment: widget.onDeleteComment,
              ),
              if (index < announcements.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _AnnouncementComposerBanner extends StatelessWidget {
  const _AnnouncementComposerBanner({required this.onTap});

  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [appSurface, appSurfaceAlt],
          ),
          border: Border.all(color: appBorder),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 10,
          ),
          leading: const AppAccentBadge(
            icon: Icons.add_comment_outlined,
            color: appPrimary,
          ),
          title: const Text(
            'Post a new announcement',
            style: TextStyle(color: appText, fontWeight: FontWeight.w800),
          ),
          subtitle: const Text(
            'Share schedule changes, event reminders, or coach notes right on the home feed.',
            style: TextStyle(color: appSubtleText, height: 1.45),
          ),
          trailing: const Icon(Icons.north_east_rounded, color: appPrimary),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Thin shim around the shared [AppEmptyState] so the rest of this file's
/// call sites stay unchanged. The signature collapses to whatever the shared
/// primitive offers; tap callbacks become a synchronous VoidCallback (the
/// async work is fire-and-forget — the parent already handles its own loading
/// state).
class _AnnouncementEmptyState extends StatelessWidget {
  const _AnnouncementEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: icon,
      title: title,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onAction: onTap == null ? null : () => onTap!(),
    );
  }
}

class _AnnouncementCard extends StatefulWidget {
  const _AnnouncementCard({
    super.key,
    required this.announcement,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleLike,
    required this.onCreateComment,
    required this.onEditComment,
    required this.onDeleteComment,
  });

  final Announcement announcement;
  final bool canManage;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;
  final Future<void> Function() onToggleLike;
  final Future<void> Function(String body) onCreateComment;
  final Future<void> Function(AnnouncementComment comment, String body)
  onEditComment;
  final Future<void> Function(AnnouncementComment comment) onDeleteComment;

  @override
  State<_AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends State<_AnnouncementCard> {
  final TextEditingController _commentController = TextEditingController();
  bool _commentSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [appSurface, appSurfaceAlt],
        ),
        border: Border.all(color: appBorder),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          collapsedIconColor: appPrimary,
          iconColor: appPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.announcement.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Posted by ${widget.announcement.authorName} · ${_formatAnnouncementDate(widget.announcement.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: appSubtleText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          widget.announcement.likedByMe
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 13,
                          color: widget.announcement.likedByMe
                              ? appDanger
                              : appSubtleText,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${widget.announcement.likeCount}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: appSubtleText,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 13,
                          color: appSubtleText,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${widget.announcement.commentCount}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: appSubtleText,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.canManage)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, color: appSubtleText),
                  color: appSurface,
                  onSelected: (value) {
                    if (value == 'edit') {
                      widget.onEdit();
                    } else if (value == 'delete') {
                      widget.onDelete();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: Text('Edit announcement'),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('Delete announcement'),
                    ),
                  ],
                ),
              const SizedBox(width: 8),
            ],
          ),
          subtitle: widget.announcement.imageUrl == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        widget.announcement.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: appSurfaceAlt,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: appSubtleText,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
          children: [
            if (widget.announcement.updatedAt.isAfter(
              widget.announcement.createdAt,
            )) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Last updated ${_formatAnnouncementDate(widget.announcement.updatedAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: appSubtleText,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.announcement.description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: appMutedText,
                  height: 1.55,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _AnnouncementMetricButton(
                  icon: widget.announcement.likedByMe
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label: '${widget.announcement.likeCount} likes',
                  accent: widget.announcement.likedByMe
                      ? appDanger
                      : appPrimary,
                  onTap: widget.onToggleLike,
                ),
                _AnnouncementStaticPill(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: '${widget.announcement.commentCount} comments',
                ),
              ],
            ),
            const SizedBox(height: 18),
            _AnnouncementCommentComposer(
              controller: _commentController,
              isSubmitting: _commentSubmitting,
              onSubmit: _submitComment,
            ),
            if (widget.announcement.comments.isNotEmpty) ...[
              const SizedBox(height: 18),
              for (final (index, comment)
                  in widget.announcement.comments.indexed) ...[
                _AnnouncementCommentCard(
                  comment: comment,
                  onEdit: () => _promptEditComment(comment),
                  onDelete: () => widget.onDeleteComment(comment),
                ),
                if (index < widget.announcement.comments.length - 1)
                  const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _submitComment() async {
    final body = _commentController.text.trim();
    if (body.isEmpty || _commentSubmitting) {
      return;
    }
    setState(() => _commentSubmitting = true);
    try {
      await widget.onCreateComment(body);
      _commentController.clear();
    } finally {
      if (mounted) {
        setState(() => _commentSubmitting = false);
      }
    }
  }

  Future<void> _promptEditComment(AnnouncementComment comment) async {
    final controller = TextEditingController(text: comment.body);
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AppFormDialog(
        title: 'Edit comment',
        fitContent: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
        child: TextField(
          controller: controller,
          maxLines: 4,
          style: const TextStyle(color: appText),
          decoration: const InputDecoration(
            hintText: 'Update your comment',
            hintStyle: TextStyle(color: appSubtleText),
          ),
        ),
      ),
    );
    controller.dispose();
    if (saved == null || saved.isEmpty) {
      return;
    }
    await widget.onEditComment(comment, saved);
  }
}

class _AnnouncementMetricButton extends StatelessWidget {
  const _AnnouncementMetricButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: accent.withOpacity(0.12),
            border: Border.all(color: accent.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: appText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnouncementStaticPill extends StatelessWidget {
  const _AnnouncementStaticPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: appSurfaceAlt,
        border: Border.all(color: appBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: appSubtleText),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: appText, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementCommentComposer extends StatelessWidget {
  const _AnnouncementCommentComposer({
    required this.controller,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool isSubmitting;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: appSurfaceAlt,
        border: Border.all(color: appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            style: const TextStyle(color: appText),
            decoration: const InputDecoration(
              hintText: 'Add a comment',
              hintStyle: TextStyle(color: appSubtleText),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: isSubmitting ? null : onSubmit,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              icon: isSubmitting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: const Text('Post'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementCommentCard extends StatelessWidget {
  const _AnnouncementCommentCard({
    required this.comment,
    required this.onEdit,
    required this.onDelete,
  });

  final AnnouncementComment comment;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: appSurfaceAlt,
        border: Border.all(color: appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comment.authorName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatAnnouncementDate(comment.updatedAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: appSubtleText,
                      ),
                    ),
                  ],
                ),
              ),
              if (comment.canManage)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, color: appSubtleText),
                  color: appSurface,
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit();
                    } else if (value == 'delete') {
                      onDelete();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: Text('Edit comment'),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('Delete comment'),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            comment.body,
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

String _formatAnnouncementDate(DateTime value) {
  final local = value.toLocal();
  final month = switch (local.month) {
    1 => 'Jan',
    2 => 'Feb',
    3 => 'Mar',
    4 => 'Apr',
    5 => 'May',
    6 => 'Jun',
    7 => 'Jul',
    8 => 'Aug',
    9 => 'Sep',
    10 => 'Oct',
    11 => 'Nov',
    _ => 'Dec',
  };
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} $month · $hour:$minute';
}
