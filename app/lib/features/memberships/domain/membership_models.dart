/// Membership plans a box offers, and the plans its members are on.
///
/// Mirrors `backend/plan_service.py`: plans are token-based (one booking
/// spends one token), prices are in cents, and member plans copy price and
/// tokens at the time they were given.
library;

enum PlanType {
  /// Unlimited tokens.
  unlimited,

  /// N tokens every week / month / year, counted from the plan's start date.
  tokens,

  /// N tokens once, optionally valid for some days.
  tokenPack;

  String get apiValue => switch (this) {
    PlanType.unlimited => 'unlimited',
    PlanType.tokens => 'tokens',
    PlanType.tokenPack => 'token_pack',
  };

  String get label => switch (this) {
    PlanType.unlimited => 'Unlimited',
    PlanType.tokens => 'Tokens per period',
    PlanType.tokenPack => 'Token pack',
  };

  static PlanType fromApi(String? value) => switch (value) {
    'tokens' => PlanType.tokens,
    'token_pack' => PlanType.tokenPack,
    _ => PlanType.unlimited,
  };
}

enum TokenPeriod {
  week,
  month,
  year;

  String get apiValue => name;

  String get label => switch (this) {
    TokenPeriod.week => 'Week',
    TokenPeriod.month => 'Month',
    TokenPeriod.year => 'Year',
  };

  static TokenPeriod fromApi(String? value) => switch (value) {
    'week' => TokenPeriod.week,
    'year' => TokenPeriod.year,
    _ => TokenPeriod.month,
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

String tokensLabel(int count) => '$count ${count == 1 ? 'token' : 'tokens'}';

/// "12 tokens / month", "10 tokens · valid 90 days", "Unlimited tokens".
String planLimitLabel({
  required PlanType type,
  int? tokenCount,
  TokenPeriod? tokenPeriod,
  int? validityDays,
}) {
  switch (type) {
    case PlanType.unlimited:
      return 'Unlimited tokens';
    case PlanType.tokens:
      final period = (tokenPeriod ?? TokenPeriod.month).label.toLowerCase();
      return '${tokensLabel(tokenCount ?? 0)} / $period';
    case PlanType.tokenPack:
      final tokens = tokensLabel(tokenCount ?? 0);
      return validityDays == null
          ? tokens
          : '$tokens · valid $validityDays days';
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
    this.tokenCount,
    this.tokenPeriod,
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
  final int? tokenCount;

  /// Only for [PlanType.tokens].
  final TokenPeriod? tokenPeriod;
  final int? validityDays;

  /// Empty = every class type.
  final List<String> allowedClassTypes;
  final bool isArchived;
  final int activeMemberCount;

  String get priceLabel =>
      '${formatPrice(priceCents, currency)}${billingPeriod.priceSuffix}';

  String get limitLabel => planLimitLabel(
    type: type,
    tokenCount: tokenCount,
    tokenPeriod: tokenPeriod,
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
      tokenCount: (data['token_count'] as num?)?.toInt(),
      tokenPeriod: data['token_period'] == null
          ? null
          : TokenPeriod.fromApi(data['token_period'] as String?),
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
    this.tokenCount,
    this.tokenPeriod,
    this.validityDays,
    this.allowedClassTypes = const [],
  });

  final String name;
  final String description;
  final PlanType type;
  final int priceCents;
  final BillingPeriod billingPeriod;
  final int? tokenCount;

  /// Only for [PlanType.tokens].
  final TokenPeriod? tokenPeriod;
  final int? validityDays;
  final List<String> allowedClassTypes;

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'plan_type': type.apiValue,
    'price_cents': priceCents,
    'billing_period': billingPeriod.apiValue,
    'token_count': type == PlanType.unlimited ? null : tokenCount,
    'token_period': type == PlanType.tokens ? tokenPeriod?.apiValue : null,
    'validity_days': type == PlanType.tokenPack ? validityDays : null,
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
    this.tokenCount,
    this.tokenPeriod,
    this.validityDays,
    this.allowedClassTypes = const [],
    this.startsOn,
    this.endsOn,
    this.requestedAt,
    this.tokensTotal,
    this.tokensUsed,
    this.tokensRemaining,
    this.periodStartsOn,
    this.periodEndsOn,
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
  final int? tokenCount;

  /// Only for [PlanType.tokens].
  final TokenPeriod? tokenPeriod;
  final int? validityDays;
  final List<String> allowedClassTypes;

  /// Gym-local dates (YYYY-MM-DD).
  final String? startsOn;
  final String? endsOn;
  final DateTime? requestedAt;

  /// Token balance of the current period (the whole pack for token packs);
  /// null for unlimited plans.
  final int? tokensTotal;
  final int? tokensUsed;
  final int? tokensRemaining;

  /// Gym-local dates of the current token period (inclusive).
  final String? periodStartsOn;
  final String? periodEndsOn;

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
    tokenCount: tokenCount,
    tokenPeriod: tokenPeriod,
    validityDays: validityDays,
  );

  /// "Since 2026-11-01", "2026-11-01 – 2027-01-29", "From 2026-12-01".
  String? get periodLabel {
    if (startsOn == null) return null;
    if (state == MemberPlanState.upcoming) return 'From $startsOn';
    if (endsOn == null) return 'Since $startsOn';
    return '$startsOn – $endsOn';
  }

  /// "7 of 12 tokens left until 2026-12-08", "3 of 10 tokens left".
  String? get usageLabel {
    final remaining = tokensRemaining;
    if (remaining == null) return null;
    final left = '$remaining of ${tokensLabel(tokensTotal ?? 0)} left';
    if (type == PlanType.tokens && periodEndsOn != null) {
      return '$left until $periodEndsOn';
    }
    return left;
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
      tokenCount: (data['token_count'] as num?)?.toInt(),
      tokenPeriod: data['token_period'] == null
          ? null
          : TokenPeriod.fromApi(data['token_period'] as String?),
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
      tokensTotal: (data['tokens_total'] as num?)?.toInt(),
      tokensUsed: (data['tokens_used'] as num?)?.toInt(),
      tokensRemaining: (data['tokens_remaining'] as num?)?.toInt(),
      periodStartsOn: data['period_starts_on'] as String?,
      periodEndsOn: data['period_ends_on'] as String?,
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
    this.extraTokenPriceCents,
  });

