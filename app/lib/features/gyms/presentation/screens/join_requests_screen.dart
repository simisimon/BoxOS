import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/core/presentation/responsive/breakpoints.dart';
import 'package:app/core/presentation/responsive/responsive_masonry.dart';
import 'package:app/features/gyms/data/repositories/api_gym_repository.dart';
import 'package:app/features/gyms/domain/models/gym_join_request.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class JoinRequestsScreen extends ConsumerStatefulWidget {
  const JoinRequestsScreen({super.key});

  @override
  ConsumerState<JoinRequestsScreen> createState() => _JoinRequestsScreenState();
}

class _JoinRequestsScreenState extends ConsumerState<JoinRequestsScreen> {
  int? _pendingRequestId;

  Future<void> _review(GymJoinRequest request, bool approve) async {
    setState(() => _pendingRequestId = request.id);
    try {
      await ref
          .read(gymRepositoryProvider)
          .reviewJoinRequest(requestId: request.id, approve: approve);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? 'Approved ${request.email}.'
                : 'Rejected ${request.email}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessageFrom(error, fallback: 'Review failed')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _pendingRequestId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final hasAccess =
        profile?.role == UserRole.admin && profile?.activeGym != null;

    return AppMobileScaffold(
      title: 'Join Requests',
      eyebrow: 'Membership',
      maxWidth: context.dashboardMaxWidth,
      body: profileAsync.when(
        loading: () => const AppLoadingState(),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(appSpaceLg),
          child: AppEmptyState.error(
            title: 'Failed to load profile',
            subtitle: errorMessageFrom(error, fallback: ''),
          ),
        ),
        data: (_) {
          if (!hasAccess) {
            return Padding(
              padding: const EdgeInsets.all(appSpaceLg),
              child: AppEmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Admin access required',
                subtitle:
                    'You need an active admin gym to review join requests.',
              ),
            );
          }

          return FutureBuilder<List<GymJoinRequest>>(
            future: ref.read(gymRepositoryProvider).fetchJoinRequests(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const AppLoadingState();
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(appSpaceLg),
                  child: AppEmptyState.error(
                    title: 'Failed to load join requests',
                    subtitle: errorMessageFrom(
                      snapshot.error ?? Exception('Unknown error'),
                      fallback: '',
                    ),
                  ),
                );
              }
              final requests = snapshot.data ?? const [];
              if (requests.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(appSpaceLg),
                  child: AppEmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'No pending join requests',
                    subtitle:
                        'New athletes asking to join your box will appear here.',
                  ),
                );
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.all(appSpaceLg),
                child: ResponsiveMasonry(
                  minColumnWidth: 320,
                  maxColumns: 3,
                  spacing: appSpaceMd,
                  children: [
                    for (final request in requests)
                      _RequestCard(
                        request: request,
                        isPending: _pendingRequestId == request.id,
                        onApprove: () => _review(request, true),
                        onReject: () => _review(request, false),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.isPending,
    required this.onApprove,
    required this.onReject,
  });

  final GymJoinRequest request;
  final bool isPending;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName =
        request.displayName.isEmpty ? request.email : request.displayName;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppAccentBadge(
                icon: Icons.person_outline_rounded,
                color: appPrimary,
              ),
              const SizedBox(width: appSpaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      request.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: appSubtleText,
                      ),
                    ),
                    if (request.nickname.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@${request.nickname}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: appMutedText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: appSpaceLg),
          Row(
            children: [
              Expanded(
                child: AppSecondaryButton(
                  label: 'Reject',
                  onPressed: isPending ? null : onReject,
                  size: AppButtonSize.md,
                  busy: isPending,
                ),
              ),
              const SizedBox(width: appSpaceSm),
              Expanded(
                child: AppPrimaryButton(
                  label: 'Approve',
                  onPressed: isPending ? null : onApprove,
                  size: AppButtonSize.md,
                  busy: isPending,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
