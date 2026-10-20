import 'dart:math' as math;

import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/core/presentation/responsive/breakpoints.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:app/features/gyms/data/repositories/api_gym_repository.dart';
import 'package:app/features/gyms/domain/models/gym_join_request.dart';
import 'package:app/features/admin_analytics/application/admin_analytics_controller.dart';
import 'package:app/features/admin_analytics/domain/models/admin_analytics_overview.dart';
import 'package:app/features/logbook/data/repositories/api_logbook_repository.dart';
import 'package:app/features/logbook/domain/models/workout_log_entry.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:app/features/profile/application/profile_controller.dart';
import 'package:app/features/profile/domain/models/account_type.dart';
import 'package:app/features/profile/domain/models/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const _homeAccent = appPrimary;

// Default weekly training-session goal driving the performance trackers.
// Could be made per-user configurable later.
const _weeklySessionGoal = 5;

// Performance gauge zones. Stays as data-viz red→amber→green regardless of
// theme accent: training intensity is universally read this way and the
// indigo brand color is reserved for chrome.
const _perfRed = Color(0xFFFF5C6E);
const _perfAmber = Color(0xFFFFB454);
const _perfGreen = Color(0xFF3DDC97);

// Pending join requests for the owner dashboard's inline-approve strip. Kept
// auto-disposing so it re-fetches whenever the owner returns to /home, and is
// invalidated after each approve/reject so the strip stays in sync.
final _dashboardJoinRequestsProvider =
    FutureProvider.autoDispose<List<GymJoinRequest>>((ref) async {
      return ref.read(gymRepositoryProvider).fetchJoinRequests();
    });

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<List<ScheduleClass>> _scheduleFuture;
  late Future<List<WorkoutLogEntry>> _entriesFuture;
  late Future<List<DailyWorkout>> _workoutsFuture;

  @override
  void initState() {
    super.initState();
    _scheduleFuture = _loadSchedule();
    _entriesFuture = _loadEntries();
    _workoutsFuture = _loadWorkouts();
  }

  Future<List<ScheduleClass>> _loadSchedule() {
    return ref.read(scheduleRepositoryProvider).fetchSchedule();
  }

  Future<List<WorkoutLogEntry>> _loadEntries() {
    return ref.read(logbookRepositoryProvider).fetchEntries();
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
    // in Logbook — home links into them instead of duplicating them.
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
            const SizedBox(height: appSpace2xl),
            const _SectionHeading('This Week', eyebrow: 'Performance'),
            const SizedBox(height: appSpaceMd),
            _PerformanceTracker(
              entriesFuture: _entriesFuture,
              weeklyGoal: _weeklySessionGoal,
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
    // live in their own tabs/surfaces. The shell renders this branch full-bleed
    // for owners, so the dashboard spans the width; we cap it at the roomy
    // dashboard width and center it to match the wireframe's wide layout.
    return AppGridBackground(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: context.dashboardMaxWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              appSpace2xl,
              appSpaceXl,
              appSpace2xl,
              appSpace3xl,
            ),
            children: const [_OwnerDashboard()],
          ),
        ),
      ),
    );
  }
}

/// Thin wrapper around [AppSectionHeader] preserving the original positional
/// constructor so the dozens of call sites in this file stay untouched.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.title, {this.eyebrow});

  final String title;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    return AppSectionHeader(title: title, eyebrow: eyebrow);
  }
}

/// Athlete's daily focal point: today's WOD title, your next class, and a
/// clear "you've logged" / "you haven't logged" indicator. Pulls from the
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
    final logged = today?.myWorkoutLog != null;
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
              if (today != null)
                AppPill(
                  label: logged ? 'Logged' : 'Open',
                  icon: logged
                      ? Icons.check_circle_rounded
                      : Icons.bolt_rounded,
                  intent: logged
                      ? AppPillIntent.success
                      : AppPillIntent.primary,
                  dense: true,
                ),
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
                  label: today == null
                      ? 'See programming'
                      : (logged ? 'View workout' : 'Open workout'),
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

/// Performance metrics derived from logbook entries. All values are real;
/// "sessions" counts distinct training days so multiple logs on one day don't
/// inflate the number.
class _PerfStats {
  const _PerfStats({
    required this.sessionsThisWeek,
    required this.sessionsLastWeek,
    required this.weeklyGoal,
    required this.streakWeeks,
    required this.prsThisMonth,
    required this.totalPrs,
    required this.totalSessions,
    required this.lastSixWeeks,
  });

