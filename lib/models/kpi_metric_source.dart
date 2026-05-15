enum KpiMetricSource { venda, faturamento }

extension KpiMetricSourceX on KpiMetricSource {
  String get value {
    switch (this) {
      case KpiMetricSource.venda:
        return 'venda';
      case KpiMetricSource.faturamento:
        return 'faturamento';
    }
  }

  String get label {
    switch (this) {
      case KpiMetricSource.venda:
        return 'Venda';
      case KpiMetricSource.faturamento:
        return 'Faturamento';
    }
  }
}

KpiMetricSource parseKpiMetricSource(String? rawValue) {
  switch (rawValue?.trim().toLowerCase()) {
    case 'faturamento':
      return KpiMetricSource.faturamento;
    case 'venda':
    default:
      return KpiMetricSource.venda;
  }
}
