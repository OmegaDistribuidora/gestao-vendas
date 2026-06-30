import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_vendas/models/customers_without_purchase.dart';

void main() {
  group('CustomerRecentOrder', () {
    test('counts distinct detailed product codes', () {
      final order = CustomerRecentOrder.fromJson(<String, dynamic>{
        'numped': '888040457',
        'item_count': 1,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'codprod': '5838'},
          <String, dynamic>{'codprod': '5840'},
          <String, dynamic>{'codprod': '13242'},
          <String, dynamic>{'codprod': '5838'},
        ],
      });

      expect(order.itemCount, 3);
    });

    test('keeps summary count when details are unavailable', () {
      final order = CustomerRecentOrder.fromJson(<String, dynamic>{
        'numped': '888040682',
        'item_count': 3,
        'items': <Map<String, dynamic>>[],
      });

      expect(order.itemCount, 3);
    });
  });
}