  final int sessionsThisWeek;
  final int sessionsLastWeek;
  final int weeklyGoal;
  final int streakWeeks;
  final int prsThisMonth;
  final int totalPrs;
  final int totalSessions;
  final List<int> lastSixWeeks; // oldest -> newest, length 6

  double get weekProgress =>
      weeklyGoal == 0 ? 0 : (sessionsThisWeek / weeklyGoal).clamp(0.0, 1.0);

  int get sessionsTrend => sessionsThisWeek - sessionsLastWeek;

  int get powerScore {
    final sessions = (sessionsThisWeek / weeklyGoal).clamp(0.0, 1.0) * 55;
    final streak = (streakWeeks / 4).clamp(0.0, 1.0) * 25;
    final prs = (prsThisMonth / 2).clamp(0.0, 1.0) * 20;
    return (sessions + streak + prs).round().clamp(0, 100);
  }

  String get powerLevel {
    final value = powerScore;
    if (value >= 85) {
      return 'Peak';
    }
    if (value >= 65) {
      return 'Strong';
    }
    if (value >= 40) {
      return 'Building';
    }
    return 'Warming up';
  }

  factory _PerfStats.from(List<WorkoutLogEntry> entries, int weeklyGoal) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));

    int distinctDaysIn(DateTime start, DateTime end) {
      final days = <int>{};
      for (final entry in entries) {
        final local = entry.scheduledDate.toLocal();
        final day = DateTime(local.year, local.month, local.day);
        if (!day.isBefore(start) && day.isBefore(end)) {
          days.add(day.millisecondsSinceEpoch);
        }
      }
      return days.length;
    }

    // weeks[0] = current week, weeks[5] = five weeks ago.
    final weeks = <int>[];
    for (var w = 0; w < 6; w++) {
      final start = startOfWeek.subtract(Duration(days: 7 * w));
      weeks.add(distinctDaysIn(start, start.add(const Duration(days: 7))));
    }

    // Consecutive weeks with at least one session. The current week gets grace
    // if it's still empty (the week may just have started).
    var streak = 0;
    for (var i = weeks[0] > 0 ? 0 : 1; i < weeks.length; i++) {
      if (weeks[i] > 0) {
        streak++;
      } else {
        break;
      }
    }

    final monthStart = DateTime(now.year, now.month, 1);
    var prsThisMonth = 0;
    var totalPrs = 0;
    for (final entry in entries) {
      if (entry.isPr) {
        totalPrs++;
        if (!entry.scheduledDate.toLocal().isBefore(monthStart)) {
          prsThisMonth++;
        }
      }
    }

    return _PerfStats(
      sessionsThisWeek: weeks[0],
      sessionsLastWeek: weeks[1],
      weeklyGoal: weeklyGoal,
      streakWeeks: streak,
      prsThisMonth: prsThisMonth,
      totalPrs: totalPrs,
      totalSessions: entries.length,
      lastSixWeeks: weeks.reversed.toList(),
    );
  }
}

class _PerformanceTracker extends StatelessWidget {
  const _PerformanceTracker({
    required this.entriesFuture,
    required this.weeklyGoal,
  });

  final Future<List<WorkoutLogEntry>> entriesFuture;
  final int weeklyGoal;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WorkoutLogEntry>>(
      future: entriesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoadingState(height: 220);
        }
        final stats = _PerfStats.from(
          snapshot.data ?? const <WorkoutLogEntry>[],
          weeklyGoal,
        );
        return _GaugeTracker(stats: stats);
      },
    );
  }
}

class _TrackerCard extends StatelessWidget {
  const _TrackerCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard.elevated(
      padding: const EdgeInsets.all(appSpaceXl),
      child: child,
    );
  }
}

class _TrackerHeader extends StatelessWidget {
  const _TrackerHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: appPrimarySoft,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 12, color: appPrimary),
        ),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: appSubtleText,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }
}

// Weekly-sessions performance tracker: a semicircular needle gauge
// ("Tachometer") over a row of supporting stats.
class _GaugeTracker extends StatelessWidget {
  const _GaugeTracker({required this.stats});

  final _PerfStats stats;

