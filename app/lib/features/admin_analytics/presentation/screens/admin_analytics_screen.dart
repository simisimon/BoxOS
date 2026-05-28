import 'dart:ui';

import 'package:app/features/admin_analytics/application/admin_analytics_controller.dart';
import 'package:app/features/admin_analytics/domain/models/admin_analytics_overview.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AdminAnalyticsScreen extends ConsumerWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    final analyticsAsync = ref.watch(adminAnalyticsOverviewProvider);
    final profile = profileAsync.valueOrNull;
    final hasAccess = profile?.role == UserRole.admin && profile?.activeGym != null;

    return Scaffold(
      backgroundColor: const Color(0xFF09111E),
      body: SafeArea(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF09111E),
                Color(0xFF10192A),
                Color(0xFF0B1320),
              ],
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => context.go('/profile'),
                    icon: const Icon(Icons.arrow_back),
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: _HeaderBlock(
                      eyebrow: 'Admin Analytics',
                      title: 'Read the floor fast',
                      subtitle:
                          'Attendance, utilization, and operational pressure in one quick scan.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (!hasAccess)
                const _BlockedState()
              else
                analyticsAsync.when(
                  data: (overview) => _OverviewContent(overview: overview),
                  loading: () => const _LoadingState(),
                  error: (error, _) => _ErrorState(message: error.toString()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderBlock extends StatelessWidget {
  const _HeaderBlock({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: const Color(0xFF7EE7C6),
            fontWeight: FontWeight.w800,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white.withOpacity(0.72),
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _OverviewContent extends StatelessWidget {
  const _OverviewContent({required this.overview});

  final AdminAnalyticsOverview overview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              label: 'Active members',
              value: '${overview.activeMembers}',
              tone: const Color(0xFF5FB2FF),
            ),
            _MetricCard(
              label: 'Active trainers',
              value: '${overview.activeTrainers}',
              tone: const Color(0xFFFFA94D),
            ),
            _MetricCard(
              label: 'Pending join requests',
              value: '${overview.pendingJoinRequests}',
              tone: const Color(0xFF7EE7C6),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _Panel(
          eyebrow: 'Last ${overview.windowDays} days',
          title: 'Attendance health',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricCard(
                label: 'Classes',
                value: '${overview.classesLast14Days}',
                tone: const Color(0xFFFF6B2C),
                compact: true,
              ),
              _MetricCard(
                label: 'Bookings',
                value: '${overview.bookingsLast14Days}',
                tone: const Color(0xFF5FB2FF),
                compact: true,
              ),
              _MetricCard(
                label: 'Attendance rate',
                value: '${overview.attendanceRateLast14Days.toStringAsFixed(1)}%',
                tone: const Color(0xFF7EE7C6),
                compact: true,
              ),
              _MetricCard(
                label: 'Utilization',
                value: '${overview.utilizationRateLast14Days.toStringAsFixed(1)}%',
                tone: const Color(0xFFE6F14A),
                compact: true,
              ),
              _MetricCard(
                label: 'No-show rate',
                value: '${overview.noShowRateLast14Days.toStringAsFixed(1)}%',
                tone: const Color(0xFFFF8A80),
                compact: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          eyebrow: 'Next 7 days',
          title: 'Forward pressure',
          child: Row(
            children: [
              Expanded(
                child: _ForwardStat(
                  label: 'Upcoming classes',
                  value: '${overview.upcomingClassesNext7Days}',
                ),
              ),
              Expanded(
                child: _ForwardStat(
                  label: 'Booked spots',
                  value: '${overview.upcomingBookingsNext7Days}',
                ),
              ),
              Expanded(
                child: _ForwardStat(
                  label: 'Capacity',
                  value: '${overview.upcomingCapacityNext7Days}',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          eyebrow: 'Daily view',
          title: 'Attendance timeline',
          child: Column(
            children: [
              for (final day in overview.dailyAttendance.reversed.take(7)) ...[
                _DailyRow(day: day),
                if (day != overview.dailyAttendance.reversed.take(7).last)
                  const Divider(color: Color(0x1FFFFFFF), height: 24),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.tone,
    this.compact = false,
  });

  final String label;
  final String value;
  final Color tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: compact ? 150 : 180),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF111C2D).withOpacity(0.84),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: tone.withOpacity(0.28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.eyebrow,
    required this.title,
    required this.child,
  });

  final String eyebrow;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111C2D),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFF7EE7C6),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ForwardStat extends StatelessWidget {
  const _ForwardStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      ],
    );
  }
}

class _DailyRow extends StatelessWidget {
  const _DailyRow({required this.day});

  final AdminAnalyticsDailyAttendance day;

  @override
  Widget build(BuildContext context) {
    final label =
        '${day.date.day.toString().padLeft(2, '0')}.${day.date.month.toString().padLeft(2, '0')}';
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            '${day.classes} classes · ${day.bookings} bookings · ${day.attended} attended · ${day.noShows} no-shows',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withOpacity(0.78),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '${day.utilizationRate.toStringAsFixed(1)}%',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: const Color(0xFF7EE7C6),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _BlockedState extends StatelessWidget {
  const _BlockedState();

  @override
  Widget build(BuildContext context) {
    return const _Panel(
      eyebrow: 'Access locked',
      title: 'Admin gym context required',
      child: Text(
        'You need an active admin gym to view analytics.',
        style: TextStyle(color: Colors.white70, height: 1.5),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      eyebrow: 'Load failed',
      title: 'Analytics could not load',
      child: Text(
        message,
        style: const TextStyle(color: Colors.white70, height: 1.5),
      ),
    );
  }
}
