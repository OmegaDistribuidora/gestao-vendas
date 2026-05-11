import '../utils/text_sanitizer.dart';

class BiModuleFilter {
  const BiModuleFilter({
    required this.id,
    required this.moduleId,
    required this.filterTable,
    required this.filterColumn,
    this.label,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final String id;
  final String moduleId;
  final String filterTable;
  final String filterColumn;
  final String? label;
  final int sortOrder;
  final bool isActive;

  String get displayLabel =>
      (label != null && label!.trim().isNotEmpty)
      ? label!.trim()
      : '$filterTable / $filterColumn';

  factory BiModuleFilter.fromJson(Map<String, dynamic> json) {
    return BiModuleFilter(
      id: json['id'] as String,
      moduleId: json['module_id'] as String,
      filterTable: TextSanitizer.normalize(
        json['filter_table'] as String? ?? '',
      ),
      filterColumn: TextSanitizer.normalize(
        json['filter_column'] as String? ?? '',
      ),
      label: TextSanitizer.normalizeNullable(json['label'] as String?),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'module_id': moduleId,
      'filter_table': filterTable,
      'filter_column': filterColumn,
      'label': label,
      'sort_order': sortOrder,
      'is_active': isActive,
    };
  }
}