  @override
  Widget build(BuildContext context) {
    return _TrackerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TrackerHeader(icon: Icons.speed_rounded, title: 'This week'),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            width: double.infinity,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GaugePainter(progress: stats.weekProgress),
                  ),
                ),
                Align(
                  alignment: const Alignment(0, -0.18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '${stats.sessionsThisWeek}',
                              style: const TextStyle(
                                color: appText,
                                fontSize: 40,
                                fontWeight: FontWeight.w800,
                                height: 1,
                                letterSpacing: -1.2,
                              ),
                            ),
                            TextSpan(
                              text: '  /  ${stats.weeklyGoal}',
                              style: const TextStyle(
                                color: appSubtleText,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stats.powerLevel.toUpperCase(),
                        style: const TextStyle(
                          color: appPrimary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: appBorder),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _GaugeStat(
                  icon: Icons.local_fire_department_rounded,
                  iconColor: _perfRed,
                  value: '${stats.streakWeeks}',
                  label: 'week streak',
                ),
              ),
              Container(width: 1, height: 34, color: appBorder),
              Expanded(
                child: _GaugeStat(
                  value: '${stats.prsThisMonth}',
                  label: 'PRs this month',
                ),
              ),
              Container(width: 1, height: 34, color: appBorder),
              Expanded(
                child: _GaugeStat(
                  value: stats.sessionsTrend > 0
                      ? '+${stats.sessionsTrend}'
                      : '${stats.sessionsTrend}',
                  label: 'vs last week',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugeStat extends StatelessWidget {
  const _GaugeStat({
    this.icon,
    this.iconColor,
    required this.value,
    required this.label,
  });

  final IconData? icon;
  final Color? iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: iconColor ?? appPrimary),
              const SizedBox(width: 4),
            ],
            Text(
              value,
              style: const TextStyle(
                color: appText,
                fontWeight: FontWeight.w900,
                fontSize: 22,
                height: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: appSubtleText, fontSize: 12),
        ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 8);
    final radius = math.min(size.width / 2, size.height - 12) - 14;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Quiet base ring so the unfilled portion of the gauge still reads as a
    // track on near-black instead of disappearing.
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..color = appSurfaceElevated;
    canvas.drawArc(rect, math.pi, math.pi, false, base);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [_perfRed, _perfAmber, _perfGreen],
      ).createShader(rect);
    final sweep = progress.clamp(0.0, 1.0) * math.pi;
    if (sweep > 0) {
      canvas.drawArc(rect, math.pi, sweep, false, track);
    }

    final angle = math.pi + progress.clamp(0.0, 1.0) * math.pi;
    final tip =
        center + Offset(math.cos(angle), math.sin(angle)) * radius * 0.46;
    final needle = Paint()
      ..color = appText
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, tip, needle);
    canvas.drawCircle(center, 7, Paint()..color = appText);
    canvas.drawCircle(center, 3, Paint()..color = appPageBackground);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.progress != progress;
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

// Owner Dashboard Widget - displays gym statistics
class _OwnerDashboard extends ConsumerWidget {
  const _OwnerDashboard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(adminAnalyticsOverviewProvider);

    return analyticsAsync.when(
      data: (overview) => _OwnerDashboardContent(overview: overview),
      loading: () => const AppLoadingState(height: 220),
      error: (error, _) => AppEmptyState.error(
        title: 'Failed to load dashboard',
        subtitle: error.toString(),
      ),
    );
  }
}

class _OwnerDashboardContent extends ConsumerWidget {
  const _OwnerDashboardContent({required this.overview});

  final AdminAnalyticsOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = overview.windowDays;
    final attendancePct = (overview.attendanceRateInWindow * 100).round();
    final utilizationPct = (overview.utilizationRateInWindow * 100).round();
    final noShowPct = (overview.noShowRateInWindow * 100).round();

    final tiles = <_KpiData>[
      _KpiData(
        label: 'Active members',
        value: '${overview.activeMembers}',
        caption: overview.newMembersInWindow > 0
            ? '+${overview.newMembersInWindow} this window'
            : 'no new joins',
        captionColor: overview.newMembersInWindow > 0
            ? _perfGreen
            : appSubtleText,
        dot: appPrimary,
      ),
      _KpiData(
        label: 'Attendance',
        value: '$attendancePct%',
        caption:
            '${overview.attendedInWindow} / ${overview.bookingsInWindow} booked',
        dot: _perfGreen,
      ),
      _KpiData(
        label: 'Utilization',
        value: '$utilizationPct%',
        caption: 'of seated capacity',
        dot: _perfAmber,
      ),
      _KpiData(
        label: 'No-show rate',
        value: '$noShowPct%',
        caption: '${overview.noShowsInWindow} no-shows',
        dot: _perfRed,
      ),
      _KpiData(
        label: 'Pending requests',
        value: '${overview.pendingJoinRequests}',
        caption: overview.pendingJoinRequests > 0
            ? 'needs review'
            : 'all clear',
        captionColor: overview.pendingJoinRequests > 0
            ? _perfAmber
            : appSubtleText,
        dot: _perfAmber,
        highlight: overview.pendingJoinRequests > 0,
      ),
      _KpiData(
        label: 'Forward load · 7d',
        value: '${overview.upcomingClassesNext7Days}',
        caption: 'classes scheduled',
        dot: appInfo,
      ),
    ];

