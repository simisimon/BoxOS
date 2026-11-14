import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/app_side_panel.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/results/data/api_follows_repository.dart';
import 'package:app/features/results/data/api_results_repository.dart';
import 'package:app/features/results/domain/workout_result.dart';
import 'package:app/features/results/presentation/block_leaderboard.dart';
import 'package:app/features/results/presentation/result_detail_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The link that opens the Friends tab with a follow request to [code]
/// ready (`#/whiteboard?tab=friends&follow=CODE`).
String followInviteLink(String code) {
  final base = Uri.base;
  final origin = base.hasAuthority ? '${base.scheme}://${base.authority}' : '';
  return '$origin${base.path}#/whiteboard?tab=friends&follow=$code';
}

/// Whiteboard › Friends: results of the people the athlete follows, newest
/// first. [followCode] comes from an invite link and asks to follow.
class FriendsFeed extends ConsumerStatefulWidget {
  const FriendsFeed({super.key, this.followCode});

  final String? followCode;

  @override
  ConsumerState<FriendsFeed> createState() => _FriendsFeedState();
}

class _FriendsFeedState extends ConsumerState<FriendsFeed> {
  final _more = <FeedEntry>[];
  bool? _hasMore;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    final code = widget.followCode;
    if (code != null && code.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showFriendsPanel(context, inviteCode: code);
      });
    }
  }

  void _reload() {
    setState(() {
      _more.clear();
      _hasMore = null;
    });
    ref.invalidate(feedProvider);
  }

  Future<void> _loadMore(int loaded) async {
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(followsRepositoryProvider)
          .fetchFeed(offset: loaded);
      if (!mounted) return;
      setState(() {
        _more.addAll(page.entries);
        _hasMore = page.hasMore;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load more results.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    final requests = ref.watch(followOverviewProvider).value?.requests.length;
    final header = Row(
      children: [
        const Expanded(
          child: Text(
            'Results of the people you follow, at any gym.',
            style: TextStyle(color: appSubtleText, fontSize: 13),
          ),
        ),
        OutlinedButton.icon(
          key: const ValueKey('open-friends'),
          onPressed: () async {
            await showFriendsPanel(context);
            if (mounted) _reload();
          },
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          icon: const Icon(Icons.group_add_outlined, size: 18),
          label: Text(
            requests == null || requests == 0
                ? 'Friends'
                : 'Friends ($requests)',
          ),
        ),
      ],
    );
    final Widget body = feed.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Text(
        errorMessageFrom(error, fallback: 'Could not load the feed.'),
        style: const TextStyle(color: appDanger),
      ),
      data: (page) {
        final entries = [...page.entries, ..._more];
        if (entries.isEmpty) {
          return const _Card(
            child: Text(
              'Nothing here yet. Follow friends from your gym or send them '
              'your invite link under Friends. Their results show up here '
              'when they share them with followers.',
              style: TextStyle(color: appSubtleText),
            ),
          );
        }
        final hasMore = _hasMore ?? page.hasMore;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in entries) ...[
              _FeedCard(entry: entry, onChanged: _reload),
              const SizedBox(height: appSpaceSm),
            ],
            if (hasMore)
              Align(
                child: TextButton(
                  onPressed: _loadingMore
                      ? null
                      : () => _loadMore(entries.length),
                  child: const Text('Load more'),
                ),
              ),
          ],
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: appSpaceMd),
        body,
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(appSpaceLg),
    decoration: BoxDecoration(
      color: appSurface,
      borderRadius: BorderRadius.circular(appRadiusLg),
      border: Border.all(color: appBorder),
    ),
    child: child,
  );
}

class _FeedCard extends ConsumerWidget {
  const _FeedCard({required this.entry, required this.onChanged});

  final FeedEntry entry;
  final VoidCallback onChanged;

