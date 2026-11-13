part of 'owner_dashboard.dart';

/// Athlete Home: the day's classes to book right in the rows next to the WOD
/// of the day, then the box's announcements (likes and comments). Messages
/// is the box chat; news lives here.
class AthleteHome extends StatelessWidget {
  const AthleteHome({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Activity(title: 'Book a class', bookable: true, manager: false),
        SizedBox(height: appSpace2xl),
        _SectionTitle('Announcements'),
        AnnouncementFeedSection(showHeader: false),
      ],
    );
  }
}

/// Trainer Dashboard: a few numbers about the classes they coach, then the
/// owner's Activity section narrowed to "Coached by me". No business
/// metrics; those endpoints are the owner's.
class TrainerDashboard extends ConsumerWidget {
  const TrainerDashboard({super.key, required this.userId});

  final int? userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref.watch(scheduleListProvider).value ?? const [];
    final today = _dateOnly(DateTime.now());
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final mine = [
      for (final c in classes)
        if (userId != null && c.assignedTrainer?.id == userId) c,
    ];
    final mineThisWeek = mine.where(
      (c) => !c.startTime.isBefore(weekStart) && c.startTime.isBefore(weekEnd),
    );
    final mineToday = mine.where((c) => _dateOnly(c.startTime) == today);
    void openClasses() => context.go('/my-box');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('My classes'),
        _Grid(
          minTileWidth: 200,
          children: [
            _MetricCard(
              label: 'Classes this week',
              value: '${mineThisWeek.length}',
              hint: 'Coached by you',
              onOpen: openClasses,
            ),
            _MetricCard(
              label: 'Classes today',
              value: '${mineToday.length}',
              hint: 'Coached by you',
              onOpen: openClasses,
            ),
            _MetricCard(
              label: 'Registrations today',
              value:
                  '${mineToday.fold<int>(0, (sum, c) => sum + c.bookedCount)}',
              hint: 'In your classes',
              onOpen: openClasses,
            ),
            _MetricCard(
              label: 'Waiting lists today',
              value:
                  '${mineToday.fold<int>(0, (sum, c) => sum + c.waitlistCount)}',
              hint: 'In your classes',
              onOpen: openClasses,
            ),
          ],
        ),
        const SizedBox(height: appSpace2xl),
        _Activity(coachUserId: userId),
      ],
    );
  }
}