    final timeline = _AttendanceTimelineCard(
      days: overview.dailyAttendance,
      windowDays: window,
    );
    final pressure = overview.pressureClasses.isEmpty
        ? null
        : _PressureClassCard(classes: overview.pressureClasses);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WindowBar(
              selectedWindow: window,
              onWindowSelected: (value) => ref
                  .read(adminAnalyticsWindowDaysProvider.notifier)
                  .setWindowDays(value),
              onFullAnalytics: () => context.go('/admin-analytics'),
            ),
            const SizedBox(height: appSpaceXl),
            _KpiGrid(tiles: tiles, columns: wide ? 3 : 2),
            const SizedBox(height: appSpaceMd),
            if (wide && pressure != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: timeline),
                  const SizedBox(width: appSpaceMd),
                  Expanded(flex: 2, child: pressure),
                ],
              )
            else ...[
              timeline,
              if (pressure != null) ...[
                const SizedBox(height: appSpaceMd),
                pressure,
              ],
            ],
            const SizedBox(height: appSpaceMd),
            const _JoinRequestsCard(),
          ],
        );
      },
    );
  }
}

/// Dashboard title bar: OPERATIONS eyebrow + "Box Dashboard" display title on
/// the left, review-window selector + "Full analytics →" on the right. Wraps
/// the controls beneath the title on narrow widths.
class _WindowBar extends StatelessWidget {
  const _WindowBar({
    required this.selectedWindow,
    required this.onWindowSelected,
    required this.onFullAnalytics,
  });

  final int selectedWindow;
  final ValueChanged<int> onWindowSelected;
  final VoidCallback onFullAnalytics;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: appSpaceLg,
      runSpacing: appSpaceMd,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'OPERATIONS',
              style: appMono(fontSize: 10, letterSpacing: 1.6),
            ),
            const SizedBox(height: 5),
            Text(
              'Box Dashboard',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(letterSpacing: -0.4),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _WindowSelector(
              selected: selectedWindow,
              onSelected: onWindowSelected,
            ),
            const SizedBox(width: appSpaceMd),
            _FullAnalyticsButton(onTap: onFullAnalytics),
          ],
        ),
      ],
    );
  }
}

/// 7 / 14 / 30-day review-window segmented control, mirroring the analytics
/// screen's horizon chips but compact enough for the dashboard top bar.
class _WindowSelector extends StatelessWidget {
  const _WindowSelector({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: appSurface,
        borderRadius: BorderRadius.circular(appRadiusSm),
        border: Border.all(color: appBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final days in const [7, 14, 30])
            GestureDetector(
              onTap: () => onSelected(days),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: days == selected ? appPrimary : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '${days}D',
                  style: appMono(
                    fontSize: 11,
                    color: days == selected ? Colors.white : appSubtleText,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FullAnalyticsButton extends StatelessWidget {
  const _FullAnalyticsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Cut-corner CTA (angled bottom-right) with a cyan glow — the wireframe's
    // primary dashboard button silhouette.
    final shape = appButtonShape(cut: 13);
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: [
          BoxShadow(color: appPrimary.withValues(alpha: 0.45), blurRadius: 20),
        ],
      ),
      child: Material(
        color: appPrimary,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Full analytics',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                SizedBox(width: 7),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KpiData {
  const _KpiData({
    required this.label,
    required this.value,
    required this.caption,
    required this.dot,
    this.captionColor = appSubtleText,
    this.highlight = false,
  });

  final String label;
  final String value;
  final String caption;
  final Color dot;
  final Color captionColor;
  final bool highlight;
}

/// KPI strip that reflows the six dashboard signals into rows of [columns]
/// (3 on the wireframe's desktop layout, 2 on narrow), sized to whatever width
/// the dashboard column provides.
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.tiles, this.columns = 2});

  final List<_KpiData> tiles;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += columns) {
      if (i > 0) rows.add(const SizedBox(height: appSpaceMd));
      final cells = <Widget>[];
      for (var c = 0; c < columns; c++) {
        if (c > 0) cells.add(const SizedBox(width: appSpaceMd));
        final index = i + c;
        cells.add(
          index < tiles.length
              ? Expanded(child: _KpiTile(data: tiles[index]))
              : const Spacer(),
        );
      }
      // IntrinsicHeight gives the Row a bounded cross-axis extent so
      // `stretch` can equalize tile heights inside the vertical scroll view
      // (a bare stretch Row here forces an infinite-height layout error).
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: cells,
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.data});