  final String currency;
  final bool requirePlanForBooking;
  final List<String> currencies;

  /// Price of one extra token; null = the box does not sell extra tokens.
  final int? extraTokenPriceCents;

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
      extraTokenPriceCents: (data?['extra_token_price_cents'] as num?)
          ?.toInt(),
    );
  }
}

/// One grant of extra tokens (bought or given by the owner). Valid for one
/// month; spent when the member's plan cannot cover a class.
class ExtraTokenCredit {
  const ExtraTokenCredit({
    required this.id,
    required this.tokens,
    required this.tokensUsed,
    required this.tokensRemaining,
    required this.priceCents,
    required this.currency,
    required this.grantedOn,
    required this.validUntil,
  });

  final int id;
  final int tokens;
  final int tokensUsed;
  final int tokensRemaining;

  /// Total paid for [tokens].
  final int priceCents;
  final String currency;

  /// Gym-local dates (YYYY-MM-DD); [validUntil] is the last usable day.
  final String grantedOn;
  final String validUntil;

  factory ExtraTokenCredit.fromJson(Map<String, dynamic> data) {
    return ExtraTokenCredit(
      id: data['id'] as int? ?? 0,
      tokens: (data['tokens'] as num?)?.toInt() ?? 0,
      tokensUsed: (data['tokens_used'] as num?)?.toInt() ?? 0,
      tokensRemaining: (data['tokens_remaining'] as num?)?.toInt() ?? 0,
      priceCents: (data['price_cents'] as num?)?.toInt() ?? 0,
      currency: data['currency'] as String? ?? 'EUR',
      grantedOn: data['granted_on'] as String? ?? '',
      validUntil: data['valid_until'] as String? ?? '',
    );
  }
}

/// A member's unexpired extra tokens.
class ExtraTokens {
  const ExtraTokens({this.tokensRemaining = 0, this.credits = const []});

  final int tokensRemaining;
  final List<ExtraTokenCredit> credits;

  /// "3 extra tokens left · first expire 2026-12-08"; null when none are left.
  String? get summaryLabel {
    String? firstExpiry;
    for (final credit in credits) {
      if (credit.tokensRemaining > 0) {
        firstExpiry = credit.validUntil;
        break;
      }
    }
    if (tokensRemaining == 0 || firstExpiry == null) return null;
    final count = tokensRemaining == 1
        ? '1 extra token'
        : '$tokensRemaining extra tokens';
    final expiry = tokensRemaining == 1 ? 'valid until' : 'first expire';
    return '$count left · $expiry $firstExpiry';
  }

  static ExtraTokens fromJson(Map<String, dynamic>? data) {
    if (data == null) return const ExtraTokens();
    return ExtraTokens(
      tokensRemaining: (data['tokens_remaining'] as num?)?.toInt() ?? 0,
      credits: [
        for (final item in data['credits'] as List<dynamic>? ?? const [])
          ExtraTokenCredit.fromJson(item as Map<String, dynamic>),
      ],
    );
  }
}

/// A member's plans and extra tokens, for the owner's member detail.
class MemberMembership {
  const MemberMembership({
    required this.plans,
    required this.extraTokens,
    this.extraTokenPriceCents,
    this.currency = 'EUR',
  });

  final List<MemberPlan> plans;
  final ExtraTokens extraTokens;
  final int? extraTokenPriceCents;
  final String currency;
}

/// The signed-in member's plans at the active box.
class MyMembership {
  const MyMembership({
    required this.plans,
    required this.requirePlanForBooking,
    this.extraTokens = const ExtraTokens(),
  });

  final List<MemberPlan> plans;
  final bool requirePlanForBooking;
  final ExtraTokens extraTokens;

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
