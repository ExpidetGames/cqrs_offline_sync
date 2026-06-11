List<dynamic> asListOr(Object? value, {required List<dynamic> fallback}) {
  if (value == null) {
    return fallback;
  }
  if (value is List<dynamic>) {
    return value;
  }
  if (value is List) {
    return value.cast<dynamic>();
  }
  return fallback;
}

Map<String, dynamic> asMapOr(
  Object? value, {
  required Map<String, dynamic> fallback,
}) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return fallback;
}

String asStringOr(Object? value, {required String fallback}) {
  if (value == null) {
    return fallback;
  }
  if (value is String) {
    return value;
  }
  return value.toString();
}

int asIntOr(Object? value, {required int fallback}) {
  if (value == null) {
    return fallback;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  final parsed = int.tryParse(value.toString());
  return parsed ?? fallback;
}

bool asBoolOr(Object? value, {required bool fallback}) {
  if (value == null) {
    return fallback;
  }
  if (value is bool) {
    return value;
  }
  if (value is String) {
    if (value.toLowerCase() == 'true') {
      return true;
    }
    if (value.toLowerCase() == 'false') {
      return false;
    }
  }
  return fallback;
}

DateTime asDateTimeOr(Object? value, {required DateTime fallback}) {
  if (value == null) {
    return fallback;
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value) ?? fallback;
  }
  return fallback;
}
