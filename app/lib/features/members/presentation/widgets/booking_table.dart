import 'package:app/core/presentation/app_chrome.dart';
import 'package:app/core/presentation/components/components.dart';
import 'package:app/features/calendar/presentation/widgets/class_type_badge.dart';
import 'package:app/features/members/domain/member_booking.dart';
import 'package:app/features/members/presentation/widgets/member_roster.dart'
    show formatShortDate;
import 'package:flutter/material.dart';

/// A member's classes as a table: date, time, class (type dot), coach and a
/// status pill. Used by the owner's member detail (Classes tab) and the
/// athlete's Profile › Bookings.
class BookingTable extends StatelessWidget {
  const BookingTable({
    super.key,
    required this.rows,
    required this.emptyText,
    this.onCancel,
    this.shrinkWrap = false,
  });

  final List<MemberBooking> rows;
  final String emptyText;

  /// Adds a Cancel action to future bookings and waitlist spots.
  final ValueChanged<MemberBooking>? onCancel;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return AppDataTable<MemberBooking>(
      shrinkWrap: shrinkWrap,
      columns: [
        const AppTableColumn('Date', flex: 2),
        const AppTableColumn('Time', flex: 2, hideWhenNarrow: true),
        const AppTableColumn('Class', flex: 3),
        const AppTableColumn('Coach', flex: 2, hideWhenNarrow: true),
        const AppTableColumn('Status', flex: 2),
        if (onCancel != null) const AppTableColumn('', flex: 2),
      ],
      rows: rows,
      emptyText: emptyText,
      cells: (b) => [
        _CellText(formatShortDate(b.start)),
        _CellText('${_hm(b.start)} – ${_hm(b.end)}'),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: classTypeColor(b.type),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: appSpaceSm),
            Expanded(
              child: Text(
                b.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: appText,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        _CellText(b.trainerName.isEmpty ? '—' : b.trainerName),
        Align(
          alignment: Alignment.centerLeft,
          child: bookingStatusPill(b, now),
        ),
        if (onCancel != null)
          Align(
            alignment: Alignment.centerRight,
            child: b.start.isAfter(now) && !b.isCancelled
                ? TextButton(
                    onPressed: () => onCancel!(b),
                    child: Text(b.status == 'waitlist' ? 'Leave' : 'Cancel'),
                  )
                : const SizedBox.shrink(),
          ),
      ],
    );
  }

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// Registered / Waiting list / Attended / No-show / Cancelled, as in the
/// reference's member Classes tab (docs/admin-ui-reference.md §4.2).
Widget bookingStatusPill(MemberBooking b, DateTime now) {
  final (label, intent) = switch (b.status) {
    'attended' => ('Attended', AppPillIntent.success),
    'no_show' => ('No-show', AppPillIntent.danger),
    'waitlist' => ('Waiting list', AppPillIntent.warning),
    'cancelled' => ('Cancelled', AppPillIntent.neutral),
    _ when b.end.isAfter(now) => ('Registered', AppPillIntent.primary),
    _ => ('Not checked in', AppPillIntent.neutral),
  };
  return AppPill(label: label, intent: intent, dense: true);
}

class _CellText extends StatelessWidget {
  const _CellText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(color: appMutedText, fontSize: 13),
  );
}