  Future<void> _bump(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(resultsRepositoryProvider)
          .setBump(entry.result.id, bumped: !entry.bumpedByMe);
      onChanged();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send the fist bump.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = entry.result;
    final localizations = MaterialLocalizations.of(context);
    const subtle = TextStyle(color: appSubtleText, fontSize: 12);
    final where = result.isPersonal ? 'Logbook' : entry.gymName;
    return Material(
      color: appSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(appRadiusLg),
        side: const BorderSide(color: appBorder),
      ),
      child: InkWell(
        key: ValueKey('feed-${result.id}'),
        borderRadius: BorderRadius.circular(appRadiusLg),
        onTap: () async {
          await showResultDetailPanel(context, resultId: result.id);
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(appSpaceMd),
          child: Row(
            children: [
              AppAvatar(
                displayName: entry.name,
                imageUrl: entry.avatarUrl.isEmpty ? null : entry.avatarUrl,
                size: 36,
              ),
              const SizedBox(width: appSpaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: appText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      result.sectionTitle.isEmpty
                          ? 'Workout'
                          : result.sectionTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: appMutedText),
                    ),
                    Text(
                      [
                        localizations.formatMediumDate(result.performedOn),
                        if (where.isNotEmpty) where,
                      ].join(' · '),
                      style: subtle,
                    ),
                  ],
                ),
              ),
              if (entry.photoUrl.isNotEmpty) ...[
                const Icon(
                  Icons.photo_camera_outlined,
                  size: 16,
                  color: appSubtleText,
                ),
                const SizedBox(width: appSpaceSm),
              ],
              if (entry.commentCount > 0) ...[
                const Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 15,
                  color: appSubtleText,
                ),
                const SizedBox(width: 2),
                Text('${entry.commentCount}', style: subtle),
                const SizedBox(width: appSpaceSm),
              ],
              if (result.isPr) ...[
                const AppPill(
                  label: 'PR',
                  intent: AppPillIntent.warning,
                  dense: true,
                ),
                const SizedBox(width: appSpaceSm),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    result.scoreLabel,
                    style: const TextStyle(
                      color: appText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(result.divisionLabel, style: subtle),
                ],
              ),
              FistBumpButton(
                key: ValueKey('feed-bump-${result.id}'),
                count: entry.bumpCount,
                bumped: entry.bumpedByMe,
                onPressed: () => _bump(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Follow people, answer requests, share the invite link. [inviteCode]
/// (from an invite link) fills in the code field.
Future<void> showFriendsPanel(BuildContext context, {String? inviteCode}) {
  return showAppSidePanel<void>(
    context,
    builder: (_) => FriendsPanel(inviteCode: inviteCode),
  );
}

class FriendsPanel extends ConsumerStatefulWidget {
  const FriendsPanel({super.key, this.inviteCode});

  final String? inviteCode;

  @override
  ConsumerState<FriendsPanel> createState() => _FriendsPanelState();
}

class _FriendsPanelState extends ConsumerState<FriendsPanel> {
  late final _code = TextEditingController(text: widget.inviteCode);
  final _query = TextEditingController();
  List<FollowPerson> _matches = const [];
  bool _busy = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final message = await action();
      ref.invalidate(followOverviewProvider);
      ref.invalidate(feedProvider);
      if (mounted) setState(() => _message = message);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = errorMessageFrom(
            error,
            fallback: 'Something went wrong.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _sentMessage(FollowStatus status) => status == FollowStatus.accepted
      ? 'You already follow them.'
      : 'Request sent. You follow them once they accept.';

  Future<void> _followByCode() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    await _run(() async {
      final status = await ref
          .read(followsRepositoryProvider)
          .follow(inviteCode: code);
      _code.clear();
      return _sentMessage(status);
    });
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      setState(() => _matches = const []);
      return;
    }
    try {
      final people = await ref
          .read(followsRepositoryProvider)
          .search(query.trim());
      if (mounted && _query.text == query) setState(() => _matches = people);
    } catch (_) {
      if (mounted) setState(() => _matches = const []);
    }
  }

  Future<void> _followPerson(FollowPerson person) => _run(() async {
    final status = await ref
        .read(followsRepositoryProvider)
        .follow(userId: person.userId);
    await _search(_query.text);
    return _sentMessage(status);
  });

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: appSpaceXl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: appMono(fontSize: 10)),
        const SizedBox(height: appSpaceSm),
        ...children,
      ],
    ),
  );

  Widget _person(FollowPerson person, List<Widget> actions, {Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: appSpaceXs),
      child: Row(
        children: [
          AppAvatar(
            displayName: person.name,
            imageUrl: person.avatarUrl.isEmpty ? null : person.avatarUrl,
            size: 32,
          ),
          const SizedBox(width: appSpaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: appText),
                ),
                if (person.gymName.isNotEmpty)
                  Text(
                    person.gymName,
                    style: const TextStyle(color: appSubtleText, fontSize: 12),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(followOverviewProvider);
    final data = overview.value;
    final repo = ref.read(followsRepositoryProvider);
    return AppSidePanel(
      title: 'Friends',
      subtitle: 'Follow athletes at any gym',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_message != null)
            Text(_message!, style: const TextStyle(color: appPrimary)),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: appDanger)),
          if (overview.isLoading && data == null)
            const LinearProgressIndicator(),
          if (data != null && data.requests.isNotEmpty)
            _section('REQUESTS', [
              for (final person in data.requests)
                _person(person, key: ValueKey('request-${person.userId}'), [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await repo.removeFollower(person.userId);
                            return null;
                          }),
                    child: const Text('Decline'),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await repo.accept(person.userId);
                            return '${person.name} now follows you.';
                          }),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 36),
                    ),
                    child: const Text('Accept'),
                  ),
                ]),
            ]),
          _section('FIND PEOPLE AT YOUR GYM', [
            TextField(
              key: const ValueKey('friends-search'),
              controller: _query,
              onChanged: _search,
              decoration: const InputDecoration(
                hintText: 'Search by name',
                prefixIcon: Icon(Icons.search_rounded, size: 18),
              ),
            ),
            for (final person in _matches)
              _person(person, [
                if (person.status == FollowStatus.none)
                  TextButton(
                    onPressed: _busy ? null : () => _followPerson(person),
                    child: const Text('Follow'),
                  )
                else
                  Text(
                    person.status == FollowStatus.pending
                        ? 'Requested'
                        : 'Following',
                    style: const TextStyle(color: appSubtleText, fontSize: 12),
                  ),
              ]),
          ]),
          _section('FOLLOW BY INVITE CODE', [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('friends-code'),
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      hintText: 'e.g. K7QM2XPA',
                    ),
                    onSubmitted: (_) => _followByCode(),
                  ),
                ),
                const SizedBox(width: appSpaceSm),
                FilledButton(
                  onPressed: _busy ? null : _followByCode,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  child: const Text('Follow'),
                ),
              ],
            ),
          ]),
          if (data != null)
            _section('YOUR INVITE LINK', [
              Text(
                'Friends at other gyms follow you with this link or code. '
                'You accept each request.',
                style: const TextStyle(color: appSubtleText, fontSize: 12),
              ),
              const SizedBox(height: appSpaceSm),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      data.inviteCode,
                      style: appMono(fontSize: 16, color: appText),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(
                        ClipboardData(text: followInviteLink(data.inviteCode)),
                      );
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Invite link copied.')),
                      );
                    },
                    icon: const Icon(Icons.link_rounded, size: 18),
                    label: const Text('Copy link'),
                  ),
                ],
              ),
            ]),
          if (data != null && data.sent.isNotEmpty)
            _section('WAITING FOR AN ANSWER', [
              for (final person in data.sent)
                _person(person, [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await repo.unfollow(person.userId);
                            return null;
                          }),
                    child: const Text('Withdraw'),
                  ),
                ]),
            ]),
          if (data != null)
            _section('FOLLOWING (${data.following.length})', [
              if (data.following.isEmpty)
                const Text(
                  'You don\'t follow anyone yet.',
                  style: TextStyle(color: appSubtleText),
                ),
              for (final person in data.following)
                _person(person, key: ValueKey('following-${person.userId}'), [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await repo.unfollow(person.userId);
                            return null;
                          }),
                    child: const Text('Unfollow'),
                  ),
                ]),
            ]),
          if (data != null)
            _section('FOLLOWERS (${data.followers.length})', [
              if (data.followers.isEmpty)
                const Text(
                  'Nobody follows you yet.',
                  style: TextStyle(color: appSubtleText),
                ),
              for (final person in data.followers)
                _person(person, [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await repo.removeFollower(person.userId);
                            return null;
                          }),
                    child: const Text('Remove'),
                  ),
                ]),
            ]),
        ],
      ),
    );
  }
}
