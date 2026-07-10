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
    required this.loginsByHourUsers,
    required this.loginsByWeekdayByProfile,
    required this.loginsByWeekdayUsers,
    required this.moduleOpensByModule,
    required this.moduleUsersByModule,
    required this.moduleUsersByUser,
  });

  final int activeUsers;
  final int totalLogins;
  final List<UsageBucket> activeUsersDetails;
  final List<UsageBucket> loginsByUser;
  final List<UsageBucket> loginsByProfile;
  final List<UsageGroup> loginsByUserByProfile;
  final List<UsageGroup> loginsByHourByProfile;
  final List<UsageGroup> loginsByHourUsers;
  final List<UsageGroup> loginsByWeekdayByProfile;
  final List<UsageGroup> loginsByWeekdayUsers;
  final List<UsageBucket> moduleOpensByModule;
  final List<UsageGroup> moduleUsersByModule;
  final List<UsageGroup> moduleUsersByUser;

  factory UsageReport.empty() {
    return const UsageReport(
      activeUsers: 0,
      totalLogins: 0,
      activeUsersDetails: <UsageBucket>[],
      loginsByUser: <UsageBucket>[],
      loginsByProfile: <UsageBucket>[],
      loginsByUserByProfile: <UsageGroup>[],
      loginsByHourByProfile: <UsageGroup>[],
      loginsByHourUsers: <UsageGroup>[],
      loginsByWeekdayByProfile: <UsageGroup>[],
      loginsByWeekdayUsers: <UsageGroup>[],
      moduleOpensByModule: <UsageBucket>[],
      moduleUsersByModule: <UsageGroup>[],
      moduleUsersByUser: <UsageGroup>[],
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
      loginsByHourUsers: parseGroups(json['logins_by_hour_users']),
      loginsByWeekdayByProfile: parseGroups(
        json['logins_by_weekday_by_profile'],
      ),
      loginsByWeekdayUsers: parseGroups(json['logins_by_weekday_users']),
      moduleOpensByModule: parseBuckets(json['module_opens_by_module']),
      moduleUsersByModule: parseGroups(json['module_users_by_module']),
      moduleUsersByUser: parseGroups(json['module_users_by_user']),
    );
  }
}

class UsageGroup {
  const UsageGroup({required this.label, required this.items, this.value});

  final String label;
  final List<UsageBucket> items;
  final double? value;

  factory UsageGroup.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'];
    return UsageGroup(
      label: TextSanitizer.normalize(json['label'] as String? ?? ''),
      value: (json['value'] as num?)?.toDouble(),
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
    this.metadata = const <String, dynamic>{},
  });

  final String label;
  final double value;
  final double? secondaryValue;
  final Map<String, dynamic> metadata;

  factory UsageBucket.fromJson(Map<String, dynamic> json) {
    return UsageBucket(
      label: TextSanitizer.normalize(json['label'] as String? ?? ''),
      value: (json['value'] as num?)?.toDouble() ?? 0,
      secondaryValue: (json['secondary_value'] as num?)?.toDouble(),
      metadata: json['metadata'] is Map
          ? (json['metadata'] as Map).map(
              (key, value) => MapEntry('$key', value),
            )
          : const <String, dynamic>{},
    );
  }
}
