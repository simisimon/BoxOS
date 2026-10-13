import 'dart:async';

import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/core/presentation/responsive/breakpoints.dart';
import 'package:app/features/community/data/repositories/api_community_repository.dart';
import 'package:app/features/community/domain/models/chat_message.dart';
import 'package:app/features/community/domain/models/community_dashboard.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _pollInterval = Duration(seconds: 10);

class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _input = TextEditingController();
  Timer? _pollTimer;
  Future<CommunityDashboard>? _dashboardFuture;
  int? _dashboardGymId;
  bool _initialLoadComplete = false;
  Object? _loadError;
  bool _sending = false;
  int? _lastSeenId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialLoad());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollController.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _initialLoad() async {
    try {
      final messages = await ref
          .read(communityRepositoryProvider)
          .fetchMessages();
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(messages);
        _lastSeenId = messages.isEmpty ? null : messages.last.id;
        _initialLoadComplete = true;
        _loadError = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(animate: false);
      });
      _startPolling();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _initialLoadComplete = true;
      });
    }
  }

  Future<CommunityDashboard> _loadDashboard() {
    return ref.read(communityRepositoryProvider).fetchDashboard();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    if (!mounted) return;
    final since = _lastSeenId;
    try {
      final fresh = await ref
          .read(communityRepositoryProvider)
          .fetchMessages(sinceId: since);
      if (!mounted || fresh.isEmpty) return;
      _mergeMessages(fresh);
    } catch (_) {
      // Polling errors stay silent; the user already has the previous data and
      // the next tick will retry. A persistent failure surfaces when they hit
      // pull-to-refresh.
    }
  }

  void _mergeMessages(List<ChatMessage> incoming) {
    final wasAtBottom = _isAtBottom();
    setState(() {
      for (final message in incoming) {
        final existingIndex = _messages.indexWhere((m) => m.id == message.id);
        if (existingIndex >= 0) {
          _messages[existingIndex] = message;
        } else {
          _messages.add(message);
        }
        if (_lastSeenId == null || message.id > _lastSeenId!) {
          _lastSeenId = message.id;
        }
      }
    });
    if (wasAtBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(animate: true);
      });
    }
  }

  bool _isAtBottom() {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.pixels >= position.maxScrollExtent - 80;
  }

  void _scrollToBottom({required bool animate}) {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(
        maxScroll,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(maxScroll);
    }
  }

  Future<void> _refresh() async {
    final profileAsync = ref.read(currentProfileProvider);
    final activeGym = profileAsync.hasValue
        ? profileAsync.value?.activeGym
        : null;
    if (activeGym == null) {
      await _initialLoad();
      return;
    }
    setState(() {
      _dashboardGymId = activeGym.id;
      _dashboardFuture = _loadDashboard();
    });
    await Future.wait([_dashboardFuture!, _initialLoad()]);
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final created = await ref
          .read(communityRepositoryProvider)
          .sendMessage(body: body);
      if (!mounted) return;
      _input.clear();
      _mergeMessages([created]);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(animate: true);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessageFrom(error, fallback: 'Failed to send')),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text(
          'The message will be removed for everyone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(communityRepositoryProvider).deleteMessage(id: message.id);
      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere((m) => m.id == message.id);
        if (index >= 0) {
          _messages[index] = ChatMessage(
            id: message.id,
            body: '',
            createdAt: message.createdAt,
            deletedAt: DateTime.now(),
            isOwn: message.isOwn,
            senderId: message.senderId,
            senderDisplayName: message.senderDisplayName,
            senderNickname: message.senderNickname,
          );
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to delete message'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    if (profileAsync.isLoading && !profileAsync.hasValue) {
      return const Material(color: appPageBackground, child: AppLoadingState());
    }
    if (profileAsync.hasError && !profileAsync.hasValue) {
      return Material(
        color: appPageBackground,
        child: Padding(
          padding: const EdgeInsets.all(appSpaceLg),
          child: AppEmptyState.error(
            title: 'Could not load community',
            subtitle: errorMessageFrom(
              profileAsync.error!,
              fallback: 'Profile data could not be loaded.',
            ),
          ),
        ),
      );
    }
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final activeGym = profile?.activeGym;
    final isModerator =
        profile?.role == UserRole.admin || profile?.role == UserRole.trainer;
    final gymName = activeGym?.name ?? '';
    if (activeGym != null &&
        (_dashboardFuture == null || _dashboardGymId != activeGym.id)) {
      _dashboardGymId = activeGym.id;
      _dashboardFuture = _loadDashboard();
    }

    return Material(
      color: appPageBackground,
      child: SafeArea(
        top: false,
        bottom: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = context.dashboardMaxWidth;
            final horizontalPadding = constraints.maxWidth > maxWidth
                ? (constraints.maxWidth - maxWidth) / 2
                : 0.0;
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: _CommunityHeader(gymName: gymName),
                  ),
                  Expanded(
                    child: activeGym == null
                        ? const _NoActiveGymState()
                        : RefreshIndicator(
                            onRefresh: _refresh,
                            child: _buildCommunityList(
                              activeGymId: activeGym.id,
                              isModerator: isModerator,
                            ),
                          ),
                  ),
                  _Composer(
                    controller: _input,
                    sending: _sending,
                    enabled: activeGym != null,
                    onSend: _send,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCommunityList({
    required int activeGymId,
    required bool isModerator,
  }) {
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: FutureBuilder<CommunityDashboard>(
          future: _dashboardFuture!,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const _DashboardLoading();
            }
            if (snapshot.hasError && !snapshot.hasData) {
              return _DashboardError(
                message: errorMessageFrom(
                  snapshot.error!,
                  fallback: 'Failed to load community stats',
                ),
                onRetry: () => setState(() {
                  _dashboardGymId = activeGymId;
                  _dashboardFuture = _loadDashboard();
                }),
              );
            }
            return _CommunityDashboardPanel(dashboard: snapshot.data!);
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: _ChatHeader(
          memberCount: _messages.length,
          loading: !_initialLoadComplete,
        ),
      ),
      ..._buildMessageItems(isModerator),
      const SizedBox(height: appSpaceSm),
    ];
    return ListView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: children,
    );
  }

  List<Widget> _buildMessageItems(bool isModerator) {
    if (!_initialLoadComplete) {
      return const [
        SizedBox(
          height: 140,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_loadError != null) {
      return [
        Padding(
          padding: const EdgeInsets.all(16),
          child: _CommunityStateCard(
            icon: Icons.error_outline,
            title: 'Failed to load messages',
            message: errorMessageFrom(
              _loadError!,
              fallback: 'Failed to load messages',
            ),
          ),
        ),
      ];
    }
    if (_messages.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(16),
          child: _CommunityStateCard(
            icon: Icons.forum_outlined,
            title: 'Be the first to say hi',
            message: 'No messages yet — start the conversation.',
          ),
        ),
      ];
    }
    return [
      for (final message in _messages)
        _MessageBubble(
          message: message,
          canModerate: isModerator || message.isOwn,
          onDelete: () => _deleteMessage(message),
        ),
    ];
  }
}

