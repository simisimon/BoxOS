/// The kinds of bookable classes a box runs: four built-ins plus the custom
/// types an owner adds in Settings › Class types (backend `/class-types`).
/// Only [wod] sessions carry the day's programmed WOD.
class ClassType {
  const ClassType(
    this.wireValue,
    this.defaultTitle, {
    this.colorKey = 'info',
    this.defaultCapacity = 12,
    this.id,
  });

  factory ClassType.fromJson(Map<String, dynamic> json) => ClassType(
    json['name'] as String,
    json['name'] as String,
    colorKey: json['color'] as String? ?? 'info',
    defaultCapacity: json['default_capacity'] as int? ?? 12,
    id: json['id'] as int?,
  );

  static const wod = ClassType(
    'WOD',
    'CrossFit',
    colorKey: 'primary',
    defaultCapacity: 20,
  );
  static const openGym = ClassType(
    'Open Gym',
    'Open Gym',
    colorKey: 'muted',
    defaultCapacity: 24,
  );
  static const skill = ClassType(
    'Skill',
    'Skill',
    colorKey: 'warning',
    defaultCapacity: 14,
  );
  static const pt = ClassType(
    'PT',
    'Personal Training',
    colorKey: 'success',
    defaultCapacity: 2,
  );

  static const builtIns = [wod, openGym, skill, pt];

  // shortcut: one app-wide registry for the active gym, filled by
  // classTypesProvider; switch to passing types around if several gyms
  // are ever shown at once.
  static List<ClassType> _custom = const [];

  static void registerCustom(List<ClassType> types) => _custom = types;

  /// Built-ins first, then the gym's custom types.
  static List<ClassType> get values => [...builtIns, ..._custom];

  /// Value sent to and received from the API; also the label shown in badges.
  final String wireValue;

  /// Title a new class of this type starts with.
  final String defaultTitle;

  /// Colour token key: primary, info, success, warning, danger or muted.
  final String colorKey;

  final int defaultCapacity;

  /// Set for custom types only (the `/class-types` row id).
  final int? id;

  bool get isCustom => id != null;

  String get label => wireValue;

  bool get showsWod => this == ClassType.wod;

  /// A type that is not (yet) registered keeps its name instead of turning
  /// into a WOD; empty legacy values fall back to [wod].
  static ClassType fromWire(String value) {
    for (final type in values) {
      if (type.wireValue == value) {
        return type;
      }
    }
    return value.isEmpty ? wod : ClassType(value, value);
  }

  @override
  bool operator ==(Object other) =>
      other is ClassType && other.wireValue == wireValue;

  @override
  int get hashCode => wireValue.hashCode;
}
