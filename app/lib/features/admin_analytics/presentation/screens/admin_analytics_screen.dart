import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
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
    final selectedWindowDays = ref.watch(adminAnalyticsWindowDaysProvider);
    final analyticsAsync = ref.watch(adminAnalyticsOverviewProvider);
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final hasAccess =
        profile?.role == UserRole.admin && profile?.activeGym != null;

    return AppMobileScaffold(
      title: 'Read the floor fast',
      eyebrow: 'Analytics',
      onBack: () => context.go('/profile'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          appSpaceLg,
          appSpaceLg,
          appSpaceLg,
          appSpace2xl,
        ),
        children: [
          const _HeaderSubtitle(
            text:
                'Attendance, utilization, and operational pressure in one quick scan.',
          ),
          const SizedBox(height: appSpaceLg),
          if (!hasAccess)
            const _BlockedState()
          else
            analyticsAsync.when(
              data: (overview) => _OverviewContent(
                overview: overview,
                selectedWindowDays: selectedWindowDays,
                onWindowChanged: (windowDays) => ref
                    .read(adminAnalyticsWindowDaysProvider.notifier)
                    .setWindowDays(windowDays),
              ),
              loading: () => const _LoadingState(),
              error: (error, _) => _ErrorState(message: error.toString()),
            ),
        ],
      ),
    );
  }
}

class _HeaderSubtitle extends StatelessWidget {
  const _HeaderSubtitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: appMutedText,
            height: 1.45,
          ),
    );
  }
}

class _OverviewContent extends StatelessWidget {
  const _OverviewContent({
    required this.overview,
    required this.selectedWindowDays,
    required this.onWindowChanged,
  });

  final AdminAnalyticsOverview overview;
  final int selectedWindowDays;
  final ValueChanged<int> onWindowChanged;

