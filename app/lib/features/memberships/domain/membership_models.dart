/// Membership plans a box offers, and the plans its members are on.
///
/// Mirrors `backend/plan_service.py`: three plan types, prices in cents, and
/// member plans that copy price and limits at the time they were given.
library;

enum PlanType {
  unlimited,
  weekly,
  punchCard;

  String get apiValue => switch (this) {
    PlanType.unlimited => 'unlimited',
    PlanType.weekly => 'weekly',
    PlanType.punchCard => 'punch_card',
  };

  String get label => switch (this) {
    PlanType.unlimited => 'Unlimited',
    PlanType.weekly => 'Classes per week',
    PlanType.punchCard => 'Punch card',
  };

  static PlanType fromApi(String? value) => switch (value) {
    'weekly' => PlanType.weekly,
    'punch_card' => PlanType.punchCard,
    _ => PlanType.unlimited,
  };
}

enum BillingPeriod {
  monthly,
  yearly,
  oneTime;

  String get apiValue => switch (this) {
    BillingPeriod.monthly => 'monthly',
    BillingPeriod.yearly => 'yearly',
    BillingPeriod.oneTime => 'one_time',
  };

  String get label => switch (this) {
    BillingPeriod.monthly => 'Monthly',
    BillingPeriod.yearly => 'Yearly',
    BillingPeriod.oneTime => 'One-off',
  };

  /// Suffix after the price, e.g. "€129 / month".
  String get priceSuffix => switch (this) {
    BillingPeriod.monthly => ' / month',
    BillingPeriod.yearly => ' / year',
    BillingPeriod.oneTime => '',
  };

  static BillingPeriod fromApi(String? value) => switch (value) {
    'yearly' => BillingPeriod.yearly,
    'one_time' => BillingPeriod.oneTime,
    _ => BillingPeriod.monthly,
  };
}

enum PaymentStatus {
  paid,
  due,
  overdue;

  String get apiValue => name;

  String get label => switch (this) {
    PaymentStatus.paid => 'Paid',
    PaymentStatus.due => 'Due',
    PaymentStatus.overdue => 'Overdue',
  };

  static PaymentStatus fromApi(String? value) => switch (value) {
    'paid' => PaymentStatus.paid,
    'overdue' => PaymentStatus.overdue,
    _ => PaymentStatus.due,
  };
}

/// Class types a plan can be limited to (same set as the schedule).
const planClassTypes = <String>['WOD', 'Open Gym', 'Skill', 'PT'];

String formatPrice(int cents, String currency) {
  final symbol = switch (currency) {
    'EUR' => '€',
    'USD' => r'$',
    'GBP' => '£',
    _ => '$currency ',
  };
  final whole = cents ~/ 100;
  final rest = cents % 100;
  final amount = rest == 0
      ? '$whole'
      : '$whole.${rest.toString().padLeft(2, '0')}';
  return '$symbol$amount';
}

/// "2 classes / week", "10 classes · 90 days", "Unlimited classes".
String planLimitLabel({
  required PlanType type,
  int? classesPerWeek,
  int? classCount,
  int? validityDays,
}) {
  switch (type) {
    case PlanType.unlimited:
      return 'Unlimited classes';
    case PlanType.weekly:
      final count = classesPerWeek ?? 0;
      return '$count ${count == 1 ? 'class' : 'classes'} / week';
    case PlanType.punchCard:
      final count = classCount ?? 0;
      final classes = '$count ${count == 1 ? 'class' : 'classes'}';
      return validityDays == null ? classes : '$classes · $validityDays days';
  }
}

String classTypesLabel(List<String> types) =>
    types.isEmpty ? 'All class types' : types.join(', ');

