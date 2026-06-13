import 'dart:math' as math;
import 'dart:typed_data';

import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/core/presentation/mobile_content.dart';
import 'package:app/features/announcements/data/repositories/api_announcement_repository.dart';
import 'package:app/features/announcements/domain/models/announcement.dart';
import 'package:app/features/announcements/domain/repositories/announcement_repository.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
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
import 'package:image_picker/image_picker.dart';

const _homeAccent = appPrimary;
const _homeDanger = appDanger;

// Default weekly training-session goal driving the performance trackers.
// Could be made per-user configurable later.
const _weeklySessionGoal = 5;

// Performance gauge zones. Stays as data-viz red→amber→green regardless of
// theme accent: training intensity is universally read this way and the
// indigo brand color is reserved for chrome.
const _perfRed = Color(0xFFFF5C6E);
const _perfAmber = Color(0xFFFFB454);
const _perfGreen = Color(0xFF3DDC97);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<List<Announcement>> _announcementsFuture;
  late Future<List<ScheduleClass>> _scheduleFuture;
  late Future<List<WorkoutLogEntry>> _entriesFuture;
  late Future<List<DailyWorkout>> _workoutsFuture;

  @override
  void initState() {
    super.initState();
    _announcementsFuture = _loadAnnouncements();
    _scheduleFuture = _loadSchedule();
    _entriesFuture = _loadEntries();
    _workoutsFuture = _loadWorkouts();
  }

  Future<List<Announcement>> _loadAnnouncements() {
    return ref.read(announcementRepositoryProvider).fetchAnnouncements();
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

  Future<void> _refreshAnnouncements() async {
    setState(() {
      _announcementsFuture = _loadAnnouncements();
    });
  }

  Future<void> _refreshSchedule() async {
    setState(() {
      _scheduleFuture = _loadSchedule();
    });
  }

  Future<void> _openAnnouncementComposer() async {
    final repository = ref.read(announcementRepositoryProvider);
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AnnouncementComposerDialog(repository: repository),
    );
    if (saved == true) {
      await _refreshAnnouncements();
    }
  }

  Future<void> _openAnnouncementEditor(Announcement announcement) async {
    final repository = ref.read(announcementRepositoryProvider);
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AnnouncementComposerDialog(
        existing: announcement,
        repository: repository,
      ),
    );
    if (saved == true) {
      await _refreshAnnouncements();
    }
  }

  Future<void> _deleteAnnouncement(Announcement announcement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: appSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: appBorder),
        ),
        title: const Text(
          'Delete announcement',
          style: TextStyle(color: appText),
        ),
        content: Text(
          'Delete "${announcement.title}"? This can’t be undone.',
          style: const TextStyle(color: appMutedText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: _homeDanger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref
          .read(announcementRepositoryProvider)
          .deleteAnnouncement(id: announcement.id);
      if (!mounted) {
        return;
      }
      await _refreshAnnouncements();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to delete announcement'),
          ),
        ),
      );
    }
  }

  Future<void> _toggleAnnouncementLike(Announcement announcement) async {
    try {
      final repository = ref.read(announcementRepositoryProvider);
      if (announcement.likedByMe) {
        await repository.unlikeAnnouncement(announcementId: announcement.id);
      } else {
        await repository.likeAnnouncement(announcementId: announcement.id);
      }
      if (!mounted) {
        return;
      }
      await _refreshAnnouncements();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Like update failed.'),
          ),
        ),
      );
    }
  }

  Future<void> _createAnnouncementComment(
    Announcement announcement,
    String body,
  ) async {
    try {
      await ref
          .read(announcementRepositoryProvider)
          .createComment(announcementId: announcement.id, body: body);
      if (!mounted) {
        return;
      }
      await _refreshAnnouncements();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Comment could not be posted.'),
          ),
        ),
      );
    }
  }

  Future<void> _editAnnouncementComment(
    AnnouncementComment comment,
    String body,
  ) async {
    try {
      await ref
          .read(announcementRepositoryProvider)
          .updateComment(commentId: comment.id, body: body);
      if (!mounted) {
        return;
      }
      await _refreshAnnouncements();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Comment could not be updated.'),
          ),
        ),
      );
    }
  }

  Future<void> _deleteAnnouncementComment(AnnouncementComment comment) async {
    try {
      await ref
          .read(announcementRepositoryProvider)
          .deleteComment(commentId: comment.id);
      if (!mounted) {
        return;
      }
      await _refreshAnnouncements();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Comment could not be deleted.'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.hasValue ? profileAsync.value : null;
    final hasActiveGym = profile?.activeGym != null;
    final isOwner = profile?.accountType == AccountType.admin &&
        profile?.role == UserRole.admin;
    final canManageAnnouncements =
        hasActiveGym &&
        (profile?.role == UserRole.admin || profile?.role == UserRole.trainer);

    // Owner/Admin workflow
    if (isOwner) {
      return _buildOwnerHome(
        context: context,
        hasActiveGym: hasActiveGym,
        canManageAnnouncements: canManageAnnouncements,
      );
    }

    // Athlete/Trainer workflow (existing behavior)
    return DecoratedBox(
      decoration: appPageDecoration(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          appSpaceLg,
          appSpaceLg,
          appSpaceLg,
          appSpace3xl,
        ),
        children: [
          if (hasActiveGym) ...[
            _TodayHero(
              workoutsFuture: _workoutsFuture,
              scheduleFuture: _scheduleFuture,
              onOpenWorkout: () => context.go('/programming'),
              onOpenBooking: () => context.go('/my-box'),
            ),
            const SizedBox(height: appSpace2xl),
            const _SectionHeading(
              'This Week',
              eyebrow: 'Performance',
            ),
            const SizedBox(height: appSpaceMd),
            _PerformanceTracker(
              entriesFuture: _entriesFuture,
              weeklyGoal: _weeklySessionGoal,
            ),
            const SizedBox(height: appSpace2xl),
          ],
          const _SectionHeading(
            'Your Bookings',
            eyebrow: 'Schedule',
          ),
          const SizedBox(height: appSpaceMd),
          _BookingQuickAccessRail(
            scheduleFuture: _scheduleFuture,
            hasActiveGym: hasActiveGym,
            onOpenBooking: () => context.go('/my-box'),
            onRefresh: _refreshSchedule,
          ),
          const SizedBox(height: appSpace2xl),
          const _SectionHeading('News', eyebrow: 'From your box'),
          const SizedBox(height: appSpaceMd),
          _AnnouncementRail(
            announcementsFuture: _announcementsFuture,
            canManageAnnouncements: canManageAnnouncements,
            hasActiveGym: hasActiveGym,
            onCreateAnnouncement: _openAnnouncementComposer,
            onEditAnnouncement: _openAnnouncementEditor,
            onDeleteAnnouncement: _deleteAnnouncement,
            onToggleLike: _toggleAnnouncementLike,
            onCreateComment: _createAnnouncementComment,
            onEditComment: _editAnnouncementComment,
            onDeleteComment: _deleteAnnouncementComment,
          ),
          const SizedBox(height: appSpace2xl),
          const _SectionHeading('Quick actions', eyebrow: 'Shortcuts'),
          const SizedBox(height: appSpaceMd),
          _QuickAccessGrid(
            profileAccountType: profile?.accountType,
            profileRole: profile?.role,
            hasActiveGym: hasActiveGym,
          ),
        ],
      ),
    );
  }

  Widget _buildOwnerHome({
    required BuildContext context,
    required bool hasActiveGym,
    required bool canManageAnnouncements,
  }) {
    if (!hasActiveGym) {
      // Owner without a box - show only "Create your first box"
      return DecoratedBox(
        decoration: appPageDecoration(),
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

    // Owner with active box - show Dashboard, News, Quick Access
    return DecoratedBox(
      decoration: appPageDecoration(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          appSpaceLg,
          appSpaceLg,
          appSpaceLg,
          appSpace3xl,
        ),
        children: [
          const _SectionHeading(
            'Box Dashboard',
            eyebrow: 'Operations',
          ),
          const SizedBox(height: appSpaceMd),
          const _OwnerDashboard(),
          const SizedBox(height: appSpace2xl),
          const _SectionHeading('News', eyebrow: 'Announcements'),
          const SizedBox(height: appSpaceMd),
          _AnnouncementRail(
            announcementsFuture: _announcementsFuture,
            canManageAnnouncements: canManageAnnouncements,
            hasActiveGym: hasActiveGym,
            onCreateAnnouncement: _openAnnouncementComposer,
            onEditAnnouncement: _openAnnouncementEditor,
            onDeleteAnnouncement: _deleteAnnouncement,
            onToggleLike: _toggleAnnouncementLike,
            onCreateComment: _createAnnouncementComment,
            onEditComment: _editAnnouncementComment,
            onDeleteComment: _deleteAnnouncementComment,
          ),
          const SizedBox(height: appSpace2xl),
          const _SectionHeading('Quick actions', eyebrow: 'Shortcuts'),
          const SizedBox(height: appSpaceMd),
          const _OwnerQuickAccessGrid(),
        ],
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
          if (today != null && today!.metconText.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              today!.metconText.trim(),
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
              style: TextStyle(
                color: appMutedText,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: appSpaceLg),
          _NextBookingStrip(
            booking: nextBooking,
            onTap: onOpenBooking,
          ),
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
    const weekdays = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
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
            Icon(
              Icons.event_outlined,
              color: appSubtleText,
              size: 18,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No class booked. Tap to reserve your slot.',
                style: TextStyle(
                  color: appSubtleText,
                  fontSize: 12.5,
                ),
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
                  style: const TextStyle(
                    color: appSubtleText,
                    fontSize: 12,
                  ),
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
    const weekdays = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
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

class _BookingQuickAccessRail extends StatelessWidget {
  const _BookingQuickAccessRail({
    required this.scheduleFuture,
    required this.hasActiveGym,
    required this.onOpenBooking,
    required this.onRefresh,
  });

  final Future<List<ScheduleClass>> scheduleFuture;
  final bool hasActiveGym;
  final VoidCallback onOpenBooking;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (!hasActiveGym) {
      return _AnnouncementEmptyState(
        icon: Icons.calendar_month_outlined,
        title: 'No active box selected',
        subtitle:
            'Pick or join a box first, then your booking shortcut and reserved classes appear here.',
        actionLabel: null,
        onTap: null,
      );
    }

    return FutureBuilder<List<ScheduleClass>>(
      future: scheduleFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoadingState(height: 220);
        }
        if (snapshot.hasError) {
          return _AnnouncementEmptyState(
            icon: Icons.error_outline,
            title: 'Couldn’t load your bookings',
            subtitle: errorMessageFrom(
              snapshot.error!,
              fallback: 'Class shortcuts are unavailable right now.',
            ),
            actionLabel: 'Retry',
            onTap: onRefresh,
          );
        }

        final now = DateTime.now();
        final bookedItems =
            (snapshot.data ?? const <ScheduleClass>[])
                .where((item) => item.isBooked && item.startTime.isAfter(now))
                .toList()
              ..sort((a, b) => a.startTime.compareTo(b.startTime));

        return SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: bookedItems.isEmpty ? 2 : bookedItems.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _BookingLauncherCard(onTap: onOpenBooking);
              }
              if (bookedItems.isEmpty) {
                return const _BookingPlaceholderCard();
              }
              return _BookedClassCard(
                item: bookedItems[index - 1],
                onTap: onOpenBooking,
              );
            },
          ),
        );
      },
    );
  }
}

