import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:app/features/home/presentation/widgets/owner_dashboard.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const _homeAccent = appPrimary;

// Pending join requests for the owner dashboard's inline-approve strip. Kept
// auto-disposing so it re-fetches whenever the owner returns to /home, and is
// invalidated after each approve/reject so the strip stays in sync.

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<List<ScheduleClass>> _scheduleFuture;
  late Future<List<DailyWorkout>> _workoutsFuture;

  @override
  void initState() {
    super.initState();
    _scheduleFuture = _loadSchedule();
    _workoutsFuture = _loadWorkouts();
  }

  Future<List<ScheduleClass>> _loadSchedule() {
    return ref.read(scheduleRepositoryProvider).fetchSchedule();
  }

  Future<List<DailyWorkout>> _loadWorkouts() {
    return ref.read(programmingRepositoryProvider).fetchWorkouts();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final hasActiveGym = profile?.activeGym != null;
    final isOwner =
        profile?.accountType == AccountType.admin &&
        profile?.role == UserRole.admin;

    // Owner/Admin workflow
    if (isOwner) {
      return _buildOwnerHome(context: context, hasActiveGym: hasActiveGym);
    }

    // Athlete/Trainer home is an entry point, not a summary of the whole app:
    // today's WOD, the next booking (both inside the hero) and one weekly
    // stat. The full schedule lives in My Box, box news in Community, history
    // — home links into them instead of duplicating them.
    return AppGridBackground(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          appSpaceLg,
          appSpaceLg,
          appSpaceLg,
          appSpace3xl,
        ),
        children: [
          if (!hasActiveGym)
            _ActionSpotlight(
              icon: Icons.search_outlined,
              title: 'Find Your Box',
              subtitle:
                  'Join a box to see today’s training, book classes, and track your week.',
              actionLabel: 'Browse Boxes',
              accentColor: _homeAccent,
              onTap: () => context.go('/gyms'),
            )
          else ...[
            _TodayHero(
              workoutsFuture: _workoutsFuture,
              scheduleFuture: _scheduleFuture,
              onOpenWorkout: () => context.go('/my-box'),
              onOpenBooking: () => context.go('/my-box'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOwnerHome({
    required BuildContext context,
    required bool hasActiveGym,
  }) {
    if (!hasActiveGym) {
      // Owner without a box - show only "Create your first box"
      return AppGridBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            const SizedBox(height: 40),
            _ActionSpotlight(
              icon: Icons.storefront_outlined,
              title: 'Create Your First Box',
              subtitle:
                  'Set up your box to unlock member flows, scheduling, and workout delivery.',
              actionLabel: 'Create Box',
              accentColor: _homeAccent,
              onTap: () => context.go('/create-gym'),
            ),
          ],
        ),
      );
    }

    // Owner with an active box lands on the operational dashboard — the
    // wireframe's "signal, not a news feed" view. Announcements and shortcuts
    // live in their own tabs/surfaces. Same content column and padding as the
    // other tabs (Members, Community, Profile).
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        appSpaceLg,
        appSpaceLg,
        appSpaceLg,
        appSpace3xl,
      ),
      children: const [OwnerDashboard()],
    );
  }
}

/// Athlete's daily focal point: today's WOD title, your next class, and a
/// Pulls from the
/// existing programming and schedule streams so no new endpoints were needed.
class _TodayHero extends StatelessWidget {
  const _TodayHero({
    required this.workoutsFuture,
    required this.scheduleFuture,
    required this.onOpenWorkout,
    required this.onOpenBooking,
  });

  final Future<List<DailyWorkout>> workoutsFuture;
  final Future<List<ScheduleClass>> scheduleFuture;
  final VoidCallback onOpenWorkout;
  final VoidCallback onOpenBooking;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DailyWorkout>>(
      future: workoutsFuture,
      builder: (context, workoutSnap) {
        return FutureBuilder<List<ScheduleClass>>(
          future: scheduleFuture,
          builder: (context, scheduleSnap) {
            if (workoutSnap.connectionState == ConnectionState.waiting ||
                scheduleSnap.connectionState == ConnectionState.waiting) {
              return const AppLoadingState(height: 180);
            }
            final today = _todayWorkout(workoutSnap.data);
            final nextBooking = _nextBooking(scheduleSnap.data);
            return _TodayHeroBody(
              today: today,
              nextBooking: nextBooking,
              onOpenWorkout: onOpenWorkout,
              onOpenBooking: onOpenBooking,
            );
          },
        );
      },
    );
  }

  static DailyWorkout? _todayWorkout(List<DailyWorkout>? workouts) {
    if (workouts == null || workouts.isEmpty) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final workout in workouts) {
      final local = workout.scheduledDate.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      if (day == today) return workout;
    }
    return null;
  }

  static ScheduleClass? _nextBooking(List<ScheduleClass>? items) {
    if (items == null || items.isEmpty) return null;
    final now = DateTime.now();
    final upcoming =
        items.where((c) => c.isBooked && c.startTime.isAfter(now)).toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return upcoming.isEmpty ? null : upcoming.first;
  }
}

