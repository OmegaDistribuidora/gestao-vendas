import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_vendas/models/app_profile.dart';
import 'package:gestao_vendas/models/routing_analysis.dart';

AppProfile _profile(String slug) =>
    AppProfile(id: slug, name: slug, slug: slug);

void main() {
  test('routing module is available only to the commercial hierarchy', () {
    for (final slug in <String>[
      AppProfile.sellerSlug,
      AppProfile.supervisorSlug,
      AppProfile.coordinatorSlug,
      AppProfile.managementSlug,
      AppProfile.boardSlug,
      AppProfile.othersSlug,
    ]) {
      expect(_profile(slug).canAccessRoutingAnalysis, isTrue, reason: slug);
    }
    expect(_profile(AppProfile.adminSlug).canAccessRoutingAnalysis, isFalse);
    expect(
      _profile(AppProfile.unassignedSlug).canAccessRoutingAnalysis,
      isFalse,
    );
  });

  test('parses seller summary, customer address, sales and coordinates', () {
    final analysis = RoutingAnalysis.fromJson(<String, dynamic>{
      'available': true,
      'applicable': true,
      'reference_date': '2026-09-11',
      'effective_profile_slug': 'vendedor',
      'effective_owner_code': '2515',
      'effective_display_name': 'Vendedor teste',
      'planned': 10,
      'purchased': 4,
      'percent': 40,
      'sale_amount': 5235.84,
      'map_available': true,
      'available_scopes': <Object>[],
      'seller_summaries': <Object>[
        <String, dynamic>{
          'seller_code': '2515',
          'seller_name': 'Vendedor teste',
          'supervisor_code': '23',
          'coordinator_code': '10',
          'planned': 10,
          'purchased': 4,
          'percent': 40,
          'sale_amount': 5235.84,
        },
      ],
      'items': <Object>[
        <String, dynamic>{
          'customer_code': '100',
          'customer_name': 'Cliente teste',
          'seller_code': '2515',
          'seller_name': 'Vendedor teste',
          'address': 'Rua Principal, 10',
          'neighborhood': 'Centro',
          'city': 'Fortaleza',
          'purchased': true,
          'sale_amount': 150.75,
          'order_count': 1,
          'route_code': '2',
          'route_sequence': 7,
          'latitude': -3.73,
          'longitude': -38.52,
        },
      ],
    });

    expect(analysis.pending, 6);
    expect(analysis.isSellerView, isTrue);
    expect(analysis.sellerSummaries.single.saleAmount, 5235.84);
    expect(analysis.items.single.hasCoordinates, isTrue);
    expect(
      analysis.items.single.addressLine,
      'Rua Principal, 10 • Centro • Fortaleza',
    );
    expect(analysis.items.single.saleAmount, 150.75);
  });

  test('rejects missing or invalid customer coordinates for the map', () {
    RoutingCustomer customer(Object? latitude, Object? longitude) =>
        RoutingCustomer.fromJson(<String, dynamic>{
          'customer_code': '1',
          'latitude': latitude,
          'longitude': longitude,
        });

    expect(customer(null, null).hasCoordinates, isFalse);
    expect(customer(0, 0).hasCoordinates, isFalse);
    expect(customer(-95, -38).hasCoordinates, isFalse);
    expect(customer(-3.7, -38.5).hasCoordinates, isTrue);
  });
}
