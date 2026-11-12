import 'package:app/core/errors/error_message.dart';
import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/admin_analytics/application/admin_analytics_controller.dart';
import 'package:app/features/admin_analytics/domain/models/owner_dashboard_data.dart';
import 'package:app/features/calendar/data/repositories/api_schedule_repository.dart';
import 'package:app/features/calendar/domain/models/schedule_class.dart';
import 'package:app/features/calendar/presentation/widgets/class_type_badge.dart';
import 'package:app/features/gyms/data/repositories/api_gym_repository.dart';
import 'package:app/features/memberships/data/membership_repository.dart';
import 'package:app/features/programming/data/repositories/api_programming_repository.dart';
import 'package:app/features/programming/domain/models/daily_workout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Owner dashboard (docs/admin-ui-reference.md §1): metrics, six-month
/// charts, and the day's activity (classes and the WOD). The review-window
/// analytics that used to live here are under Reports.
class OwnerDashboard extends ConsumerWidget {
  const OwnerDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(ownerDashboardProvider);
    final openRequests =
        (ref.watch(pendingJoinRequestsProvider).value?.length ?? 0) +
        (ref.watch(pendingPlanRequestsProvider).value?.length ?? 0);
    return dashboard.when(
      loading: () => const AppLoadingState(height: 220),
      error: (error, _) => AppEmptyState.error(
        title: 'Failed to load dashboard',
        subtitle: errorMessageFrom(error, fallback: 'Try again'),
        actionLabel: 'Retry',
        onAction: () => ref.invalidate(ownerDashboardProvider),
      ),
      data: (data) {
        final months = data.months;
        final current = months.isEmpty ? null : months.last;
        final previous = months.length < 2 ? null : months[months.length - 2];
        int churn(DashboardMonth? m) => m?.churnedMembers ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle('Metrics'),
            _Grid(
              minTileWidth: 200,
              children: [
                _MetricCard(
                  label: 'Members at risk',
                  value: '${data.membersAtRisk}',
                  hint: 'No class in ${data.atRiskDays} days',
                  onOpen: () => context.go('/members'),
                ),
                _MetricCard(
                  label: 'Churned members',
                  value: '${churn(current)}',
                  hint: 'This month',
                  trend: _trend(churn(current), churn(previous)),
                  // More churn is bad news.
                  invertTrend: true,
                  onOpen: () => context.go('/members'),
                ),
                _MetricCard(
                  label: 'Expiring memberships',
                  value: '${data.expiringMemberships}',
                  hint: 'Next ${data.expiringDays} days',
                  onOpen: () => context.go('/memberships'),
                ),
                _MetricCard(
                  label: 'Open requests',
                  value: '$openRequests',
                  hint: 'Join and plan requests',
                  onOpen: () => context.go('/members'),
                ),
              ],
            ),
            const SizedBox(height: appSpace2xl),
            const _SectionTitle('Last 6 months'),
            _Grid(
              minTileWidth: 240,
              children: [
                _ChartCard(
                  label: 'New members',
                  months: months,
                  value: (m) => m.newMembers.toDouble(),
                ),
                _ChartCard(
                  label: 'New memberships',
                  months: months,
                  value: (m) => m.newMemberships.toDouble(),
                ),
                _ChartCard(
                  label: 'Class utilisation',
                  months: months,
                  value: (m) => m.utilizationPercent,
                  percent: true,
                  area: true,
                ),
                _ChartCard(
                  label: 'Class registrations',
                  months: months,
                  value: (m) => m.registrations.toDouble(),
                  stacked: (m) => m.attended.toDouble(),
                  legend: 'Attended / booked',
                ),
              ],
            ),
            const SizedBox(height: appSpace2xl),
            const _Activity(),
          ],
        );
      },
    );
  }
}

/// Percent change from [previous] to [current]; null when there is nothing
/// to compare against.
int? _trend(num current, num previous) =>
    previous == 0 ? null : ((current - previous) * 100 / previous).round();