class _TodayHeroBody extends StatelessWidget {
  const _TodayHeroBody({
    required this.today,
    required this.nextBooking,
    required this.onOpenWorkout,
    required this.onOpenBooking,
  });

  final DailyWorkout? today;
  final ScheduleClass? nextBooking;
  final VoidCallback onOpenWorkout;
  final VoidCallback onOpenBooking;

  @override
  Widget build(BuildContext context) {
    final dateLabel = _todayLabel();
    return AppCard.elevated(
      padding: const EdgeInsets.all(appSpaceXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: appPrimarySoft,
                  borderRadius: BorderRadius.circular(appRadiusPill),
                  border: Border.all(color: appPrimaryHairline),
                ),
                child: const Text(
                  'TODAY',
                  style: TextStyle(
                    color: appPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                dateLabel,
                style: const TextStyle(
                  color: appSubtleText,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: appSpaceMd),
          Text(
            today?.title ?? 'No WOD posted yet',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: appText,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.1,
              letterSpacing: -0.5,
            ),
          ),
          if (today != null && today!.sections.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              today!.sections.first.description.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: appMutedText,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ] else if (today == null) ...[
            const SizedBox(height: 6),
            const Text(
              'Your coach hasn’t posted today’s training yet. Check back soon.',
              style: TextStyle(color: appMutedText, fontSize: 13, height: 1.45),
            ),
          ],
          const SizedBox(height: appSpaceLg),
          _NextBookingStrip(booking: nextBooking, onTap: onOpenBooking),
          const SizedBox(height: appSpaceLg),
          Row(
            children: [
              Expanded(
                child: AppPrimaryButton(
                  label: today == null ? 'See programming' : 'Open workout',
                  icon: today == null
                      ? Icons.calendar_today_outlined
                      : Icons.local_fire_department_outlined,
                  onPressed: onOpenWorkout,
                  size: AppButtonSize.md,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _todayLabel() {
    final now = DateTime.now();
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final weekday = weekdays[now.weekday - 1];
    final month = months[now.month - 1];
    return '$weekday · $month ${now.day}'.toUpperCase();
  }
}

class _NextBookingStrip extends StatelessWidget {
  const _NextBookingStrip({required this.booking, required this.onTap});

  final ScheduleClass? booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (booking == null) {
      return AppCard.inset(
        onTap: onTap,
        padding: const EdgeInsets.all(appSpaceMd),
        child: Row(
          children: const [
            Icon(Icons.event_outlined, color: appSubtleText, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No class booked. Tap to reserve your slot.',
                style: TextStyle(color: appSubtleText, fontSize: 12.5),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: appSubtleText, size: 18),
          ],
        ),
      );
    }
    final localizations = MaterialLocalizations.of(context);
    final startLabel = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(booking!.startTime.toLocal()),
      alwaysUse24HourFormat: true,
    );
    final dayLabel = _bookingDayLabel(booking!.startTime.toLocal());
    return AppCard.inset(
      onTap: onTap,
      padding: const EdgeInsets.all(appSpaceMd),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: appPrimarySoft,
              borderRadius: BorderRadius.circular(appRadiusSm),
              border: Border.all(color: appPrimaryHairline),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.check_circle_outline_rounded,
              color: appPrimary,
              size: 20,
            ),
          ),
          const SizedBox(width: appSpaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking!.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: appText,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$dayLabel · $startLabel',
                  style: const TextStyle(color: appSubtleText, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: appSubtleText,
            size: 18,
          ),
        ],
      ),
    );
  }

  static String _bookingDayLabel(DateTime local) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (diff > 1 && diff <= 6) return weekdays[local.weekday - 1];
    return '${local.day}/${local.month}';
  }
}

class _ActionSpotlight extends StatelessWidget {
  const _ActionSpotlight({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentColor.withOpacity(0.22), appSurfaceAlt],
        ),
        border: Border.all(color: accentColor.withOpacity(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAccentBadge(icon: icon, color: accentColor),
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
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: appMutedText,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: onTap,
                  child: Text(actionLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
