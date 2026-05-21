import 'kpi_metric_source.dart';

class PerformanceOverview {
  const PerformanceOverview({
    required this.supported,
    required this.viewerProfileSlug,
    required this.profileSlug,
    required this.selectedScopeProfileSlug,
    required this.selectedScopeOwnerCode,
    required this.metricSource,
    required this.selectedMonthStart,
    required this.availableScopes,
    required this.availableMonths,
    required this.items,
    this.lastTargetsUpdatedAt,
    this.lastSalesUpdatedAt,
    this.lastFinancialUpdatedAt,
    this.lastSkuUpdatedAt,
  });

  final bool supported;
  final String viewerProfileSlug;
  final String profileSlug;
  final String? selectedScopeProfileSlug;
  final String? selectedScopeOwnerCode;
  final KpiMetricSource metricSource;
  final DateTime? selectedMonthStart;
  final List<PerformanceScopeOption> availableScopes;
  final List<PerformanceMonthOption> availableMonths;
  final List<PerformanceOverviewItem> items;
  final DateTime? lastTargetsUpdatedAt;
  final DateTime? lastSalesUpdatedAt;
  final DateTime? lastFinancialUpdatedAt;
  final DateTime? lastSkuUpdatedAt;

  PerformanceOverviewItem? get overallItem {
    for (final item in items) {
      if (item.isOverall) {
        return item;
      }
    }
    return null;
  }

  List<PerformanceOverviewItem> get supplierItems =>
      items.where((item) => !item.isOverall).toList();

  factory PerformanceOverview.empty() {
    return const PerformanceOverview(
      supported: true,
      viewerProfileSlug: '',
      profileSlug: '',
      selectedScopeProfileSlug: null,
      selectedScopeOwnerCode: null,
      metricSource: KpiMetricSource.venda,
      selectedMonthStart: null,
      availableScopes: <PerformanceScopeOption>[],
      availableMonths: <PerformanceMonthOption>[],
      items: <PerformanceOverviewItem>[],
    );
  }