const _monthLabels = [
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: appSpaceMd),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: appText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Lays [children] out in equal columns, as many as fit at [minTileWidth].
class _Grid extends StatelessWidget {
  const _Grid({required this.children, required this.minTileWidth});

  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 4, 2 or 1 columns, so four cards never leave one alone on a row.
        final fit = (constraints.maxWidth / minTileWidth).floor();
        final columns = fit >= 4 ? 4 : (fit >= 2 ? 2 : 1);
        final width =
            (constraints.maxWidth - appSpaceMd * (columns - 1)) / columns;
        return Wrap(
          spacing: appSpaceMd,
          runSpacing: appSpaceMd,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

BoxDecoration _cardDecoration() => BoxDecoration(
  color: appSurface,
  borderRadius: BorderRadius.circular(appRadiusLg),
  border: Border.all(color: appBorder),
);

class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.percent, this.invert = false});

  final int percent;

  /// When rising is bad (e.g. churn).
  final bool invert;

  @override
  Widget build(BuildContext context) {
    final good = (percent >= 0) != invert;
    return AppPill(
      label: '${percent >= 0 ? '↑' : '↓'} ${percent.abs()}%',
      intent: good ? AppPillIntent.success : AppPillIntent.danger,
      dense: true,
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.hint,
    required this.onOpen,
    this.trend,
    this.invertTrend = false,
  });

  final String label;
  final String value;
  final String hint;
  final VoidCallback onOpen;
  final int? trend;
  final bool invertTrend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(appSpaceLg, appSpaceSm, 0, appSpaceLg),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: appMutedText, fontSize: 13),
                ),
              ),
              IconButton(
                tooltip: 'Open',
                visualDensity: VisualDensity.compact,
                onPressed: onOpen,
                icon: const Icon(
                  Icons.open_in_full_rounded,
                  size: 16,
                  color: appSubtleText,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: appText,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              if (trend != null) ...[
                const SizedBox(width: appSpaceSm),
                _TrendBadge(percent: trend!, invert: invertTrend),
              ],
            ],
          ),
          const SizedBox(height: appSpaceXs),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: appSubtleText, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Headline number for the current month, trend vs. last month, and a small