class _CommunityHeader extends StatelessWidget {
  const _CommunityHeader({required this.gymName});

  final String gymName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const AppAccentBadge(icon: Icons.groups_2_outlined, size: 42),
        const SizedBox(width: appSpaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Community',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: appText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                gymName.isEmpty ? 'Box chat' : gymName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: appSubtleText,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommunityDashboardPanel extends StatelessWidget {
  const _CommunityDashboardPanel({required this.dashboard});

  final CommunityDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    return AppCard.elevated(
      padding: const EdgeInsets.all(appSpaceLg),
      child: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: _StatsGrid(stats: dashboard.stats)),
                const SizedBox(width: appSpaceLg),
                Expanded(flex: 4, child: _NewestPrs(prs: dashboard.newestPrs)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StatsGrid(stats: dashboard.stats),
                const SizedBox(height: appSpaceLg),
                _NewestPrs(prs: dashboard.newestPrs),
              ],
            ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final CommunityStats stats;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 3 : 2;
    final metrics = [
      _CommunityMetric(
        label: 'Members',
        value: stats.activeMembers.toString(),
        icon: Icons.group_outlined,
        color: appPrimary,
      ),
      _CommunityMetric(
        label: 'Trainer',
        value: stats.activeTrainers.toString(),
        icon: Icons.sports_outlined,
        color: appInfo,
      ),
      _CommunityMetric(
        label: 'Owner',
        value: stats.owners.toString(),
        icon: Icons.admin_panel_settings_outlined,
        color: appWarning,
      ),
      _CommunityMetric(
        label: 'PRs 30d',
        value: stats.prsLast30Days.toString(),
        icon: Icons.emoji_events_outlined,
        color: appSuccess,
      ),
      _CommunityMetric(
        label: 'Chat 7d',
        value: stats.messagesLast7Days.toString(),
        icon: Icons.forum_outlined,
        color: appPrimary,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PanelTitle(
          icon: Icons.query_stats_rounded,
          title: 'Box Statistics',
        ),
        const SizedBox(height: appSpaceMd),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: metrics.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: appSpaceMd,
            mainAxisSpacing: appSpaceMd,
            mainAxisExtent: 86,
          ),
          itemBuilder: (context, index) => metrics[index],
        ),
      ],
    );
  }
}

