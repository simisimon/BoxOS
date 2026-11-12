import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/admin_analytics/application/admin_analytics_controller.dart';
import 'package:app/features/admin_analytics/domain/models/admin_analytics_overview.dart';
import 'package:app/features/admin_analytics/presentation/widgets/admin_analytics_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Chart colours from the §0 table.
const _perfRed = appDanger;
const _perfAmber = appWarning;
const _perfGreen = appSuccess;

/// Reports → Attendance (docs/admin-ui-reference.md §8, the [inferred]
/// Attendance report): the review-window KPIs, daily attendance, busiest
/// classes and the full analytics. Moved here from the owner dashboard.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(adminAnalyticsOverviewProvider);

    return ListView(
      padding: const EdgeInsets.all(appSpaceLg),
      children: [
        analyticsAsync.when(
          data: (overview) => _OwnerDashboardContent(overview: overview),
          loading: () => const AppLoadingState(height: 220),
          error: (error, _) => AppEmptyState.error(
            title: 'Failed to load dashboard',
            subtitle: error.toString(),
          ),
        ),
      ],
    );
  }
}

class _OwnerDashboardContent extends ConsumerWidget {
  const _OwnerDashboardContent({required this.overview});

  final AdminAnalyticsOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = overview.windowDays;
    final attendancePct = overview.attendanceRateInWindow.round();
    final utilizationPct = overview.utilizationRateInWindow.round();
    final noShowPct = overview.noShowRateInWindow.round();

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
            _FullAnalyticsCard(windowDays: window),
          ],
        );
      },
    );
  }
}

/// Dashboard title bar: OPERATIONS eyebrow + "Box Dashboard" display title on
/// the left, review-window selector on the right. Wraps the selector beneath
/// the title on narrow widths.
class _WindowBar extends StatelessWidget {
  const _WindowBar({
    required this.selectedWindow,
    required this.onWindowSelected,
  });

  final int selectedWindow;
  final ValueChanged<int> onWindowSelected;

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
            Text('REPORTS', style: appMono(fontSize: 10, letterSpacing: 1.6)),
            const SizedBox(height: 5),
            Text(
              'Attendance',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(letterSpacing: -0.4),
            ),
          ],
        ),
        _WindowSelector(selected: selectedWindow, onSelected: onWindowSelected),
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
                    color: days == selected ? appInverseText : appSubtleText,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Full analytics, folded at the bottom of the dashboard; tapping the header
/// unfolds them in place. Uses the same review window as the KPIs above.
class _FullAnalyticsCard extends StatefulWidget {
  const _FullAnalyticsCard({required this.windowDays});

  final int windowDays;

  @override
  State<_FullAnalyticsCard> createState() => _FullAnalyticsCardState();
}

class _FullAnalyticsCardState extends State<_FullAnalyticsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: appPanelDecoration(radius: appRadiusMd),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'FULL ANALYTICS · ${widget.windowDays}D',
                        style: appMono(fontSize: 10, letterSpacing: 1.4),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: appSubtleText,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: AdminAnalyticsDetails(),
            ),
        ],
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
                ? const [appPrimary, appPrimary]
                : const [appPrimary, appPrimaryHairline],
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
