enum AccountType { athlete, admin }

extension AccountTypeX on AccountType {
  String get apiValue {
    switch (this) {
      case AccountType.admin:
        return 'admin';
      case AccountType.athlete:
        return 'athlete';
    }
  }

  String get label {
    switch (this) {
      case AccountType.admin:
        return 'Admin';
      case AccountType.athlete:
        return 'Athlete';
    }
  }
}

AccountType accountTypeFromApi(String value) {
  switch (value.trim().toLowerCase()) {
    case 'owner':
    case 'admin':
      return AccountType.admin;
    case 'athlete':
    default:
      return AccountType.athlete;
  }
}