class _CommunityMetric extends StatelessWidget {
  const _CommunityMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppCard.inset(
      padding: const EdgeInsets.all(appSpaceMd),
      child: Row(
        children: [
          AppAccentBadge(icon: icon, color: color, size: 36),
          const SizedBox(width: appSpaceMd),
          Expanded(
            child: AppMetric(label: label, value: value, valueSize: 22),
          ),
        ],
      ),
    );
  }
}

class _NewestPrs extends StatelessWidget {
  const _NewestPrs({required this.prs});

  final List<CommunityPr> prs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PanelTitle(
          icon: Icons.workspace_premium_outlined,
          title: 'Newest PRs',
        ),
        const SizedBox(height: appSpaceMd),
        if (prs.isEmpty)
          const AppEmptyState(
            icon: Icons.emoji_events_outlined,
            title: 'No PRs yet',
            subtitle: 'New member records appear here as soon as they log one.',
            compact: true,
          )
        else
          Column(
            children: [
              for (var index = 0; index < prs.length; index++) ...[
                _PrRow(pr: prs[index]),
                if (index != prs.length - 1) const SizedBox(height: appSpaceSm),
              ],
            ],
          ),
      ],
    );
  }
}

class _PrRow extends StatelessWidget {
  const _PrRow({required this.pr});

  final CommunityPr pr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard.inset(
      padding: const EdgeInsets.all(appSpaceMd),
      child: Row(
        children: [
          const AppAccentBadge(
            icon: Icons.emoji_events_outlined,
            color: appSuccess,
            size: 38,
          ),
          const SizedBox(width: appSpaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pr.memberLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: appText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  pr.workoutTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: appSubtleText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: appSpaceMd),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                pr.scoreLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: appSuccess,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatRelativeDate(pr.updatedAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: appSubtleText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: appPrimary, size: 18),
        const SizedBox(width: appSpaceSm),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: appText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();

  @override
  Widget build(BuildContext context) {
    return const AppCard.elevated(child: AppLoadingState(height: 180));
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState.error(
      title: 'Could not load dashboard',
      subtitle: message,
      actionLabel: 'Retry',
      onAction: onRetry,
      compact: true,
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.memberCount, required this.loading});

  final int memberCount;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.chat_bubble_outline_rounded, color: appPrimary, size: 18),
        const SizedBox(width: appSpaceSm),
        Expanded(
          child: Text(
            'Community Chat',
            style: theme.textTheme.titleMedium?.copyWith(
              color: appText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Text(
          loading ? 'Loading' : '$memberCount messages',
          style: theme.textTheme.labelMedium?.copyWith(
            color: appSubtleText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _NoActiveGymState extends StatelessWidget {
  const _NoActiveGymState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _CommunityStateCard(
          icon: Icons.store_mall_directory_outlined,
          title: 'No active gym',
          message:
              'Join or switch to a gym to chat with your community. Without '
              'an active gym there is no channel to read or write to.',
        ),
      ],
    );
  }
}

class _CommunityStateCard extends StatelessWidget {
  const _CommunityStateCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(6),
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
                const SizedBox(height: 6),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: appSubtleText,
                    height: 1.4,
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.canModerate,
    required this.onDelete,
  });

  final ChatMessage message;
  final bool canModerate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleColor = message.isOwn ? appPrimary : appSurfaceAlt;
    final bodyColor = message.isOwn ? Colors.white : appText;
    final alignment = message.isOwn
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final timeLabel = _formatTime(message.createdAt);
    final showActions = canModerate && !message.isDeleted;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          if (!message.isOwn)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 2),
              child: Text(
                message.senderLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: appSubtleText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          GestureDetector(
            onLongPress: showActions ? onDelete : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.72,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(6),
                    topRight: const Radius.circular(6),
                    bottomLeft: Radius.circular(message.isOwn ? 18 : 4),
                    bottomRight: Radius.circular(message.isOwn ? 4 : 18),
                  ),
                  border: Border.all(color: appBorder),
                ),
                child: message.isDeleted
                    ? Text(
                        'Message deleted',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: appSubtleText,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    : Text(
                        message.body,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: bodyColor,
                          height: 1.35,
                        ),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 6, right: 6),
            child: Text(
              timeLabel,
              style: theme.textTheme.labelSmall?.copyWith(color: appSubtleText),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime value) {
    final now = DateTime.now();
    final isSameDay =
        value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    if (isSameDay) return '$hh:$mm';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day.$month $hh:$mm';
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final inputEnabled = enabled && !sending;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: appBorder)),
        color: appSurface,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: inputEnabled,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: enabled ? 'Write a message…' : 'Join a gym to chat',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox.square(
            dimension: 44,
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size.square(44),
                fixedSize: const Size.square(44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: inputEnabled ? onSend : null,
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatRelativeDate(DateTime value) {
  final now = DateTime.now();
  final difference = now.difference(value);
  if (difference.inDays <= 0) return 'Today';
  if (difference.inDays == 1) return 'Yesterday';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day.$month';
}