class MembershipPlan {
  const MembershipPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.priceCents,
    required this.currency,
    required this.billingPeriod,
    this.classesPerWeek,
    this.classCount,
    this.validityDays,
    this.allowedClassTypes = const [],
    this.isArchived = false,
    this.activeMemberCount = 0,
  });

  final int id;
  final String name;
  final String description;
  final PlanType type;
  final int priceCents;
  final String currency;
  final BillingPeriod billingPeriod;
  final int? classesPerWeek;
  final int? classCount;
  final int? validityDays;

  /// Empty = every class type.
  final List<String> allowedClassTypes;
  final bool isArchived;
  final int activeMemberCount;

  String get priceLabel =>
      '${formatPrice(priceCents, currency)}${billingPeriod.priceSuffix}';

  String get limitLabel => planLimitLabel(
    type: type,
    classesPerWeek: classesPerWeek,
    classCount: classCount,
    validityDays: validityDays,
  );

  factory MembershipPlan.fromJson(Map<String, dynamic> data) {
    return MembershipPlan(
      id: data['id'] as int? ?? 0,
      name: data['name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      type: PlanType.fromApi(data['plan_type'] as String?),
      priceCents: (data['price_cents'] as num?)?.toInt() ?? 0,
      currency: data['currency'] as String? ?? 'EUR',
      billingPeriod: BillingPeriod.fromApi(data['billing_period'] as String?),
      classesPerWeek: (data['classes_per_week'] as num?)?.toInt(),
      classCount: (data['class_count'] as num?)?.toInt(),
      validityDays: (data['validity_days'] as num?)?.toInt(),
      allowedClassTypes: [
        for (final item in data['allowed_class_types'] as List<dynamic>? ?? [])
          item.toString(),
      ],
      isArchived: data['is_archived'] as bool? ?? false,
      activeMemberCount: (data['active_member_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// What the owner types into the plan editor.
class MembershipPlanDraft {
  const MembershipPlanDraft({
    required this.name,
    required this.description,
    required this.type,
    required this.priceCents,
    required this.billingPeriod,
    this.classesPerWeek,
    this.classCount,
    this.validityDays,
    this.allowedClassTypes = const [],
  });

  final String name;
  final String description;
  final PlanType type;
  final int priceCents;
  final BillingPeriod billingPeriod;
  final int? classesPerWeek;
  final int? classCount;
  final int? validityDays;
  final List<String> allowedClassTypes;

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'plan_type': type.apiValue,
    'price_cents': priceCents,
    'billing_period': billingPeriod.apiValue,
    'classes_per_week': type == PlanType.weekly ? classesPerWeek : null,
    'class_count': type == PlanType.punchCard ? classCount : null,
    'validity_days': type == PlanType.punchCard ? validityDays : null,
    'allowed_class_types': allowedClassTypes,
  };
}

/// requested | upcoming | current | expired | ended | rejected | cancelled
enum MemberPlanState {
  requested,
  upcoming,
  current,
  expired,
  ended,
  rejected,
  cancelled;

  String get label => switch (this) {
    MemberPlanState.requested => 'Requested',
    MemberPlanState.upcoming => 'Upcoming',
    MemberPlanState.current => 'Current',
    MemberPlanState.expired => 'Expired',
    MemberPlanState.ended => 'Ended',
    MemberPlanState.rejected => 'Declined',
    MemberPlanState.cancelled => 'Withdrawn',
  };

  static MemberPlanState fromApi(String? value) {
    for (final state in MemberPlanState.values) {
      if (state.name == value) return state;
    }
    return MemberPlanState.ended;
  }
}

class MemberPlan {
  const MemberPlan({
    required this.id,
    required this.userId,
    required this.planId,
    required this.state,
    required this.planName,
    required this.type,
    required this.priceCents,
    required this.currency,
    required this.billingPeriod,
    required this.paymentStatus,
    this.classesPerWeek,
    this.classCount,
    this.validityDays,
    this.allowedClassTypes = const [],
    this.startsOn,
    this.endsOn,
    this.requestedAt,
    this.classesUsed,
    this.classesRemaining,
    this.classesThisWeek,
    this.memberName,
    this.memberEmail,
    this.currentPlanName,
  });

  final int id;
  final int userId;
  final int? planId;
  final MemberPlanState state;
  final String planName;
  final PlanType type;
  final int priceCents;
  final String currency;
  final BillingPeriod billingPeriod;
  final PaymentStatus paymentStatus;
  final int? classesPerWeek;
  final int? classCount;
  final int? validityDays;
  final List<String> allowedClassTypes;

  /// Gym-local dates (YYYY-MM-DD).
  final String? startsOn;
  final String? endsOn;
  final DateTime? requestedAt;
  final int? classesUsed;
  final int? classesRemaining;
  final int? classesThisWeek;

  /// Only set on plan requests listed for the owner.
  final String? memberName;
  final String? memberEmail;
  final String? currentPlanName;

  bool get isActive =>
      state == MemberPlanState.current || state == MemberPlanState.upcoming;

  String get priceLabel =>
      '${formatPrice(priceCents, currency)}${billingPeriod.priceSuffix}';

  String get limitLabel => planLimitLabel(
    type: type,
    classesPerWeek: classesPerWeek,
    classCount: classCount,
    validityDays: validityDays,
  );

  /// "Since 2026-11-01", "2026-11-01 – 2027-01-29", "From 2026-12-01".
  String? get periodLabel {
    if (startsOn == null) return null;
    if (state == MemberPlanState.upcoming) return 'From $startsOn';
    if (endsOn == null) return 'Since $startsOn';
    return '$startsOn – $endsOn';
  }

  /// "1 of 2 this week", "7 of 10 left".
  String? get usageLabel {
    if (type == PlanType.weekly && classesThisWeek != null) {
      return '$classesThisWeek of ${classesPerWeek ?? 0} booked this week';
    }
    if (type == PlanType.punchCard && classesRemaining != null) {
      return '$classesRemaining of ${classCount ?? 0} classes left';
    }
    return null;
  }

  factory MemberPlan.fromJson(Map<String, dynamic> data) {
    final member = data['member'] as Map<String, dynamic>?;
    final memberDisplayName = member?['display_name'] as String? ?? '';
    final requestedAtRaw = data['requested_at'] as String?;
    return MemberPlan(
      id: data['id'] as int? ?? 0,
      userId: data['user_id'] as int? ?? 0,
      planId: data['plan_id'] as int?,
      state: MemberPlanState.fromApi(data['state'] as String?),
      planName: data['plan_name'] as String? ?? '',
      type: PlanType.fromApi(data['plan_type'] as String?),
      priceCents: (data['price_cents'] as num?)?.toInt() ?? 0,
      currency: data['currency'] as String? ?? 'EUR',
      billingPeriod: BillingPeriod.fromApi(data['billing_period'] as String?),
      paymentStatus: PaymentStatus.fromApi(data['payment_status'] as String?),
      classesPerWeek: (data['classes_per_week'] as num?)?.toInt(),
      classCount: (data['class_count'] as num?)?.toInt(),
      validityDays: (data['validity_days'] as num?)?.toInt(),
      allowedClassTypes: [
        for (final item in data['allowed_class_types'] as List<dynamic>? ?? [])
          item.toString(),
      ],
      startsOn: data['starts_on'] as String?,
      endsOn: data['ends_on'] as String?,
      requestedAt: requestedAtRaw == null
          ? null
          : DateTime.tryParse(requestedAtRaw),
      classesUsed: (data['classes_used'] as num?)?.toInt(),
      classesRemaining: (data['classes_remaining'] as num?)?.toInt(),
      classesThisWeek: (data['classes_this_week'] as num?)?.toInt(),
      memberName: member == null
          ? null
          : (memberDisplayName.isEmpty
                ? member['email'] as String? ?? ''
                : memberDisplayName),
      memberEmail: member?['email'] as String?,
      currentPlanName: data['current_plan_name'] as String?,
    );
  }
}

/// The plan shown on the Members tab next to each member.
class MemberPlanSummary {
  const MemberPlanSummary({
    required this.id,
    required this.planName,
    required this.type,
    required this.paymentStatus,
    required this.isUpcoming,
    this.startsOn,
    this.endsOn,
  });

  final int id;
  final String planName;
  final PlanType type;
  final PaymentStatus paymentStatus;
  final bool isUpcoming;
  final String? startsOn;
  final String? endsOn;

  static MemberPlanSummary? fromJson(Map<String, dynamic>? data) {
    if (data == null) return null;
    return MemberPlanSummary(
      id: data['id'] as int? ?? 0,
      planName: data['plan_name'] as String? ?? '',
      type: PlanType.fromApi(data['plan_type'] as String?),
      paymentStatus: PaymentStatus.fromApi(data['payment_status'] as String?),
      isUpcoming: data['state'] == 'upcoming',
      startsOn: data['starts_on'] as String?,
      endsOn: data['ends_on'] as String?,
    );
  }
}

class MembershipSettings {
  const MembershipSettings({
    required this.currency,
    required this.requirePlanForBooking,
    this.currencies = const ['EUR', 'USD', 'GBP', 'CHF'],
  });

  final String currency;
  final bool requirePlanForBooking;
  final List<String> currencies;

  factory MembershipSettings.fromJson(Map<String, dynamic>? data) {
    return MembershipSettings(
      currency: data?['currency'] as String? ?? 'EUR',
      requirePlanForBooking:
          data?['require_plan_for_booking'] as bool? ?? false,
      currencies: [
        for (final item
            in data?['currencies'] as List<dynamic>? ??
                const ['EUR', 'USD', 'GBP', 'CHF'])
          item.toString(),
      ],
    );
  }
}

/// The signed-in member's plans at the active box.
class MyMembership {
  const MyMembership({
    required this.plans,
    required this.requirePlanForBooking,
  });

  final List<MemberPlan> plans;
  final bool requirePlanForBooking;

  MemberPlan? get current => _first(MemberPlanState.current);
  MemberPlan? get upcoming => _first(MemberPlanState.upcoming);
  MemberPlan? get request => _first(MemberPlanState.requested);

  MemberPlan? _first(MemberPlanState state) {
    for (final plan in plans) {
      if (plan.state == state) return plan;
    }
    return null;
  }
}
