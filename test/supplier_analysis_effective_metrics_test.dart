import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_vendas/models/supplier_analysis.dart';

void main() {
  test('uses effective order and positivation totals returned by backend', () {
    final item = SupplierAnalysisItem.fromJson(const <String, dynamic>{
      'code': '117',
      'supplier_name': 'Fornecedor',
      'gross_amount': 10000,
      'return_amount': -100,
      'gross_volume': 10,
      'return_volume': -0.1,
      'gross_orders': 1,
      'return_orders': 1,
      'gross_positivation': 1,
      'return_positivation': 1,
      'net_orders': 1,
      'net_positivation': 1,
    });

    expect(item.netAmount, 9900);
    expect(item.netOrders, 1);
    expect(item.netPositivation, 1);
  });

  test('keeps compatibility with payloads without effective totals', () {
    final item = SupplierAnalysisItem.fromJson(const <String, dynamic>{
      'gross_orders': 3,
      'return_orders': 1,
      'gross_positivation': 2,
      'return_positivation': 1,
    });

    expect(item.netOrders, 2);
    expect(item.netPositivation, 1);
    expect(item.positivationLabel, '1');
  });

  test('shows new monthly customers when backend provides the count', () {
    final item = SupplierAnalysisItem.fromJson(const <String, dynamic>{
      'net_positivation': 18,
      'new_positivation': 6,
    });

    expect(item.newPositivation, 6);
    expect(item.positivationLabel, '18 (6 novos)');
  });

  test('uses singular label for one new monthly customer', () {
    final item = SupplierAnalysisItem.fromJson(const <String, dynamic>{
      'net_positivation': 4,
      'new_positivation': 1,
    });

    expect(item.positivationLabel, '4 (1 novo)');
  });
}
