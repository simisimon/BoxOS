import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_form_dialog.dart';
import 'package:app/core/presentation/app_side_panel.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/announcements/data/repositories/api_announcement_repository.dart';
import 'package:app/features/announcements/domain/models/announcement.dart';
import 'package:app/features/announcements/presentation/widgets/announcement_composer_dialog.dart';
import 'package:app/features/community/presentation/screens/community_screen.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:app/features/members/presentation/widgets/member_roster.dart'
    show formatShortDate;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Messages page (docs/admin-ui-reference.md §5). Owners and trainers get
/// Announcements
/// (a searchable list beside a reading pane; Compose and Edit open the
/// composer panel) and Chat (the box chat, moved here from Community). BoxOS has no per-recipient read state or
/// e-mail delivery, so there is no recipients dialog.
class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  List<Announcement>? _messages;
  String? _error;
  int? _selectedId;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final messages = await ref
          .read(announcementRepositoryProvider)
          .fetchAnnouncements();
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = errorMessageFrom(error, fallback: 'Try again'));
    }
  }

  Future<void> _compose([Announcement? existing]) async {
    final saved = await showAppSidePanel<bool>(
      context,
      builder: (_) => AnnouncementComposerDialog(
        existing: existing,
        repository: ref.read(announcementRepositoryProvider),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _delete(Announcement message) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Delete message',
      message: 'Delete "${message.title}"? This can’t be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    await _run(
      () => ref
          .read(announcementRepositoryProvider)
          .deleteAnnouncement(id: message.id),
      'Failed to delete message',
    );
  }

  Future<void> _deleteComment(AnnouncementComment comment) => _run(
    () => ref
        .read(announcementRepositoryProvider)
        .deleteComment(commentId: comment.id),
    'Comment could not be deleted.',
  );

  Future<void> _run(Future<void> Function() action, String failed) async {
    try {
      await action();
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessageFrom(error, fallback: failed))),
      );
    }
  }

  /// Announcements | Chat: owners post news and talk with members here.
  bool _chat = false;

  @override
  Widget build(BuildContext context) {
    // Athletes read announcements on Home; Messages is just the box chat.
    final role = ref.watch(currentProfileProvider).value?.role;
    if (role == UserRole.athlete) {
      return const CommunityScreen(chatOnly: true);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            appSpaceLg,
            appSpaceLg,
            appSpaceLg,
            0,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.campaign_outlined),
                  label: Text('Announcements'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.forum_outlined),
                  label: Text('Chat'),
                ),
              ],
              selected: {_chat},
              onSelectionChanged: (s) => setState(() => _chat = s.first),
            ),
          ),
        ),
        Expanded(
          child: _chat
              ? const CommunityScreen(chatOnly: true)
              : _buildAnnouncements(context),
        ),
      ],
    );
  }

  Widget _buildAnnouncements(BuildContext context) {
    final messages = _messages;
    if (messages == null) {
      return _error == null
          ? const AppLoadingState()
          : Padding(
              padding: const EdgeInsets.all(appSpaceLg),
              child: AppEmptyState.error(
                title: 'Could not load messages',
                subtitle: _error,
                actionLabel: 'Retry',
                onAction: _load,
              ),
            );
    }
    final query = _query.trim().toLowerCase();
    final visible = [
      for (final m in messages)
        if (query.isEmpty ||
            m.title.toLowerCase().contains(query) ||
            m.description.toLowerCase().contains(query))
          m,
    ];
    final selected =
        visible.where((m) => m.id == _selectedId).firstOrNull ??
        visible.firstOrNull;

    return Padding(
      padding: const EdgeInsets.all(appSpaceLg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final list = _MessageList(
            messages: visible,
            total: messages.length,
            selectedId: wide ? selected?.id : null,
            onQuery: (value) => setState(() => _query = value),
            onCompose: _compose,
            onOpen: (message) {
              setState(() => _selectedId = message.id);
              if (!wide) {
                showAppSidePanel<void>(
                  context,
                  builder: (panelContext) => AppSidePanel(
                    title: message.title,
                    bodyPadding: EdgeInsets.zero,
                    // The panel's menu closes the panel itself first.
                    menu: [
                      if (message.canManage) ...[
                        ('Edit', () => _compose(message)),
                        ('Delete', () => _delete(message)),
                      ],
                    ],
                    child: _ReadingPane(
                      message: message,
                      onEdit: () {},
                      onDelete: () {},
                      // Close first: the panel shows a snapshot that would
                      // keep the deleted comment.
                      onDeleteComment: (comment) {
                        Navigator.of(panelContext).pop();
                        _deleteComment(comment);
                      },
                    ),
                  ),
                );
              }
            },
          );
          if (!wide) return list;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 360, child: list),
              const SizedBox(width: appSpaceMd),
              Expanded(
                child: Container(
                  decoration: _panel(),
                  child: selected == null
                      ? const AppEmptyState(
                          icon: Icons.mail_outline_rounded,
                          title: 'No message selected',
                          compact: true,
                        )
                      : SingleChildScrollView(
                          key: ValueKey(selected.id),
                          child: _ReadingPane(
                            message: selected,
                            onEdit: () => _compose(selected),
                            onDelete: () => _delete(selected),
                            onDeleteComment: _deleteComment,
                            showTitle: true,
                          ),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

BoxDecoration _panel() => BoxDecoration(
  color: appSurface,
  borderRadius: BorderRadius.circular(appRadiusLg),
  border: Border.all(color: appBorder),
);

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.total,
    required this.selectedId,
    required this.onQuery,
    required this.onCompose,
    required this.onOpen,
  });

  final List<Announcement> messages;
  final int total;
  final int? selectedId;
  final ValueChanged<String> onQuery;
  final VoidCallback onCompose;
  final ValueChanged<Announcement> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _panel(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(appSpaceMd),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: onQuery,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Search by subject',
                      prefixIcon: Icon(Icons.search_rounded, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: appSpaceSm),
                IconButton.filled(
                  onPressed: onCompose,
                  tooltip: 'Compose',
                  style: IconButton.styleFrom(
                    backgroundColor: appPrimary,
                    foregroundColor: appInverseText,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(appRadiusSm),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: appBorder),
          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Text(
                      'No messages yet.',
                      style: TextStyle(color: appSubtleText),
                    ),
                  )
                : ListView.separated(
                    itemCount: messages.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: appBorder),
                    itemBuilder: (context, index) {
                      final m = messages[index];
                      return Material(
                        color: m.id == selectedId
                            ? appPrimarySoft
                            : Colors.transparent,
                        child: InkWell(
                          onTap: () => onOpen(m),
                          child: Padding(
                            padding: const EdgeInsets.all(appSpaceMd),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${m.likeCount} likes · '
                                        '${m.commentCount} comments',
                                        style: const TextStyle(
                                          color: appSubtleText,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      formatShortDate(m.createdAt),
                                      style: const TextStyle(
                                        color: appSubtleText,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: appSpaceXs),
                                Text(
                                  m.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
                    },
                  ),
          ),
          const Divider(height: 1, color: appBorder),
          Padding(
            padding: const EdgeInsets.all(appSpaceMd),
            child: Text(
              '${messages.length} of $total messages',
              style: const TextStyle(color: appSubtleText, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// One message: subject, author and time, image, body, then its comments
/// (deletable by managers).
class _ReadingPane extends StatelessWidget {
  const _ReadingPane({
    required this.message,
    required this.onEdit,
    required this.onDelete,
    required this.onDeleteComment,
    this.showTitle = false,
  });

  final Announcement message;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<AnnouncementComment> onDeleteComment;

  /// The side panel already shows the subject in its header.
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    String stamp(DateTime t) =>
        '${localizations.formatMediumDate(t.toLocal())} · '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal()))}';
    return Padding(
      padding: const EdgeInsets.all(appSpaceXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: showTitle
                    ? Text(
                        message.title,
                        style: const TextStyle(
                          color: appText,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              // In the phone panel the panel's own ⋯ menu has these.
              if (message.canManage && showTitle)
                PopupMenuButton<String>(
                  tooltip: 'Message actions',
                  color: appSurfaceElevated,
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: appMutedText,
                  ),
                  onSelected: (value) =>
                      value == 'edit' ? onEdit() : onDelete(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: appSpaceSm),
          Wrap(
            spacing: appSpaceSm,
            runSpacing: appSpaceXs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const AppPill(label: 'To: All members', dense: true),
              Text(
                '${message.authorName} · ${stamp(message.createdAt)}',
                style: const TextStyle(color: appSubtleText, fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: appSpaceLg),
          if (message.imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(appRadiusMd),
              child: Image.network(
                message.imageUrl!,
                height: 220,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: appSpaceLg),
          ],
          SelectableText(
            message.description,
            style: const TextStyle(color: appText, height: 1.5),
          ),
          const SizedBox(height: appSpace2xl),
          Text(
            'Comments ${message.comments.length} · Likes ${message.likeCount}',
            style: appMono(fontSize: 10),
          ),
          const SizedBox(height: appSpaceSm),
          for (final comment in message.comments)
            Container(
              padding: const EdgeInsets.symmetric(vertical: appSpaceSm),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: appBorder)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          comment.authorName,
                          style: const TextStyle(
                            color: appText,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          comment.body,
                          style: const TextStyle(color: appMutedText),
                        ),
                      ],
                    ),
                  ),
                  if (comment.canManage)
                    IconButton(
                      tooltip: 'Delete comment',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onDeleteComment(comment),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: appSubtleText,
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
