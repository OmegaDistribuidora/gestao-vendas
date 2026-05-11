import 'user_module_filter_value.dart';

class UserModuleAccess {
  const UserModuleAccess({
    required this.id,
    required this.userId,
    required this.moduleId,
    required this.hasFilteredData,
    this.filterValues = const <UserModuleFilterValue>[],
  });

  final String id;
  final String userId;
  final String moduleId;
  final bool hasFilteredData;
  final List<UserModuleFilterValue> filterValues;

  String get filterValue =>
      filterValues.isEmpty ? '' : filterValues.first.filterValue;

  factory UserModuleAccess.fromJson(Map<String, dynamic> json) {
    final filterValuesJson = json['filter_values'];
    return UserModuleAccess(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      moduleId: json['module_id'] as String,
      hasFilteredData: json['has_filtered_data'] as bool? ?? false,
      filterValues: filterValuesJson is List
          ? filterValuesJson
                .whereType<Map>()
                .map(
                  (row) => UserModuleFilterValue.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <UserModuleFilterValue>[],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'user_id': userId,
      'module_id': moduleId,
      'has_filtered_data': hasFilteredData,
      'filter_values': filterValues.map((item) => item.toJson()).toList(),
    };
  }

  UserModuleAccess copyWith({
    String? id,
    String? userId,
    String? moduleId,
    bool? hasFilteredData,
    List<UserModuleFilterValue>? filterValues,
  }) {
    return UserModuleAccess(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      moduleId: moduleId ?? this.moduleId,
      hasFilteredData: hasFilteredData ?? this.hasFilteredData,
      filterValues: filterValues ?? this.filterValues,
    );
  }
}
