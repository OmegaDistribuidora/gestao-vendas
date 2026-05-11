import 'bi_module_filter.dart';
import '../utils/text_sanitizer.dart';

class BiModule {
  const BiModule({
    required this.id,
    required this.name,
    required this.panelUrl,
    this.filters = const <BiModuleFilter>[],
    this.sellerDefaultFilterId,
    this.isSystem = false,
    this.isActive = true,
    this.type = 'acompanhamento_bi',
  });

  final String id;
  final String name;
  final String panelUrl;
  final List<BiModuleFilter> filters;
  final String? sellerDefaultFilterId;
  final bool isSystem;
  final bool isActive;
  final String type;

  String get filterTable =>
      filters.isEmpty ? '' : filters.first.filterTable;
  String get filterColumn =>
      filters.isEmpty ? '' : filters.first.filterColumn;

  factory BiModule.fromJson(Map<String, dynamic> json) {
    final filtersJson = json['filters'];
    return BiModule(
      id: json['id'] as String,
      name: TextSanitizer.normalize(json['name'] as String),
      panelUrl: json['panel_url'] as String? ?? '',
      filters: filtersJson is List
          ? filtersJson
                .whereType<Map>()
                .map(
                  (row) => BiModuleFilter.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <BiModuleFilter>[],
      sellerDefaultFilterId: json['seller_default_filter_id'] as String?,
      isSystem: json['is_system'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      type: json['type'] as String? ?? 'acompanhamento_bi',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'panel_url': panelUrl,
      'filters': filters.map((item) => item.toJson()).toList(),
      'seller_default_filter_id': sellerDefaultFilterId,
      'is_system': isSystem,
      'is_active': isActive,
      'type': type,
    };
  }

  BiModule copyWith({
    String? id,
    String? name,
    String? panelUrl,
    List<BiModuleFilter>? filters,
    String? sellerDefaultFilterId,
    bool? isSystem,
    bool? isActive,
    String? type,
  }) {
    return BiModule(
      id: id ?? this.id,
      name: name ?? this.name,
      panelUrl: panelUrl ?? this.panelUrl,
      filters: filters ?? this.filters,
      sellerDefaultFilterId:
          sellerDefaultFilterId ?? this.sellerDefaultFilterId,
      isSystem: isSystem ?? this.isSystem,
      isActive: isActive ?? this.isActive,
      type: type ?? this.type,
    );
  }
}