  @override
  Widget build(BuildContext context) {
    final recentDays = overview.dailyAttendance.reversed.take(7).toList();
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
              tone: appPrimary,
            ),
            _MetricCard(
              label: 'Active trainers',
              value: '${overview.activeTrainers}',
              tone: appPrimary,
            ),
            _MetricCard(
              label: 'Pending join requests',
              value: '${overview.pendingJoinRequests}',
              tone: appPrimary,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _Panel(
          eyebrow: 'Window control',
          title: 'Choose the review horizon',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final windowDays in const [7, 14, 30])
                _WindowChip(
                  label: '${windowDays}D',
                  selected: selectedWindowDays == windowDays,
                  onTap: () => onWindowChanged(windowDays),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          eyebrow: 'Membership health',
          title: 'Who is joining and what mix is forming',
          child: Column(
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard(
                    label: 'New members',
                    value: '${overview.newMembersInWindow}',
                    tone: appPrimary,
                    compact: true,
                  ),
                  _MetricCard(
                    label: 'Athlete only',
                    value: '${overview.roleMix.athleteOnly}',
                    tone: appPrimary,
                    compact: true,
                  ),
                  _MetricCard(
                    label: 'Trainer capable',
                    value: '${overview.roleMix.trainerCapable}',
                    tone: appPrimary,
                    compact: true,
                  ),
                  _MetricCard(
                    label: 'Admin capable',
                    value: '${overview.roleMix.adminCapable}',
                    tone: appPrimary,
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Recent members',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: appText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (overview.recentMembers.isEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'No recent memberships in this gym yet.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: appMutedText),
                  ),
                )
              else
                Column(
                  children: [
                    for (
                      var index = 0;
                      index < overview.recentMembers.length;
                      index++
                    ) ...[
                      _RecentMemberRow(item: overview.recentMembers[index]),
                      if (index < overview.recentMembers.length - 1)
                        const Divider(color: Color(0x1FFFFFFF), height: 24),
                    ],
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          eyebrow: 'Last ${overview.windowDays} days',
          title: 'Attendance health',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricCard(
                label: 'Classes',
                value: '${overview.classesInWindow}',
                tone: appPrimary,
                compact: true,
              ),
              _MetricCard(
                label: 'Bookings',
                value: '${overview.bookingsInWindow}',
                tone: appPrimary,
                compact: true,
              ),
              _MetricCard(
                label: 'Attendance rate',
                value: '${overview.attendanceRateInWindow.toStringAsFixed(1)}%',
                tone: appPrimary,
                compact: true,
              ),
              _MetricCard(
                label: 'Utilization',
                value:
                    '${overview.utilizationRateInWindow.toStringAsFixed(1)}%',
                tone: appPrimary,
                compact: true,
              ),
              _MetricCard(
                label: 'No-show rate',
                value: '${overview.noShowRateInWindow.toStringAsFixed(1)}%',
                tone: appDanger,
                compact: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          eyebrow: 'Next 7 days',
          title: 'Forward pressure',
          child: Column(
            children: [
              Row(
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
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard(
                    label: 'Waitlist spots',
                    value: '${overview.upcomingWaitlistSpotsNext7Days}',
                    tone: appPrimary,
                    compact: true,
                  ),
                  _MetricCard(
                    label: 'Classes with waitlist',
                    value: '${overview.upcomingClassesWithWaitlistNext7Days}',
                    tone: appDanger,
                    compact: true,
                  ),
                  _MetricCard(
                    label: 'Full classes',
                    value: '${overview.upcomingFullClassesNext7Days}',
                    tone: appPrimary,
                    compact: true,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          eyebrow: 'Pressure list',
          title: 'Classes that need attention',
          child: overview.pressureClasses.isEmpty
              ? Text(
                  'No waitlist-heavy or full classes are building pressure right now.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: appMutedText,
                    height: 1.5,
                  ),
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < overview.pressureClasses.length;
                      index++
                    ) ...[
                      _PressureClassRow(item: overview.pressureClasses[index]),
                      if (index < overview.pressureClasses.length - 1)
                        const Divider(color: Color(0x1FFFFFFF), height: 24),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _Panel(
          eyebrow: 'Retention risk',
          title: 'Low-attendance and no-show drilldown',
          child: overview.problemClasses.isEmpty
              ? Text(
                  'No completed classes crossed the low-attendance or high-no-show thresholds in this window.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: appMutedText,
                    height: 1.5,
                  ),
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < overview.problemClasses.length;
                      index++
                    ) ...[
                      _ProblemClassRow(item: overview.problemClasses[index]),
                      if (index < overview.problemClasses.length - 1)
                        const Divider(color: Color(0x1FFFFFFF), height: 24),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _Panel(
          eyebrow: 'Daily view',
          title: 'Attendance timeline',
          child: Column(
            children: [
              for (var index = 0; index < recentDays.length; index++) ...[
                _DailyRow(day: recentDays[index]),
                if (index < recentDays.length - 1)
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
              color: appSurface.withOpacity(0.84),
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
                    color: appText,
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
        color: appSurface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: appPrimary,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: appText,
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
            color: appText,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: appSubtleText),
        ),
      ],
    );
  }
}

class _RecentMemberRow extends StatelessWidget {
  const _RecentMemberRow({required this.item});

  final AdminAnalyticsRecentMember item;

  @override
  Widget build(BuildContext context) {
    final joined = item.createdAt;
    final dateLabel =
        '${joined.day.toString().padLeft(2, '0')}.${joined.month.toString().padLeft(2, '0')}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.displayName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: appText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${item.email} · ${item.activeRole}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: appMutedText),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          dateLabel,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: appPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _WindowChip extends StatelessWidget {
  const _WindowChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? appPrimary.withOpacity(0.16) : appSurfaceAlt,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? appPrimary : appBorder),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? appPrimary : Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: appText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            '${day.classes} classes · ${day.bookings} bookings · ${day.attended} attended · ${day.noShows} no-shows',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: appMutedText),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '${day.utilizationRate.toStringAsFixed(1)}%',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: appPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PressureClassRow extends StatelessWidget {
  const _PressureClassRow({required this.item});

  final AdminAnalyticsPressureClass item;

  @override
  Widget build(BuildContext context) {
    final start = item.startTime;
    final dateLabel =
        '${start.day.toString().padLeft(2, '0')}.${start.month.toString().padLeft(2, '0')} · ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: appText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$dateLabel · ${item.bookings}/${item.capacity} booked',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: appMutedText),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${item.waitlistCount} WL',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: appPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${item.utilizationRate.toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: appPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProblemClassRow extends StatelessWidget {
  const _ProblemClassRow({required this.item});

  final AdminAnalyticsProblemClass item;

  @override
  Widget build(BuildContext context) {
    final start = item.startTime;
    final dateLabel =
        '${start.day.toString().padLeft(2, '0')}.${start.month.toString().padLeft(2, '0')} · ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: appText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$dateLabel · ${item.bookings}/${item.capacity} booked · ${item.attended} attended · ${item.noShows} no-shows',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: appMutedText),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${item.noShowRate.toStringAsFixed(1)}% NS',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: appDanger,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${item.attendanceRate.toStringAsFixed(1)}% att.',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: appPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
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
