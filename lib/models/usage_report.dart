import '../utils/text_sanitizer.dart';

class UsageReport {
  const UsageReport({
    required this.activeUsers,
    required this.totalLogins,
    required this.totalModuleOpens,
    required this.totalMinutes,
    required this.loginsByUser,
    required this.modulesByOpenCount,
    required this.minutesByModule,
    required this.loginsByHour,
    required this.loginsByWeekday,
    required this.loginsByProfile,
  });

  final int activeUsers;
  final int totalLogins;
  final int totalModuleOpens;
  final double totalMinutes;
  final List<UsageBucket> loginsByUser;
  final List<UsageBucket> modulesByOpenCount;
  final List<UsageBucket> minutesByModule;
  final List<UsageBucket> loginsByHour;
  final List<UsageBucket> loginsByWeekday;
  final List<UsageBucket> loginsByProfile;

  factory UsageReport.empty() {
    return const UsageReport(
      activeUsers: 0,
      totalLogins: 0,
      totalModuleOpens: 0,
      totalMinutes: 0,
      loginsByUser: <UsageBucket>[],
      modulesByOpenCount: <UsageBucket>[],
      minutesByModule: <UsageBucket>[],
      loginsByHour: <UsageBucket>[],
      loginsByWeekday: <UsageBucket>[],
      loginsByProfile: <UsageBucket>[],
    );
  }

  factory UsageReport.fromJson(Map<String, dynamic> json) {
    List<UsageBucket> parseList(Object? value) {
      if (value is! List) {
        return const <UsageBucket>[];
      }

      return value
          .whereType<Map>()
          .map(
            (item) => UsageBucket.fromJson(
              item.map(
                (key, value) => MapEntry('$key', value),
              ),
            ),
          )
          .toList();
    }

    return UsageReport(
      activeUsers: (json['active_users'] as num?)?.toInt() ?? 0,
      totalLogins: (json['total_logins'] as num?)?.toInt() ?? 0,
      totalModuleOpens: (json['total_module_opens'] as num?)?.toInt() ?? 0,
      totalMinutes: (json['total_minutes'] as num?)?.toDouble() ?? 0,
      loginsByUser: parseList(json['logins_by_user']),
      modulesByOpenCount: parseList(json['modules_by_open_count']),
      minutesByModule: parseList(json['minutes_by_module']),
      loginsByHour: parseList(json['logins_by_hour']),
      loginsByWeekday: parseList(json['logins_by_weekday']),
      loginsByProfile: parseList(json['logins_by_profile']),
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