  final _KpiData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: appSurfaceAlt,
        borderRadius: BorderRadius.circular(appRadiusMd),
        border: Border.all(
          color: data.highlight ? data.dot.withValues(alpha: 0.35) : appBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  data.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appMono(
                    fontSize: 9.5,
                    letterSpacing: 1.3,
                    color: data.highlight ? data.dot : appSubtleText,
                  ),
                ),
              ),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: data.dot,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: appSpaceSm),
          Text(
            data.value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontSize: 28,
              height: 1,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: appMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              color: data.captionColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Daily-attendance sparkline. Bars are normalized against the busiest day in
/// the window; the most recent day is highlighted in bright cyan.
class _AttendanceTimelineCard extends StatelessWidget {
  const _AttendanceTimelineCard({required this.days, required this.windowDays});

  final List<AdminAnalyticsDailyAttendance> days;
  final int windowDays;

  @override
  Widget build(BuildContext context) {
    // dailyAttendance arrives most-recent-first; render oldest → newest.
    final ordered = days.reversed.toList();
    final maxAttended = ordered.fold<int>(
      1,
      (max, d) => d.attended > max ? d.attended : max,
    );
    // Trend: mean attendance of the recent half vs the earlier half.
    double? trendPct;
    if (ordered.length >= 4) {
      final half = ordered.length ~/ 2;
      final earlierMean =
          ordered.take(half).fold<int>(0, (a, d) => a + d.attended) / half;
      final recentMean =
          ordered
              .skip(ordered.length - half)
              .fold<int>(0, (a, d) => a + d.attended) /
          half;
      if (earlierMean > 0) {
        trendPct = (recentMean - earlierMean) / earlierMean * 100;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: appPanelDecoration(radius: appRadiusMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'DAILY ATTENDANCE · ${windowDays}D',
                style: appMono(fontSize: 10, letterSpacing: 1.4),
              ),
              const Spacer(),
              if (trendPct != null && trendPct.abs() >= 1)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      trendPct >= 0
                          ? Icons.arrow_drop_up_rounded
                          : Icons.arrow_drop_down_rounded,
                      size: 16,
                      color: trendPct >= 0 ? _perfGreen : _perfRed,
                    ),
                    Text(
                      '${trendPct.abs().round()}%',
                      style: appMono(
                        fontSize: 11,
                        letterSpacing: 0,
                        color: trendPct >= 0 ? _perfGreen : _perfRed,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: appSpaceLg),
          if (ordered.isEmpty)
            Text(
              'No attendance recorded in this window yet.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: appMutedText),
            )
          else
            SizedBox(
              height: 96,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < ordered.length; i++) ...[
                    if (i > 0) const SizedBox(width: 5),
                    Expanded(
                      child: _TimelineBar(
                        fraction: ordered[i].attended / maxAttended,
                        isLatest: i == ordered.length - 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineBar extends StatelessWidget {
  const _TimelineBar({required this.fraction, required this.isLatest});

  final double fraction;
  final bool isLatest;

  @override
  Widget build(BuildContext context) {
    final height = (fraction.clamp(0.08, 1.0)) * 96;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isLatest
                ? const [Color(0xFF7EF6FF), appPrimary]
                : const [appPrimary, Color(0xFF044E57)],
          ),
          boxShadow: isLatest
              ? [
                  BoxShadow(
                    color: appPrimary.withValues(alpha: 0.5),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

/// "Pressure classes" — sessions at or over capacity, with waitlist or
/// low-fill status pulled straight from the analytics overview.
class _PressureClassCard extends StatelessWidget {
  const _PressureClassCard({required this.classes});

  final List<AdminAnalyticsPressureClass> classes;

  @override
  Widget build(BuildContext context) {
    final shown = classes.take(4).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: appPanelDecoration(radius: appRadiusMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PRESSURE CLASSES',
            style: appMono(fontSize: 10, letterSpacing: 1.4),
          ),
          const SizedBox(height: appSpaceLg),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: appSpaceMd),
              const Divider(height: 1),
              const SizedBox(height: appSpaceMd),
            ],
            _PressureClassRow(item: shown[i]),
          ],
        ],
      ),
    );
  }
}

class _PressureClassRow extends StatelessWidget {
  const _PressureClassRow({required this.item});

  final AdminAnalyticsPressureClass item;

  @override
  Widget build(BuildContext context) {
    final isFull = item.bookings >= item.capacity;
    final time = TimeOfDay.fromDateTime(item.startTime.toLocal());
    final timeLabel = time.format(context);
    final AppPillIntent intent;
    final String pill;
    if (item.waitlistCount > 0) {
      intent = AppPillIntent.danger;
      pill = '+${item.waitlistCount} waitlist';
    } else if (isFull) {
      intent = AppPillIntent.danger;
      pill = 'Full';
    } else {
      intent = AppPillIntent.warning;
      pill = 'Low fill';
    }
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$timeLabel · ${item.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: appText,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${item.bookings}/${item.capacity} booked',
                style: appMono(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: appSpaceMd),
        AppPill(label: pill, intent: intent, dense: true),
      ],
    );
  }
}

/// Inline join-request approvals. Reads the pending queue, lets the owner
/// approve/reject without leaving /home, and refreshes the dashboard counts.
class _JoinRequestsCard extends ConsumerStatefulWidget {
  const _JoinRequestsCard();

  @override
  ConsumerState<_JoinRequestsCard> createState() => _JoinRequestsCardState();
}

class _JoinRequestsCardState extends ConsumerState<_JoinRequestsCard> {
  int? _pendingId;

  Future<void> _review(GymJoinRequest request, bool approve) async {
    setState(() => _pendingId = request.id);
    try {
      await ref
          .read(gymRepositoryProvider)
          .reviewJoinRequest(requestId: request.id, approve: approve);
      if (!mounted) return;
      ref.invalidate(_dashboardJoinRequestsProvider);
      ref.invalidate(adminAnalyticsOverviewProvider);
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessageFrom(error, fallback: 'Review failed')),
        ),
      );
    } finally {
      if (mounted) setState(() => _pendingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(_dashboardJoinRequestsProvider);
    final requests = requestsAsync.value ?? const <GymJoinRequest>[];
    if (requests.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: appPanelDecoration(radius: appRadiusMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'JOIN REQUESTS · INLINE APPROVE',
                style: appMono(fontSize: 10, letterSpacing: 1.4),
              ),
              const Spacer(),
              AppPill(
                label: '${requests.length} pending',
                intent: AppPillIntent.warning,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: appSpaceLg),
          for (var i = 0; i < requests.length; i++) ...[
            if (i > 0) const SizedBox(height: appSpaceSm),
            _JoinRequestRow(
              request: requests[i],
              busy: _pendingId == requests[i].id,
              onApprove: () => _review(requests[i], true),
              onReject: () => _review(requests[i], false),
            ),
          ],
        ],
      ),
    );
  }
}

class _JoinRequestRow extends StatelessWidget {
  const _JoinRequestRow({
    required this.request,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final GymJoinRequest request;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final name = request.displayName.trim().isNotEmpty
        ? request.displayName
        : request.email;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: appInsetDecoration(),
      child: Row(
        children: [
          AppAvatar(displayName: name, size: 34),
          const SizedBox(width: appSpaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: appText,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  request.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: appSpaceMd),
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            _RequestActionButton(
              icon: Icons.check_rounded,
              filled: true,
              onTap: onApprove,
            ),
            const SizedBox(width: 6),
            _RequestActionButton(
              icon: Icons.close_rounded,
              filled: false,
              onTap: onReject,
            ),
          ],
        ],
      ),
    );
  }
}

class _RequestActionButton extends StatelessWidget {
  const _RequestActionButton({
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(appRadiusSm),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: filled ? _perfGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(appRadiusSm),
            border: filled ? null : Border.all(color: appBorderStrong),
          ),
          child: Icon(
            icon,
            size: 18,
            color: filled ? appInverseText : appSubtleText,
          ),
        ),
      ),
    );
  }
}
