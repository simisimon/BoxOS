import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/mobile_content.dart';
import 'package:app/features/gyms/data/repositories/api_gym_repository.dart';
import 'package:app/features/gyms/domain/models/gym_join_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class JoinRequestsScreen extends ConsumerStatefulWidget {
  const JoinRequestsScreen({super.key});

  @override
  ConsumerState<JoinRequestsScreen> createState() => _JoinRequestsScreenState();
}

class _JoinRequestsScreenState extends ConsumerState<JoinRequestsScreen> {
  late Future<List<GymJoinRequest>> _requestsFuture;
  int? _pendingRequestId;

  @override
  void initState() {
    super.initState();
    _requestsFuture = ref.read(gymRepositoryProvider).fetchJoinRequests();
  }

  Future<void> _review(GymJoinRequest request, bool approve) async {
    setState(() => _pendingRequestId = request.id);
    try {
      await ref
          .read(gymRepositoryProvider)
          .reviewJoinRequest(requestId: request.id, approve: approve);
      if (!mounted) {
        return;
      }
      setState(() {
        _requestsFuture = ref.read(gymRepositoryProvider).fetchJoinRequests();
      });
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
    return Scaffold(
      appBar: AppBar(title: const Text('Join Requests')),
      body: FutureBuilder<List<GymJoinRequest>>(
        future: _requestsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                errorMessageFrom(
                  snapshot.error ?? Exception('Unknown error'),
                  fallback: 'Failed to load join requests',
                ),
              ),
            );
          }
          final requests = snapshot.data ?? const [];
          if (requests.isEmpty) {
            return const Center(child: Text('No pending join requests.'));
          }
          return MobileContent(
            padding: EdgeInsets.zero,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: requests.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final request = requests[index];
                final isPending = _pendingRequestId == request.id;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.displayName.isEmpty
                              ? request.email
                              : request.displayName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(request.email),
                        if (request.nickname.isNotEmpty)
                          Text('@${request.nickname}'),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          children: [
                            FilledButton(
                              onPressed: isPending
                                  ? null
                                  : () => _review(request, true),
                              child: const Text('Approve'),
                            ),
                            OutlinedButton(
                              onPressed: isPending
                                  ? null
                                  : () => _review(request, false),
                              child: const Text('Reject'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
