import 'package:app/features/profile/domain/models/user_role.dart';

/// Lifecycle state of a gym membership.
///
/// `active` is the default and the only one that grants the full member
/// experience. `paused` keeps the membership listed in the roster but is the
/// hook for blocking bookings/entitlements later. `removed` is a soft delete:
/// the row stays for audit history but the roster filters it out.
enum MembershipStatus {
  active,
  paused,
  removed;

  String get apiValue {
    switch (this) {
      case MembershipStatus.active:
        return 'active';
      case MembershipStatus.paused:
        return 'paused';
      case MembershipStatus.removed:
        return 'removed';
    }
  }

  String get label {
    switch (this) {
      case MembershipStatus.active:
        return 'Active';
      case MembershipStatus.paused:
        return 'Paused';
      case MembershipStatus.removed:
        return 'Removed';
    }
  }

  static MembershipStatus fromApi(String? value) {
    switch (value) {
      case 'paused':
        return MembershipStatus.paused;
      case 'removed':
        return MembershipStatus.removed;
      case 'active':
      default:
        return MembershipStatus.active;
    }
  }
}

class RoleManagedUser {
  const RoleManagedUser({
    required this.id,
    required this.membershipId,
    required this.email,
    required this.role,
    required this.availableRoles,
    required this.displayName,
    required this.nickname,
    required this.canEditRole,
    this.profileImageUrl = '',
    this.status = MembershipStatus.active,
    this.adminNote = '',
    this.joinedAt,
    this.totalBookings = 0,
    this.attendedBookings = 0,
    this.noShowBookings = 0,
    this.bookingRate = 0,
    this.lastBookingAt,
    this.newestPrTitle = '',
    this.newestPrScore = '',
    this.newestPrAt,
  });

  final int id;
  final int membershipId;
  final String email;
  final UserRole role;
  final List<UserRole> availableRoles;
  final String displayName;
  final String nickname;
  final bool canEditRole;
  final String profileImageUrl;
  final MembershipStatus status;

  /// Admin-only note attached to the membership (injury notes, plan reminders).
  /// Empty string when none.
  final String adminNote;

  /// When this user joined the gym (membership creation timestamp). Null only
  /// when the backend didn't supply it (older clients).
  final DateTime? joinedAt;
  final int totalBookings;
  final int attendedBookings;
  final int noShowBookings;
  final double bookingRate;
  final DateTime? lastBookingAt;
  final String newestPrTitle;
  final String newestPrScore;
  final DateTime? newestPrAt;
}
