import '../utils/text_sanitizer.dart';

class UsageReport {
  const UsageReport({
    required this.activeUsers,
    required this.totalLogins,
    required this.activeUsersDetails,
    required this.loginsByUser,
    required this.loginsByProfile,
    required this.loginsByUserByProfile,
    required this.loginsByHourByProfile,
    required this.loginsByWeekdayByProfile,
  });

  final int activeUsers;
  final int totalLogins;
  final List<UsageBucket> activeUsersDetails;
  final List<UsageBucket> loginsByUser;
  final List<UsageBucket> loginsByProfile;
  final List<UsageGroup> loginsByUserByProfile;
  final List<UsageGroup> loginsByHourByProfile;
  final List<UsageGroup> loginsByWeekdayByProfile;

  factory UsageReport.empty() {
    return const UsageReport(
      activeUsers: 0,
      totalLogins: 0,
      activeUsersDetails: <UsageBucket>[],
      loginsByUser: <UsageBucket>[],
      loginsByProfile: <UsageBucket>[],
      loginsByUserByProfile: <UsageGroup>[],
      loginsByHourByProfile: <UsageGroup>[],
      loginsByWeekdayByProfile: <UsageGroup>[],
    );
  }

  factory UsageReport.fromJson(Map<String, dynamic> json) {
    List<UsageBucket> parseBuckets(Object? value) {
      if (value is! List) {
        return const <UsageBucket>[];
      }

      return value
          .whereType<Map>()
          .map(
            (item) => UsageBucket.fromJson(
              item.map((key, value) => MapEntry('$key', value)),
            ),
          )
          .toList();
    }

    List<UsageGroup> parseGroups(Object? value) {
      if (value is! List) {
        return const <UsageGroup>[];
      }

      return value
          .whereType<Map>()
          .map(
            (item) => UsageGroup.fromJson(
              item.map((key, value) => MapEntry('$key', value)),
            ),
          )
          .toList();
    }

    return UsageReport(
      activeUsers: (json['active_users'] as num?)?.toInt() ?? 0,
      totalLogins: (json['total_logins'] as num?)?.toInt() ?? 0,
      activeUsersDetails: parseBuckets(json['active_users_details']),
      loginsByUser: parseBuckets(json['logins_by_user']),
      loginsByProfile: parseBuckets(json['logins_by_profile']),
      loginsByUserByProfile: parseGroups(json['logins_by_user_by_profile']),
      loginsByHourByProfile: parseGroups(json['logins_by_hour_by_profile']),
      loginsByWeekdayByProfile: parseGroups(
        json['logins_by_weekday_by_profile'],
      ),
    );
  }
}

class UsageGroup {
  const UsageGroup({required this.label, required this.items});

  final String label;
  final List<UsageBucket> items;

  factory UsageGroup.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'];
    return UsageGroup(
      label: TextSanitizer.normalize(json['label'] as String? ?? ''),
      items: itemsJson is List
          ? itemsJson
                .whereType<Map>()
                .map(
                  (item) => UsageBucket.fromJson(
                    item.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <UsageBucket>[],
    );
  }
}

class UsageBucket {
  const UsageBucket({
    required this.label,
    required this.value,
    this.secondaryValue,
  });

  final String label;
  final double value;
  final double? secondaryValue;

  factory UsageBucket.fromJson(Map<String, dynamic> json) {
    return UsageBucket(
      label: TextSanitizer.normalize(json['label'] as String? ?? ''),
      value: (json['value'] as num?)?.toDouble() ?? 0,
      secondaryValue: (json['secondary_value'] as num?)?.toDouble(),
    );
  }
}
