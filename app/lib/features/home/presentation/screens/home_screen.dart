import 'dart:math' as math;

import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:app/features/home/presentation/widgets/owner_dashboard.dart';
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
    // live in their own tabs/surfaces. Same content column and padding as the
    // other tabs (Members, Community, Logbook, Profile).
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
