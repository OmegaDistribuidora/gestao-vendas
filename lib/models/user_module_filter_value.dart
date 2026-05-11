import 'bi_module_filter.dart';

class UserModuleFilterValue {
  const UserModuleFilterValue({
    required this.id,
    required this.accessId,
    required this.moduleFilterId,
    required this.filterValue,
    this.moduleFilter,
  });

  final String id;
  final String accessId;
  final String moduleFilterId;
  final String filterValue;
  final BiModuleFilter? moduleFilter;

  factory UserModuleFilterValue.fromJson(Map<String, dynamic> json) {
    final moduleFilterJson = json['module_filter'];
    return UserModuleFilterValue(
      id: json['id'] as String,
      accessId: json['access_id'] as String,
      moduleFilterId: json['module_filter_id'] as String,
      filterValue: json['filter_value'] as String? ?? '',
      moduleFilter: moduleFilterJson is Map<String, dynamic>
          ? BiModuleFilter.fromJson(moduleFilterJson)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'access_id': accessId,
      'module_filter_id': moduleFilterId,
      'filter_value': filterValue,
      'module_filter': moduleFilter?.toJson(),
    };
  }
}