/// six-month chart: bars, an area, or bars with a stacked lower part.
class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.label,
    required this.months,
    required this.value,
    this.stacked,
    this.percent = false,
    this.area = false,
    this.legend,
  });

  final String label;
  final List<DashboardMonth> months;
  final double Function(DashboardMonth) value;

  /// Lower part of each bar (drawn in the strong accent), e.g. attended out
  /// of booked.
  final double Function(DashboardMonth)? stacked;
  final bool percent;
  final bool area;
  final String? legend;

  @override
  Widget build(BuildContext context) {
    final values = [for (final m in months) value(m)];
    final current = values.isEmpty ? 0.0 : values.last;
    final previous = values.length < 2 ? 0.0 : values[values.length - 2];
    final trend = _trend(current, previous);
    final max = values.fold<double>(0, (a, b) => b > a ? b : a);
    String format(double v) =>
        percent ? '${v.toStringAsFixed(0)}%' : v.toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(appSpaceLg),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: appMutedText, fontSize: 13),
          ),
          const SizedBox(height: appSpaceXs),
          Row(
            children: [
              Text(
                format(current),
                style: const TextStyle(
                  color: appText,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (trend != null) ...[
                const SizedBox(width: appSpaceSm),
                _TrendBadge(percent: trend),
              ],
            ],
          ),
          const SizedBox(height: appSpaceMd),
          SizedBox(
            height: 72,
            child: area
                ? CustomPaint(
                    size: Size.infinite,
                    painter: _AreaPainter(
                      values: values,
                      max: percent ? 100 : max,
                    ),
                  )
                : Stack(
                    children: [
                      // Gridlines only (no values): the §0 chart rules.
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _AreaPainter(values: const [], max: 0),
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < months.length; i++) ...[
                            if (i > 0) const SizedBox(width: appSpaceSm),
                            Expanded(
                              child: _Bar(
                                fraction: max == 0 ? 0 : values[i] / max,
                                lowerFraction: stacked == null || max == 0
                                    ? null
                                    : stacked!(months[i]) / max,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: appSpaceXs),
          Row(
            children: [
              for (var i = 0; i < months.length; i++) ...[
                // Same gaps as the bars so each label sits under its bar.
                if (i > 0 && !area) const SizedBox(width: appSpaceSm),
                Expanded(
                  child: Text(
                    _monthLabels[months[i].month.month - 1],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: appSubtleText,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (legend != null) ...[
            const SizedBox(height: appSpaceXs),
            Text(
              legend!,
              style: const TextStyle(color: appSubtleText, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, this.lowerFraction});

  final double fraction;
  final double? lowerFraction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final total = (fraction.clamp(0.0, 1.0) * height).clamp(2.0, height);
        final lower = lowerFraction == null
            ? null
            : (lowerFraction!.clamp(0.0, 1.0) * height).clamp(0.0, total);
        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: total,
            decoration: BoxDecoration(
              // Stacked bars: the upper part in the second stack colour.
              color: lower == null ? appPrimary : appPrimaryHairline,
              borderRadius: BorderRadius.circular(appRadiusSm),
            ),
            alignment: Alignment.bottomCenter,
            child: lower == null
                ? null
                : Container(
                    height: lower,
                    decoration: BoxDecoration(
                      color: appPrimary,
                      borderRadius: BorderRadius.circular(appRadiusSm),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _AreaPainter extends CustomPainter {
  _AreaPainter({required this.values, required this.max});

  final List<double> values;
  final double max;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = appBorder
      ..strokeWidth = 1;
    for (final y in [0.0, size.height / 2, size.height]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.length < 2 || max <= 0) return;
    // Points sit at the centre of each month's label column.
    final step = size.width / values.length;
    final points = [
      for (var i = 0; i < values.length; i++)
        Offset(
          step * (i + 0.5),
          size.height - (values[i] / max).clamp(0.0, 1.0) * size.height,
        ),
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    final fill = Path.from(line)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = appPrimarySoft);
    canvas.drawPath(
      line,
      Paint()
        ..color = appPrimary
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_AreaPainter old) =>
      old.values != values || old.max != max;
}

/// Activity: the selected day's classes (left) and its WOD (right), with
/// Today and ‹ › to move between days.
class _Activity extends ConsumerStatefulWidget {
  const _Activity();

  @override
  ConsumerState<_Activity> createState() => _ActivityState();
}

class _ActivityState extends ConsumerState<_Activity> {
  DateTime _day = _dateOnly(DateTime.now());

  void _shift(int days) =>
      setState(() => _day = DateTime(_day.year, _day.month, _day.day + days));

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final classes = [
      for (final c in ref.watch(scheduleListProvider).value ?? const [])
        if (_dateOnly(c.startTime) == _day) c,
    ]..sort((a, b) => a.startTime.compareTo(b.startTime));
    final workout = (ref.watch(programmingListProvider).value ?? const [])
        .where((w) => _dateOnly(w.scheduledDate) == _day)
        .firstOrNull;
    final isToday = _day == _dateOnly(DateTime.now());

    final classesCard = Container(
      decoration: _cardDecoration(),
      padding: const EdgeInsets.all(appSpaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Classes ${classes.length}',
            style: const TextStyle(color: appText, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: appSpaceMd),
          if (classes.isEmpty)
            const Text(
              'No classes on this day.',
              style: TextStyle(color: appSubtleText),
            )
          else
            for (final c in classes) _ClassRow(item: c),
        ],
      ),
    );
    final programCard = Container(
      decoration: _cardDecoration(),
      padding: const EdgeInsets.all(appSpaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Programs',
            style: TextStyle(color: appText, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: appSpaceMd),
          if (workout == null)
            const Text(
              'No WOD programmed.',
              style: TextStyle(color: appSubtleText),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    workout.title,
                    style: const TextStyle(
                      color: appText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                AppPill(
                  label: workout.isPublished ? 'Published' : 'Draft',
                  intent: workout.isPublished
                      ? AppPillIntent.success
                      : AppPillIntent.warning,
                  dense: true,
                ),
              ],
            ),
            const SizedBox(height: appSpaceSm),
            for (var i = 0; i < workout.sections.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: appSpaceXs),
                child: Text(
                  '${i + 1}  ${_sectionLabel(workout.sections[i])}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: appMutedText, fontSize: 13),
                ),
              ),
          ],
          const SizedBox(height: appSpaceSm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.go('/programs'),
              child: const Text('Manage programs'),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          'Activity · ${localizations.formatMediumDate(_day)}',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: isToday
                    ? null
                    : () => setState(() => _day = _dateOnly(DateTime.now())),
                child: const Text('Today'),
              ),
              IconButton(
                tooltip: 'Previous day',
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                tooltip: 'Next day',
                onPressed: () => _shift(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 720
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: classesCard),
                    const SizedBox(width: appSpaceMd),
                    Expanded(flex: 2, child: programCard),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    classesCard,
                    const SizedBox(height: appSpaceMd),
                    programCard,
                  ],
                ),
        ),
      ],
    );
  }

  static String _sectionLabel(DailyWorkoutSection section) =>
      section.title.isNotEmpty ? section.title : section.description;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

class _ClassRow extends StatelessWidget {
  const _ClassRow({required this.item});

  final ScheduleClass item;

  @override
  Widget build(BuildContext context) {
    // `06:00 – 07:00` as in the reference; fits the fixed time column.
    String time(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final end = item.startTime.add(Duration(minutes: item.durationMinutes));
    final now = DateTime.now();
    final status = end.isBefore(now)
        ? 'Ended'
        : item.startTime.isBefore(now)
        ? 'In progress'
        : 'Starts ${time(item.startTime)}';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: appSpaceSm + 2),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: appBorder)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              '${time(item.startTime)} – ${time(end)}',
              style: const TextStyle(color: appMutedText, fontSize: 12.5),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: appText,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: classTypeColor(item.type),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: appSpaceXs),
                    Expanded(
                      child: Text(
                        '${item.type.label} · $status',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: appSubtleText,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          AppPill(
            label: '${item.bookedCount} of ${item.capacity}',
            intent: item.isFull ? AppPillIntent.warning : AppPillIntent.neutral,
            dense: true,
          ),
        ],
      ),
    );
  }
}
