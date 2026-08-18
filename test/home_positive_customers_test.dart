import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_vendas/models/home_positive_customers.dart';

void main() {
  test('parses new-customer summary and item flag', () {
    final result = HomePositiveCustomers.fromJson({
      'total_clients': 2,
      'total_new_customers': 1,
      'total_amount': 350.5,
      'items': [
        {
          'client_code': '10',
          'client_name': 'Cliente Novo',
          'total_amount': 200,
          'is_new_in_month': true,
        },
        {
          'client_code': '20',
          'client_name': 'Cliente Recorrente',
          'total_amount': 150.5,
          'is_new_in_month': false,
        },
      ],
    });

    expect(result.totalClients, 2);
    expect(result.totalNewCustomers, 1);
    expect(result.totalAmount, 350.5);
    expect(result.items.first.isNewInMonth, isTrue);
    expect(result.items.last.isNewInMonth, isFalse);
  });
}
