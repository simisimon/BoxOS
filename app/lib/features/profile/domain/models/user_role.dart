enum UserRole { athlete, trainer, admin }

extension UserRoleX on UserRole {
  String get apiValue {
    switch (this) {
      case UserRole.athlete:
        return 'athlete';
      case UserRole.trainer:
        return 'trainer';
      case UserRole.admin:
        return 'admin';
    }
  }

  String get label {
    switch (this) {
      case UserRole.athlete:
        return 'Athlete';
      case UserRole.trainer:
        return 'Trainer';
      case UserRole.admin:
        return 'Admin';
    }
  }
}

UserRole userRoleFromApi(String value) {
  switch (value.trim().toLowerCase()) {
    case 'trainer':
      return UserRole.trainer;
    case 'box':
    case 'admin':
      return UserRole.admin;
    case 'athlete':
    default:
      return UserRole.athlete;
  }
}
