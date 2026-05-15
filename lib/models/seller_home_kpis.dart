import 'kpi_metric_source.dart';

class SellerHomeKpis {
  const SellerHomeKpis({
    required this.metricSource,
    required this.grossAmount,
    required this.grossVolume,
    required this.grossOrders,
    required this.grossPositivation,
    required this.returnAmount,
    required this.returnVolume,
    required this.returnOrders,
    required this.returnPositivation,
    required this.lastSalesUpdatedAt,
    required this.lastFinancialUpdatedAt,
  });

  final KpiMetricSource metricSource;
  final double grossAmount;
  final double grossVolume;
  final int grossOrders;
  final int grossPositivation;
  final double returnAmount;
  final double returnVolume;
  final int returnOrders;
  final int returnPositivation;
  final DateTime? lastSalesUpdatedAt;
  final DateTime? lastFinancialUpdatedAt;

  factory SellerHomeKpis.empty() {
    return const SellerHomeKpis(
      metricSource: KpiMetricSource.venda,
      grossAmount: 0,
      grossVolume: 0,
      grossOrders: 0,
      grossPositivation: 0,
      returnAmount: 0,
      returnVolume: 0,
      returnOrders: 0,
      returnPositivation: 0,
      lastSalesUpdatedAt: null,
      lastFinancialUpdatedAt: null,
    );
  }

  factory SellerHomeKpis.fromJson(Map<String, dynamic> json) {
    return SellerHomeKpis(
      metricSource: parseKpiMetricSource(json['metric_source'] as String?),
      grossAmount:
          (json['gross_amount'] as num?)?.toDouble() ??
          (json['total_venda'] as num?)?.toDouble() ??
          0,
      grossVolume:
          (json['gross_volume'] as num?)?.toDouble() ??
          (json['total_volume'] as num?)?.toDouble() ??
          0,
      grossOrders:
          (json['gross_orders'] as num?)?.toInt() ??
          (json['total_pedidos'] as num?)?.toInt() ??
          0,
      grossPositivation:
          (json['gross_positivation'] as num?)?.toInt() ??
          (json['total_positivacao'] as num?)?.toInt() ??
          0,
      returnAmount: (json['return_amount'] as num?)?.toDouble() ?? 0,
      returnVolume: (json['return_volume'] as num?)?.toDouble() ?? 0,
      returnOrders: (json['return_orders'] as num?)?.toInt() ?? 0,
      returnPositivation:
          (json['return_positivation'] as num?)?.toInt() ?? 0,
      lastSalesUpdatedAt: _parseDate(json['last_sales_updated_at']),
      lastFinancialUpdatedAt: _parseDate(json['last_financial_updated_at']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }
}