  factory PerformanceOverview.fromJson(Map<String, dynamic> json) {
    final rawScopes = json['available_scopes'];
    final rawMonths = json['available_months'];
    final rawItems = json['items'];

    return PerformanceOverview(
      supported: json['supported'] as bool? ?? true,
      viewerProfileSlug: '${json['viewer_profile_slug'] ?? ''}',
      profileSlug: '${json['profile_slug'] ?? ''}',
      selectedScopeProfileSlug: _toNullableString(
        json['selected_scope_profile_slug'],
      ),
      selectedScopeOwnerCode: _toNullableString(json['selected_scope_owner_code']),
      metricSource: parseKpiMetricSource(json['metric_source'] as String?),
      selectedMonthStart: _parseDateTime(json['selected_month_start']),
      availableScopes: rawScopes is List
          ? rawScopes
                .whereType<Map>()
                .map(
                  (row) => PerformanceScopeOption.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <PerformanceScopeOption>[],
      availableMonths: rawMonths is List
          ? rawMonths
                .whereType<Map>()
                .map(
                  (row) => PerformanceMonthOption.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <PerformanceMonthOption>[],
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (row) => PerformanceOverviewItem.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <PerformanceOverviewItem>[],
      lastTargetsUpdatedAt: _parseDateTime(json['last_targets_updated_at']),
      lastSalesUpdatedAt: _parseDateTime(json['last_sales_updated_at']),
      lastFinancialUpdatedAt: _parseDateTime(json['last_financial_updated_at']),
      lastSkuUpdatedAt: _parseDateTime(json['last_sku_updated_at']),
    );
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static String? _toNullableString(Object? value) {
    final text = '$value'.trim();
    if (value == null || text.isEmpty || text == 'null') {
      return null;
    }
    return text;
  }
}

class PerformanceScopeOption {
  const PerformanceScopeOption({
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

  factory PerformanceScopeOption.fromJson(Map<String, dynamic> json) {
    return PerformanceScopeOption(
      profileSlug: '${json['profile_slug'] ?? ''}',
      ownerCode: '${json['owner_code'] ?? ''}',
      displayName: '${json['display_name'] ?? ''}',
      label: '${json['label'] ?? ''}',
    );
  }
}

class PerformanceMonthOption {
  const PerformanceMonthOption({required this.monthStart, required this.label});

  final DateTime monthStart;
  final String label;

  String get value => monthStart.toIso8601String().split('T').first;

  factory PerformanceMonthOption.fromJson(Map<String, dynamic> json) {
    final parsedMonthStart = DateTime.tryParse('${json['month_start'] ?? ''}');
    return PerformanceMonthOption(
      monthStart: parsedMonthStart ?? DateTime(2026, 1, 1),
      label: '${json['label'] ?? ''}',
    );
  }
}

class PerformanceOverviewItem {
  const PerformanceOverviewItem({
    required this.code,
    required this.supplierName,
    required this.financialMetricSource,
    required this.secondaryMetricSource,
    required this.targetFin,
    required this.actualFin,
    required this.actualPos,
    required this.actualSku,
    this.finProgressPct,
    this.targetPos,
    this.posProgressPct,
    this.targetSku,
    this.skuProgressPct,
    this.secondaryMetricType,
  });

  final String code;
  final String supplierName;
  final KpiMetricSource financialMetricSource;
  final KpiMetricSource secondaryMetricSource;
  final double targetFin;
  final double actualFin;
  final double? finProgressPct;
  final int? targetPos;
  final int actualPos;
  final double? posProgressPct;
  final int? targetSku;
  final int actualSku;
  final double? skuProgressPct;
  final String? secondaryMetricType;

  bool get isOverall => code == '1';
  bool get usesSkuMetric => secondaryMetricType == 'sku';
  bool get usesPositivationMetric => secondaryMetricType == 'positivacao';
  bool get hasSecondaryMetric => usesSkuMetric || usesPositivationMetric;
  bool get usesFinancialSourceForSecondary =>
      secondaryMetricSource == KpiMetricSource.faturamento;

  int? get secondaryTarget => usesSkuMetric ? targetSku : targetPos;
  int get secondaryActual => usesSkuMetric ? actualSku : actualPos;
  double? get secondaryProgressPct =>
      usesSkuMetric ? skuProgressPct : posProgressPct;
  String get secondaryLabel => usesSkuMetric ? 'SKU' : 'Positivacao';
  String get financialLabel =>
      financialMetricSource == KpiMetricSource.faturamento
      ? 'Faturamento Liquido'
      : 'Venda Liquida';

  factory PerformanceOverviewItem.fromJson(Map<String, dynamic> json) {
    return PerformanceOverviewItem(
      code: '${json['code'] ?? ''}',
      supplierName: '${json['supplier_name'] ?? ''}',
      financialMetricSource: parseKpiMetricSource(
        json['financial_metric_source'] as String?,
      ),
      secondaryMetricSource: parseKpiMetricSource(
        json['secondary_metric_source'] as String?,
      ),
      targetFin: _toDouble(json['target_fin']),
      actualFin: _toDouble(json['actual_fin']),
      finProgressPct: _toNullableDouble(json['fin_progress_pct']),
      targetPos: _toNullableInt(json['target_pos']),
      actualPos: _toInt(json['actual_pos']),
      posProgressPct: _toNullableDouble(json['pos_progress_pct']),
      targetSku: _toNullableInt(json['target_sku']),
      actualSku: _toInt(json['actual_sku']),
      skuProgressPct: _toNullableDouble(json['sku_progress_pct']),
      secondaryMetricType: json['secondary_metric_type'] as String?,
    );
  }

  static double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? 0;
    }
    return 0;
  }

  static double? _toNullableDouble(Object? value) {
    if (value == null) {
      return null;
    }
    return _toDouble(value);
  }

  static int _toInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  static int? _toNullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    return _toInt(value);
  }
}
