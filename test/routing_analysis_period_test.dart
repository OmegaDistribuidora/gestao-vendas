import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_vendas/models/routing_analysis.dart';

void main() {
  test('parses a period and keeps repeated customer visits by date', () {
    final analysis = RoutingAnalysis.fromJson(<String, dynamic>{
      'available': true,
      'applicable': true,
      'reference_date': '2026-09-14',
      'start_date': '2026-09-14',
      'end_date': '2026-09-19',
      'requested_days': 6,
      'available_days': 5,
      'missing_dates': <String>['2026-09-19'],
      'effective_profile_slug': 'vendedor',
      'effective_owner_code': '2634',
      'effective_display_name': 'Vendedor',
      'planned': 2,
      'purchased': 1,
      'sale_amount': 100,
      'map_available': true,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'reference_date': '2026-09-14',
          'customer_code': '1',
          'customer_name': 'Cliente',
          'seller_code': '2634',
          'purchased': true,
        },
        <String, dynamic>{
          'reference_date': '2026-09-16',
          'customer_code': '1',
          'customer_name': 'Cliente',
          'seller_code': '2634',
          'purchased': false,
        },
      ],
    });

    expect(analysis.isPeriod, isTrue);
    expect(analysis.hasIncompletePeriod, isTrue);
    expect(analysis.items, hasLength(2));
    expect(analysis.items.first.referenceDate, DateTime(2026, 9, 14));
    expect(analysis.items.last.referenceDate, DateTime(2026, 9, 16));
  });
}
