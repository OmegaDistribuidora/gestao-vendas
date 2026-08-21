import '../utils/text_sanitizer.dart';
import 'kpi_metric_source.dart';

class SupplierAnalysis {
  const SupplierAnalysis({
    required this.metricSource,
    required this.viewerProfileSlug,
    required this.selectedScopeProfileSlug,
    required this.selectedScopeOwnerCode,
    required this.availableScopes,
    required this.lastUpdatedAt,
    required this.overall,
    required this.suppliers,
  });

  final KpiMetricSource metricSource;
  final String viewerProfileSlug;
  final String? selectedScopeProfileSlug;
  final String? selectedScopeOwnerCode;
  final List<SupplierAnalysisScope> availableScopes;
  final DateTime? lastUpdatedAt;
  final SupplierAnalysisItem? overall;
  final List<SupplierAnalysisItem> suppliers;

  factory SupplierAnalysis.empty() {
    return const SupplierAnalysis(
      metricSource: KpiMetricSource.venda,
      viewerProfileSlug: '',
      selectedScopeProfileSlug: null,
      selectedScopeOwnerCode: null,
      availableScopes: <SupplierAnalysisScope>[],
      lastUpdatedAt: null,
      overall: null,
      suppliers: <SupplierAnalysisItem>[],
    );
  }

  factory SupplierAnalysis.fromJson(Map<String, dynamic> json) {
    final suppliersJson = json['suppliers'];
    final overallJson = json['overall'];
    final scopesJson = json['available_scopes'];
    return SupplierAnalysis(
      metricSource: parseKpiMetricSource(json['metric_source'] as String?),
      viewerProfileSlug: '${json['viewer_profile_slug'] ?? ''}'.trim(),
      selectedScopeProfileSlug: _nullableString(
        json['selected_scope_profile_slug'],
      ),
      selectedScopeOwnerCode: _nullableString(
        json['selected_scope_owner_code'],
      ),
      availableScopes: scopesJson is List
          ? scopesJson
                .whereType<Map>()
                .map(
                  (row) => SupplierAnalysisScope.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <SupplierAnalysisScope>[],
      lastUpdatedAt: _parseDate(json['last_updated_at']),
      overall: overallJson is Map
          ? SupplierAnalysisItem.fromJson(
              overallJson.map((key, value) => MapEntry('$key', value)),
            )
          : null,
      suppliers: suppliersJson is List
          ? suppliersJson
                .whereType<Map>()
                .map(
                  (row) => SupplierAnalysisItem.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <SupplierAnalysisItem>[],
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }

  static String? _nullableString(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }
}

class SupplierAnalysisScope {
  const SupplierAnalysisScope({
    required this.profileSlug,
    required this.ownerCode,
    required this.displayName,
    required this.label,
  });

  final String profileSlug;
  final String ownerCode;
  final String displayName;
  final String label;

  String get value => '$profileSlug|$ownerCode';

  factory SupplierAnalysisScope.fromJson(Map<String, dynamic> json) {
    final profileSlug = '${json['profile_slug'] ?? ''}'.trim();
    final ownerCode = '${json['owner_code'] ?? ''}'.trim();
    final displayName = TextSanitizer.normalize(
      '${json['display_name'] ?? ''}'.trim(),
    );
    final profileName = profileSlug == 'supervisor' ? 'Supervisor' : 'Vendedor';

    return SupplierAnalysisScope(
      profileSlug: profileSlug,
      ownerCode: ownerCode,
      displayName: displayName,
      label: '$profileName - $ownerCode - $displayName',
    );
  }
}

class SupplierAnalysisItem {
  const SupplierAnalysisItem({
    required this.code,
    required this.supplierName,
    required this.grossAmount,
    required this.returnAmount,
    required this.returnVolume,
    required this.returnOrders,
    required this.returnPositivation,
    required this.grossVolume,
    required this.grossOrders,
    required this.grossPositivation,
    this.effectiveOrders,
    this.effectivePositivation,
    this.newPositivation,
  });

  final String code;
  final String supplierName;
  final double grossAmount;
  final double returnAmount;
  final double returnVolume;
  final int returnOrders;
  final int returnPositivation;
  final double grossVolume;
  final int grossOrders;
  final int grossPositivation;
  final int? effectiveOrders;
  final int? effectivePositivation;
  final int? newPositivation;

  double get netAmount => grossAmount + returnAmount;
  double get netVolume => grossVolume + returnVolume;
  int get netOrders =>
      effectiveOrders ?? _clampPositive(grossOrders - returnOrders);
  int get netPositivation =>
      effectivePositivation ??
      _clampPositive(grossPositivation - returnPositivation);
  String get positivationLabel {
    final newCustomers = newPositivation;
    if (newCustomers == null) {
      return '$netPositivation';
    }
    return '$netPositivation ($newCustomers ${newCustomers == 1 ? 'novo' : 'novos'})';
  }

  factory SupplierAnalysisItem.fromJson(Map<String, dynamic> json) {
    return SupplierAnalysisItem(
      code: '${json['code'] ?? ''}'.trim(),
      supplierName: TextSanitizer.normalize(
        json['supplier_name'] as String? ?? '',
      ),
      grossAmount: (json['gross_amount'] as num?)?.toDouble() ?? 0,
      returnAmount: (json['return_amount'] as num?)?.toDouble() ?? 0,
      returnVolume: (json['return_volume'] as num?)?.toDouble() ?? 0,
      returnOrders: (json['return_orders'] as num?)?.toInt() ?? 0,
      returnPositivation: (json['return_positivation'] as num?)?.toInt() ?? 0,
      grossVolume: (json['gross_volume'] as num?)?.toDouble() ?? 0,
      grossOrders: (json['gross_orders'] as num?)?.toInt() ?? 0,
      grossPositivation: (json['gross_positivation'] as num?)?.toInt() ?? 0,
      effectiveOrders: (json['net_orders'] as num?)?.toInt(),
      effectivePositivation: (json['net_positivation'] as num?)?.toInt(),
      newPositivation: (json['new_positivation'] as num?)?.toInt(),
    );
  }

  static int _clampPositive(int value) => value < 0 ? 0 : value;
}