class _BookingLauncherCard extends StatelessWidget {
  const _BookingLauncherCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 196,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(appRadiusXl),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(appRadiusXl),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [appPrimary, Color(0xFF3D4FE0)],
              ),
              boxShadow: const [
                BoxShadow(
                  color: appPrimarySoft,
                  blurRadius: 32,
                  offset: Offset(0, 20),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(appSpaceLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Color(0x33FFFFFF),
                    child: Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  Spacer(),
                  Text(
                    'Book a class',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Reserve your next slot in seconds.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xCCFFFFFF),
                      height: 1.35,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BookingPlaceholderCard extends StatelessWidget {
  const _BookingPlaceholderCard();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 232,
      child: AppCard(
        radius: appRadiusXl,
        padding: const EdgeInsets.all(appSpaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            AppAccentBadge(
              icon: Icons.event_busy_outlined,
              color: appPrimary,
            ),
            Spacer(),
            Text(
              'No class booked',
              style: TextStyle(
                color: appText,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Reserve one and it stays pinned here.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: appSubtleText,
                height: 1.4,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookedClassCard extends StatelessWidget {
  const _BookedClassCard({required this.item, required this.onTap});

  final ScheduleClass item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final startLabel = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(item.startTime.toLocal()),
      alwaysUse24HourFormat: true,
    );
    final dayLabel = localizations.formatShortDate(item.startTime.toLocal());
    return SizedBox(
      width: 248,
      child: AppCard(
        onTap: onTap,
        radius: appRadiusXl,
        padding: const EdgeInsets.all(appSpaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                AppAccentBadge(
                  icon: Icons.check_circle_outline_rounded,
                  color: appPrimary,
                ),
                Spacer(),
                AppPill(label: 'Booked', intent: AppPillIntent.primary),
              ],
            ),
            const Spacer(),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                color: appText,
                fontWeight: FontWeight.w800,
                fontSize: 19,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$dayLabel · $startLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: appMutedText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.assignedTrainer == null
                  ? item.classType
                  : '${item.classType} · ${item.assignedTrainer!.displayName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: appSubtleText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementRail extends StatefulWidget {
  const _AnnouncementRail({
    required this.announcementsFuture,
    required this.canManageAnnouncements,
    required this.hasActiveGym,
    required this.onCreateAnnouncement,
    required this.onEditAnnouncement,
    required this.onDeleteAnnouncement,
    required this.onToggleLike,
    required this.onCreateComment,
    required this.onEditComment,
    required this.onDeleteComment,
  });

  final Future<List<Announcement>> announcementsFuture;
  final bool canManageAnnouncements;
  final bool hasActiveGym;
  final Future<void> Function() onCreateAnnouncement;
  final Future<void> Function(Announcement announcement) onEditAnnouncement;
  final Future<void> Function(Announcement announcement) onDeleteAnnouncement;
  final Future<void> Function(Announcement announcement) onToggleLike;
  final Future<void> Function(Announcement announcement, String body)
  onCreateComment;
  final Future<void> Function(AnnouncementComment comment, String body)
  onEditComment;
  final Future<void> Function(AnnouncementComment comment) onDeleteComment;

  @override
  State<_AnnouncementRail> createState() => _AnnouncementRailState();
}

class _AnnouncementRailState extends State<_AnnouncementRail> {
  List<Announcement>? _cached;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Announcement>>(
      future: widget.announcementsFuture,
      builder: (context, snapshot) {
        if (!widget.hasActiveGym) {
          return _AnnouncementEmptyState(
            icon: Icons.campaign_outlined,
            title: 'No active box selected',
            subtitle:
                'Announcements appear once you are inside an active box context.',
            actionLabel: null,
            onTap: null,
          );
        }

        // Keep the cached list up-to-date whenever fresh data arrives.
        if (snapshot.hasData) {
          _cached = snapshot.data;
        }

        // On initial load (no cache yet) show a spinner.
        if (snapshot.connectionState == ConnectionState.waiting &&
            _cached == null) {
          return const AppLoadingState(height: 180);
        }

        // Show errors only when there is no cached data to fall back on.
        if (snapshot.hasError && _cached == null) {
          return _AnnouncementEmptyState(
            icon: Icons.error_outline,
            title: 'Failed to load announcements',
            subtitle: errorMessageFrom(
              snapshot.error!,
              fallback: 'Announcements could not be loaded.',
            ),
            actionLabel:
                widget.canManageAnnouncements ? 'Try posting instead' : null,
            onTap:
                widget.canManageAnnouncements
                    ? widget.onCreateAnnouncement
                    : null,
          );
        }

        final announcements = _cached ?? const <Announcement>[];
        if (announcements.isEmpty) {
          return _AnnouncementEmptyState(
            icon: Icons.campaign_outlined,
            title: 'No announcements yet',
            subtitle: widget.canManageAnnouncements
                ? 'Post the first update so athletes see a real gym news feed instead of placeholders.'
                : 'Your coaches and admins have not posted any announcements yet.',
            actionLabel:
                widget.canManageAnnouncements ? 'Create Announcement' : null,
            onTap:
                widget.canManageAnnouncements
                    ? widget.onCreateAnnouncement
                    : null,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.canManageAnnouncements) ...[
              _AnnouncementComposerBanner(onTap: widget.onCreateAnnouncement),
              const SizedBox(height: 12),
            ],
            for (final (index, announcement) in announcements.indexed) ...[
              _AnnouncementCard(
                key: ValueKey(announcement.id),
                announcement: announcement,
                canManage: announcement.canManage,
                onEdit: () => widget.onEditAnnouncement(announcement),
                onDelete: () => widget.onDeleteAnnouncement(announcement),
                onToggleLike: () => widget.onToggleLike(announcement),
                onCreateComment: (body) =>
                    widget.onCreateComment(announcement, body),
                onEditComment: widget.onEditComment,
                onDeleteComment: widget.onDeleteComment,
              ),
              if (index < announcements.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _AnnouncementComposerBanner extends StatelessWidget {
  const _AnnouncementComposerBanner({required this.onTap});

  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [appSurface, appSurfaceAlt],
          ),
          border: Border.all(color: appBorder),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 10,
          ),
          leading: const AppAccentBadge(
            icon: Icons.add_comment_outlined,
            color: appPrimary,
          ),
          title: const Text(
            'Post a new announcement',
            style: TextStyle(color: appText, fontWeight: FontWeight.w800),
          ),
          subtitle: const Text(
            'Share schedule changes, event reminders, or coach notes right on the home feed.',
            style: TextStyle(color: appSubtleText, height: 1.45),
          ),
          trailing: const Icon(Icons.north_east_rounded, color: appPrimary),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Thin shim around the shared [AppEmptyState] so the rest of this file's
/// call sites stay unchanged. The signature collapses to whatever the shared
/// primitive offers; tap callbacks become a synchronous VoidCallback (the
/// async work is fire-and-forget — the parent already handles its own loading
/// state).
class _AnnouncementEmptyState extends StatelessWidget {
  const _AnnouncementEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: icon,
      title: title,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onAction: onTap == null ? null : () => onTap!(),
    );
  }
}

class _AnnouncementCard extends StatefulWidget {
  const _AnnouncementCard({
    super.key,
    required this.announcement,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleLike,
    required this.onCreateComment,
    required this.onEditComment,
    required this.onDeleteComment,
  });

  final Announcement announcement;
  final bool canManage;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;
  final Future<void> Function() onToggleLike;
  final Future<void> Function(String body) onCreateComment;
  final Future<void> Function(AnnouncementComment comment, String body)
  onEditComment;
  final Future<void> Function(AnnouncementComment comment) onDeleteComment;

  @override
  State<_AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends State<_AnnouncementCard> {
  final TextEditingController _commentController = TextEditingController();
  bool _commentSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [appSurface, appSurfaceAlt],
        ),
        border: Border.all(color: appBorder),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          collapsedIconColor: _homeAccent,
          iconColor: _homeAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.announcement.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Posted by ${widget.announcement.authorName} · ${_formatAnnouncementDate(widget.announcement.createdAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: appSubtleText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          widget.announcement.likedByMe
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 13,
                          color: widget.announcement.likedByMe
                              ? _homeDanger
                              : appSubtleText,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${widget.announcement.likeCount}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: appSubtleText,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 13,
                          color: appSubtleText,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${widget.announcement.commentCount}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: appSubtleText,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.canManage)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, color: appSubtleText),
                  color: appSurface,
                  onSelected: (value) {
                    if (value == 'edit') {
                      widget.onEdit();
                    } else if (value == 'delete') {
                      widget.onDelete();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: Text('Edit announcement'),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('Delete announcement'),
                    ),
                  ],
                ),
              const SizedBox(width: 8),
            ],
          ),
          subtitle: widget.announcement.imageUrl == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        widget.announcement.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: appSurfaceAlt,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: appSubtleText,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
          children: [
            if (widget.announcement.updatedAt.isAfter(
              widget.announcement.createdAt,
            )) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Last updated ${_formatAnnouncementDate(widget.announcement.updatedAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: appSubtleText,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.announcement.description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: appMutedText,
                  height: 1.55,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _AnnouncementMetricButton(
                  icon: widget.announcement.likedByMe
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label: '${widget.announcement.likeCount} likes',
                  accent: widget.announcement.likedByMe
                      ? _homeDanger
                      : _homeAccent,
                  onTap: widget.onToggleLike,
                ),
                _AnnouncementStaticPill(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: '${widget.announcement.commentCount} comments',
                ),
              ],
            ),
            const SizedBox(height: 18),
            _AnnouncementCommentComposer(
              controller: _commentController,
              isSubmitting: _commentSubmitting,
              onSubmit: _submitComment,
            ),
            if (widget.announcement.comments.isNotEmpty) ...[
              const SizedBox(height: 18),
              for (final (index, comment)
                  in widget.announcement.comments.indexed) ...[
                _AnnouncementCommentCard(
                  comment: comment,
                  onEdit: () => _promptEditComment(comment),
                  onDelete: () => widget.onDeleteComment(comment),
                ),
                if (index < widget.announcement.comments.length - 1)
                  const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _submitComment() async {
    final body = _commentController.text.trim();
    if (body.isEmpty || _commentSubmitting) {
      return;
    }
    setState(() => _commentSubmitting = true);
    try {
      await widget.onCreateComment(body);
      _commentController.clear();
    } finally {
      if (mounted) {
        setState(() => _commentSubmitting = false);
      }
    }
  }

  Future<void> _promptEditComment(AnnouncementComment comment) async {
    final controller = TextEditingController(text: comment.body);
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: appSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: appBorder),
        ),
        title: const Text('Edit comment', style: TextStyle(color: appText)),
        content: TextField(
          controller: controller,
          maxLines: 4,
          style: const TextStyle(color: appText),
          decoration: const InputDecoration(
            hintText: 'Update your comment',
            hintStyle: TextStyle(color: appSubtleText),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == null || saved.isEmpty) {
      return;
    }
    await widget.onEditComment(comment, saved);
  }
}

class _AnnouncementMetricButton extends StatelessWidget {
  const _AnnouncementMetricButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: accent.withOpacity(0.12),
            border: Border.all(color: accent.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: appText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnouncementStaticPill extends StatelessWidget {
  const _AnnouncementStaticPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: appSurfaceAlt,
        border: Border.all(color: appBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: appSubtleText),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: appText, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementCommentComposer extends StatelessWidget {
  const _AnnouncementCommentComposer({
    required this.controller,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool isSubmitting;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: appSurfaceAlt,
        border: Border.all(color: appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            style: const TextStyle(color: appText),
            decoration: const InputDecoration(
              hintText: 'Add a comment',
              hintStyle: TextStyle(color: appSubtleText),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: isSubmitting ? null : onSubmit,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              icon: isSubmitting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: const Text('Post'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementCommentCard extends StatelessWidget {
  const _AnnouncementCommentCard({
    required this.comment,
    required this.onEdit,
    required this.onDelete,
  });

  final AnnouncementComment comment;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: appSurfaceAlt,
        border: Border.all(color: appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comment.authorName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: appText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatAnnouncementDate(comment.updatedAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: appSubtleText,
                      ),
                    ),
                  ],
                ),
              ),
              if (comment.canManage)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, color: appSubtleText),
                  color: appSurface,
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit();
                    } else if (value == 'delete') {
                      onDelete();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: Text('Edit comment'),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('Delete comment'),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            comment.body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: appMutedText,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatAnnouncementDate(DateTime value) {
  final local = value.toLocal();
  final month = switch (local.month) {
    1 => 'Jan',
    2 => 'Feb',
    3 => 'Mar',
    4 => 'Apr',
    5 => 'May',
    6 => 'Jun',
    7 => 'Jul',
    8 => 'Aug',
    9 => 'Sep',
    10 => 'Oct',
    11 => 'Nov',
    _ => 'Dec',
  };
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} $month · $hour:$minute';
}

class _HomeAction {
  const _HomeAction({
    required this.icon,
    required this.title,
    required this.route,
    required this.accentColor,
  });

  final IconData icon;
  final String title;
  final String route;
  final Color accentColor;
}

class _QuickAccessGrid extends StatelessWidget {
  const _QuickAccessGrid({
    required this.profileAccountType,
    required this.profileRole,
    required this.hasActiveGym,
  });

  final AccountType? profileAccountType;
  final UserRole? profileRole;
  final bool hasActiveGym;

  @override
  Widget build(BuildContext context) {
    final actions = <_HomeAction>[
      if (profileAccountType == AccountType.admin &&
          profileRole == UserRole.admin)
        const _HomeAction(
          icon: Icons.group_outlined,
          title: 'Review Join Requests',
          route: '/gym-requests',
          accentColor: appPrimary,
        )
      else
        const _HomeAction(
          icon: Icons.search_outlined,
          title: 'Find a Box',
          route: '/gyms',
          accentColor: appPrimary,
        ),
      if (profileRole == UserRole.trainer || profileRole == UserRole.admin)
        const _HomeAction(
          icon: Icons.edit_calendar_outlined,
          title: 'Open Schedule',
          route: '/my-box',
          accentColor: appPrimary,
        )
      else
        const _HomeAction(
          icon: Icons.menu_book_outlined,
          title: 'Open Logbook',
          route: '/logbook',
          accentColor: appPrimary,
        ),
      _HomeAction(
        icon: hasActiveGym
            ? Icons.local_fire_department_outlined
            : Icons.notifications_outlined,
        title: hasActiveGym ? 'See Programming' : 'Open Notifications',
        route: hasActiveGym ? '/programming' : '/notifications',
        accentColor: _homeAccent,
      ),
    ];

    return Column(
      children: [
        for (final (index, action) in actions.indexed) ...[
          _ActionTile(action: action),
          if (index < actions.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});

  final _HomeAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: () => context.go(action.route),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          AppAccentBadge(icon: action.icon, color: action.accentColor),
          const SizedBox(width: appSpaceMd),
          Expanded(
            child: Text(
              action.title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: appText,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right_rounded,
            color: appSubtleText,
            size: 22,
          ),
        ],
      ),
    );
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
        borderRadius: BorderRadius.circular(26),
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

class _AnnouncementComposerDialog extends StatefulWidget {
  const _AnnouncementComposerDialog({
    this.existing,
    required this.repository,
  });

  final Announcement? existing;
  final AnnouncementRepository repository;

  @override
  State<_AnnouncementComposerDialog> createState() =>
      _AnnouncementComposerDialogState();
}

class _AnnouncementComposerDialogState
    extends State<_AnnouncementComposerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _imagePicker = ImagePicker();
  bool _isSaving = false;
  bool _isUploadingImage = false;
  Uint8List? _selectedImageBytes;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _titleController.text = existing.title;
      _descriptionController.text = existing.description;
      _imageUrlController.text = existing.imageUrl ?? '';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickImageFromGallery() async {
    if (_isSaving || _isUploadingImage) {
      return;
    }
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1800,
      );
      if (picked == null) {
        return;
      }
      final bytes = await picked.readAsBytes();
      final contentType = switch (picked.mimeType) {
        final type? when type.trim().isNotEmpty => type,
        _ when picked.name.toLowerCase().endsWith('.png') => 'image/png',
        _ when picked.name.toLowerCase().endsWith('.webp') => 'image/webp',
        _ => 'image/jpeg',
      };
      setState(() {
        _isUploadingImage = true;
        _selectedImageBytes = bytes;
      });
      final imageUrl = await widget.repository.uploadAnnouncementImage(
        bytes: bytes,
        filename: picked.name,
        contentType: contentType,
      );
      if (!mounted) {
        return;
      }
      _imageUrlController.text = imageUrl;
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(error, fallback: 'Failed to upload image'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_isSaving || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      if (_isEditing) {
        await widget.repository.updateAnnouncement(
          id: widget.existing!.id,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          imageUrl: _imageUrlController.text.trim().isEmpty
              ? null
              : _imageUrlController.text.trim(),
        );
      } else {
        await widget.repository.createAnnouncement(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          imageUrl: _imageUrlController.text.trim().isEmpty
              ? null
              : _imageUrlController.text.trim(),
        );
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessageFrom(
              error,
              fallback: _isEditing
                  ? 'Failed to update announcement'
                  : 'Failed to create announcement',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = (screenWidth - 32).clamp(
      100.0,
      mobileContentMaxWidth.toDouble(),
    );

    return AlertDialog(
      backgroundColor: appSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: appBorder),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(
        _isEditing ? 'Edit Announcement' : 'Create Announcement',
        style: const TextStyle(color: appText),
      ),
      content: SizedBox(
        width: dialogWidth,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(appRadiusLg),
                    color: appSurfaceAlt,
                    border: Border.all(color: appBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add a gallery image',
                        style: TextStyle(
                          color: appText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Pick a photo from your phone. It will upload and attach automatically.',
                        style: TextStyle(color: appMutedText, height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      if (_selectedImageBytes != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Image.memory(
                              _selectedImageBytes!,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: _isUploadingImage
                                ? null
                                : _pickImageFromGallery,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 44),
                            ),
                            icon: _isUploadingImage
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.photo_library_outlined),
                            label: Text(
                              _isUploadingImage
                                  ? 'Uploading...'
                                  : 'Choose from gallery',
                            ),
                          ),
                          if (_imageUrlController.text.trim().isNotEmpty)
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _imageUrlController.clear();
                                  _selectedImageBytes = null;
                                });
                              },
                              child: const Text('Remove image'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _titleController,
                  style: const TextStyle(color: appText),
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'Saturday schedule update',
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Title is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _descriptionController,
                  minLines: 4,
                  maxLines: 7,
                  style: const TextStyle(color: appText),
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Write the actual update athletes should read.',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Description is required';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: Text(
            _isSaving
                ? (_isEditing ? 'Saving...' : 'Posting...')
                : (_isEditing ? 'Save Changes' : 'Post Announcement'),
          ),
        ),
      ],
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

class _OwnerDashboardContent extends StatelessWidget {
  const _OwnerDashboardContent({required this.overview});

  final AdminAnalyticsOverview overview;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Key metrics row
        Row(
          children: [
            Expanded(
              child: _DashboardMetricCard(
                icon: Icons.people_outline,
                label: 'Active Members',
                value: '${overview.activeMembers}',
                accentColor: appPrimary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DashboardMetricCard(
                icon: Icons.person_add_outlined,
                label: 'Join Requests',
                value: '${overview.pendingJoinRequests}',
                accentColor:
                    overview.pendingJoinRequests > 0 ? _perfAmber : appPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _DashboardMetricCard(
                icon: Icons.event_available_outlined,
                label: 'Attendance Rate',
                value: '${(overview.attendanceRateInWindow * 100).toStringAsFixed(0)}%',
                accentColor: _getPerformanceColor(overview.attendanceRateInWindow),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DashboardMetricCard(
                icon: Icons.trending_up_outlined,
                label: 'Utilization',
                value: '${(overview.utilizationRateInWindow * 100).toStringAsFixed(0)}%',
                accentColor: _getPerformanceColor(overview.utilizationRateInWindow),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(appSpaceLg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _DashboardStat(
                label: 'Classes',
                value: '${overview.upcomingClassesNext7Days}',
                sublabel: 'next 7 days',
              ),
              Container(width: 1, height: 36, color: appBorder),
              _DashboardStat(
                label: 'Bookings',
                value: '${overview.upcomingBookingsNext7Days}',
                sublabel: 'upcoming',
              ),
              Container(width: 1, height: 36, color: appBorder),
              _DashboardStat(
                label: 'No-shows',
                value: '${overview.noShowsInWindow}',
                sublabel: 'last ${overview.windowDays}d',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getPerformanceColor(double rate) {
    if (rate >= 0.75) return _perfGreen;
    if (rate >= 0.50) return _perfAmber;
    return _perfRed;
  }
}

class _DashboardMetricCard extends StatelessWidget {
  const _DashboardMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(appSpaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAccentBadge(icon: icon, color: accentColor),
          const SizedBox(height: appSpaceMd),
          Text(
            value,
            style: const TextStyle(
              color: appText,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: appSubtleText,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardStat extends StatelessWidget {
  const _DashboardStat({
    required this.label,
    required this.value,
    required this.sublabel,
  });

  final String label;
  final String value;
  final String sublabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: appSubtleText,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: appText,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          sublabel,
          style: const TextStyle(
            color: appMutedText,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// Owner Quick Access Grid
class _OwnerQuickAccessGrid extends StatelessWidget {
  const _OwnerQuickAccessGrid();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ActionTile(
          action: const _HomeAction(
            icon: Icons.group_outlined,
            title: 'Review Join Requests',
            route: '/gym-requests',
            accentColor: appPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _ActionTile(
          action: const _HomeAction(
            icon: Icons.edit_calendar_outlined,
            title: 'Operate the Box',
            route: '/my-box',
            accentColor: appPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _ActionTile(
          action: const _HomeAction(
            icon: Icons.analytics_outlined,
            title: 'View Full Analytics',
            route: '/admin-analytics',
            accentColor: _homeAccent,
          ),
        ),
      ],
    );
  }
}
