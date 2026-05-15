import '../utils/text_sanitizer.dart';
import 'kpi_metric_source.dart';

class SupplierAnalysis {
  const SupplierAnalysis({
    required this.metricSource,
    required this.lastUpdatedAt,
    required this.suppliers,
  });

  final KpiMetricSource metricSource;
  final DateTime? lastUpdatedAt;
  final List<SupplierAnalysisItem> suppliers;

  factory SupplierAnalysis.empty() {
    return const SupplierAnalysis(
      metricSource: KpiMetricSource.venda,
      lastUpdatedAt: null,
      suppliers: <SupplierAnalysisItem>[],
    );
  }

  factory SupplierAnalysis.fromJson(Map<String, dynamic> json) {
    final suppliersJson = json['suppliers'];
    return SupplierAnalysis(
      metricSource: parseKpiMetricSource(json['metric_source'] as String?),
      lastUpdatedAt: _parseDate(json['last_updated_at']),
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
}

class SupplierAnalysisItem {
  const SupplierAnalysisItem({
    required this.code,
    required this.supplierName,
    required this.grossAmount,
    required this.grossVolume,
    required this.grossOrders,
    required this.grossPositivation,
  });

  final String code;
  final String supplierName;
  final double grossAmount;
  final double grossVolume;
  final int grossOrders;
  final int grossPositivation;

  factory SupplierAnalysisItem.fromJson(Map<String, dynamic> json) {
    return SupplierAnalysisItem(
      code: '${json['code'] ?? ''}'.trim(),
      supplierName: TextSanitizer.normalize(
        json['supplier_name'] as String? ?? '',
      ),
      grossAmount: (json['gross_amount'] as num?)?.toDouble() ?? 0,
      grossVolume: (json['gross_volume'] as num?)?.toDouble() ?? 0,
      grossOrders: (json['gross_orders'] as num?)?.toInt() ?? 0,
      grossPositivation:
          (json['gross_positivation'] as num?)?.toInt() ?? 0,
    );
  }
}
