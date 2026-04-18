import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/mobile_content.dart';
import 'package:app/features/gyms/data/repositories/api_gym_repository.dart';
import 'package:app/features/gyms/domain/models/my_gym_join_request.dart';
import 'package:app/features/profile/domain/models/gym_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GymDirectoryScreen extends ConsumerStatefulWidget {
  const GymDirectoryScreen({super.key});

  @override
  ConsumerState<GymDirectoryScreen> createState() => _GymDirectoryScreenState();
}

class _GymDirectoryScreenState extends ConsumerState<GymDirectoryScreen> {
  late Future<List<GymSummary>> _gymsFuture;
  late Future<List<MyGymJoinRequest>> _requestsFuture;
  final _searchController = TextEditingController();
  int? _pendingGymId;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _gymsFuture = ref.read(gymRepositoryProvider).listGyms();
    _requestsFuture = ref.read(gymRepositoryProvider).fetchMyJoinRequests();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _requestJoin(GymSummary gym) async {
    if (_pendingGymId != null) {
      return;
    }
    setState(() => _pendingGymId = gym.id);
    try {
      await ref.read(gymRepositoryProvider).requestJoin(gymId: gym.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Join request sent to ${gym.name}.')),
      );
      setState(() {
        _requestsFuture = ref.read(gymRepositoryProvider).fetchMyJoinRequests();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Join request failed'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _pendingGymId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find a Gym')),
      body: FutureBuilder<List<Object>>(
        future: Future.wait<Object>([_gymsFuture, _requestsFuture]),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                errorMessageFrom(
                  snapshot.error ?? Exception('Unknown error'),
                  fallback: 'Failed to load gyms',
                ),
              ),
            );
          }
          final data = snapshot.data ?? const <Object>[];
          final gyms = data.isNotEmpty
              ? data[0] as List<GymSummary>
              : const <GymSummary>[];
          final requests = data.length > 1
              ? data[1] as List<MyGymJoinRequest>
              : const <MyGymJoinRequest>[];
          final filteredGyms = gyms.where((gym) {
            final query = _query.trim().toLowerCase();
            if (query.isEmpty) {
              return true;
            }
            return gym.name.toLowerCase().contains(query) ||
                gym.slug.toLowerCase().contains(query) ||
                gym.timezone.toLowerCase().contains(query);
          }).toList();
          final requestsByGymId = {
            for (final request in requests) request.gym.id: request,
          };
          if (gyms.isEmpty) {
            return const Center(child: Text('No gyms available yet.'));
          }
          return MobileContent(
            padding: EdgeInsets.zero,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Search gyms',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 16),
                if (requests.isNotEmpty) ...[
                  Text(
                    'My Requests',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  ...requests.map(
                    (request) => Card(
                      child: ListTile(
                        title: Text(request.gym.name),
                        subtitle: Text(
                          request.status == 'pending'
                              ? 'Waiting for admin approval'
                              : request.status == 'approved'
                              ? 'Approved. You can switch into this gym from your profile.'
                              : 'Rejected by gym admin',
                        ),
                        trailing: _StatusChip(status: request.status),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  'Available Gyms',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (filteredGyms.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No gyms match your search.'),
                    ),
                  ),
                ...filteredGyms.map((gym) {
                  final isPending = _pendingGymId == gym.id;
                  final request = requestsByGymId[gym.id];
                  final isMemberApproved = request?.status == 'approved';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              gym.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text('Timezone: ${gym.timezone}'),
                            Text('Slug: ${gym.slug}'),
                            const SizedBox(height: 12),
                            if (request != null) ...[
                              Row(
                                children: [
                                  _StatusChip(status: request.status),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      request.status == 'pending'
                                          ? 'Request submitted. Waiting for approval.'
                                          : request.status == 'approved'
                                          ? 'Membership approved.'
                                          : 'Request rejected.',
                                    ),
                                  ),
                                ],
                              ),
                            ] else
                              FilledButton(
                                onPressed: isPending || isMemberApproved
                                    ? null
                                    : () => _requestJoin(gym),
                                child: isPending
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Request to Join'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      'approved' => ('Approved', Colors.green.shade700),
      'rejected' => ('Rejected', scheme.error),
      _ => ('Pending', scheme.primary),
    };
    return Chip(
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: 0.2)),
      labelStyle: TextStyle(color: color),
    );
  }
}
