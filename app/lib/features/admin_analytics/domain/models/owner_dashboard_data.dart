/// `GET /admin/dashboard`: headline member counts and six calendar months of
/// activity, oldest first.
class OwnerDashboardData {
  const OwnerDashboardData({
    required this.membersAtRisk,
    required this.atRiskDays,
    required this.expiringMemberships,
    required this.expiringDays,
    required this.months,
  });

  factory OwnerDashboardData.fromJson(Map<String, dynamic> json) =>
      OwnerDashboardData(
        membersAtRisk: (json['members_at_risk'] as num? ?? 0).toInt(),
        atRiskDays: (json['at_risk_days'] as num? ?? 21).toInt(),
        expiringMemberships: (json['expiring_memberships'] as num? ?? 0)
            .toInt(),
        expiringDays: (json['expiring_days'] as num? ?? 14).toInt(),
        months: [
          for (final row in json['months'] as List? ?? const [])
            DashboardMonth.fromJson(row as Map<String, dynamic>),
        ],
      );

  final int membersAtRisk;
  final int atRiskDays;
  final int expiringMemberships;
  final int expiringDays;
  final List<DashboardMonth> months;
}

class DashboardMonth {
  const DashboardMonth({
    required this.month,
    required this.newMembers,
    required this.newMemberships,
    required this.churnedMembers,
    required this.registrations,
    required this.attended,
    required this.utilizationPercent,
  });

  factory DashboardMonth.fromJson(Map<String, dynamic> json) {
    int count(String key) => (json[key] as num? ?? 0).toInt();
    final parts = (json['month'] as String? ?? '2000-01').split('-');
    return DashboardMonth(
      month: DateTime(int.parse(parts[0]), int.parse(parts[1])),
      newMembers: count('new_members'),
      newMemberships: count('new_memberships'),
      churnedMembers: count('churned_members'),
      registrations: count('registrations'),
      attended: count('attended'),
      utilizationPercent: (json['utilization_percent'] as num? ?? 0).toDouble(),
    );
  }

  /// First day of the month.
  final DateTime month;
  final int newMembers;
  final int newMemberships;
  final int churnedMembers;
  final int registrations;
  final int attended;

  /// Booked seats over offered seats, 0–100.
  final double utilizationPercent;
}
