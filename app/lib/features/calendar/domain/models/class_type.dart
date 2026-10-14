/// The kinds of bookable classes a box runs. Mirrors the backend's allowed
/// `class_type` values. Only [wod] sessions carry the day's programmed WOD.
enum ClassType {
  wod('WOD', 'CrossFit'),
  openGym('Open Gym', 'Open Gym'),
  skill('Skill', 'Skill'),
  pt('PT', 'Personal Training');

  const ClassType(this.wireValue, this.defaultTitle);

  /// Value sent to and received from the API; also the label shown in badges.
  final String wireValue;

  /// Title a new class of this type starts with.
  final String defaultTitle;

  String get label => wireValue;

  bool get showsWod => this == ClassType.wod;

  /// Unknown legacy values fall back to [wod] so old rows still render.
  static ClassType fromWire(String value) {
    for (final type in ClassType.values) {
      if (type.wireValue == value) {
        return type;
      }
    }
    return ClassType.wod;
  }
}
