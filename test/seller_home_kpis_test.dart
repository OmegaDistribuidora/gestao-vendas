import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_vendas/models/seller_home_kpis.dart';

void main() {
  test('parses the daily new positivation used by progress', () {
    final kpis = SellerHomeKpis.fromJson(const <String, dynamic>{
      'gross_positivation': 267,
      'daily_new_positivation': 183,
      'daily_secondary_target': 278,
      'secondary_metric_type': 'positivacao',
    });

    expect(kpis.grossPositivation, 267);
    expect(kpis.dailyNewPositivation, 183);
    expect(kpis.dailySecondaryTarget, 278);
  });

  test('keeps compatibility when daily new positivation is absent', () {
    final kpis = SellerHomeKpis.fromJson(const <String, dynamic>{
      'gross_positivation': 12,
    });

    expect(kpis.dailyNewPositivation, isNull);
  });
}
