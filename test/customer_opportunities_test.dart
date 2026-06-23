import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_vendas/models/customer_opportunities.dart';

void main() {
  test('converts neighborhood, hierarchy and activity filters', () {
    final overview = CustomerOpportunitiesOverview.fromJson(<String, dynamic>{
      'viewer_profile_slug': 'coordenador',
      'viewer_user_code': '1',
      'selected_supervisor_code': '10',
      'selected_seller_code': '2144',
      'selected_neighborhood_key': 'fortaleza|centro',
      'selected_activity_key': '1',
      'last_updated_at': '2026-06-23T13:30:00Z',
      'available_supervisors': <Map<String, dynamic>>[
        <String, dynamic>{
          'code': '10',
          'name': 'Supervisor Teste',
          'label': '10 - Supervisor Teste',
        },
      ],
      'available_sellers': <Map<String, dynamic>>[
        <String, dynamic>{
          'code': '2144',
          'name': 'Vendedor Teste',
          'label': '2144 - Vendedor Teste',
        },
      ],
      'served_neighborhoods': <Map<String, dynamic>>[
        <String, dynamic>{
          'neighborhood_key': 'fortaleza|centro',
          'city': 'Fortaleza',
          'district': 'Centro',
          'opportunity_count': 120,
          'center_latitude': -3.7319,
          'center_longitude': -38.5267,
        },
      ],
      'available_activities': <Map<String, dynamic>>[
        <String, dynamic>{
          'activity_key': '1',
          'activity_code': '1',
          'activity_name': 'Mercadinho',
          'opportunity_count': 80,
        },
      ],
      'total_opportunities': 1,
      'opportunities': <List<dynamic>>[
        <dynamic>['12345678000190', -3.7319, -38.5267],
      ],
    });

    expect(overview.viewerProfileSlug, 'coordenador');
    expect(overview.selectedSupervisorCode, '10');
    expect(overview.selectedSellerCode, '2144');
    expect(overview.selectedNeighborhoodKey, 'fortaleza|centro');
    expect(overview.selectedActivityKey, '1');
    expect(overview.availableSupervisors.single.code, '10');
    expect(overview.availableSellers.single.code, '2144');
    expect(overview.servedNeighborhoods.single.label, 'Fortaleza - Centro');
    expect(overview.servedNeighborhoods.single.opportunityCount, 120);
    expect(overview.availableActivities.single.label, '1 - Mercadinho');
    expect(overview.totalOpportunities, 1);
    expect(overview.opportunities.single.taxId, '12345678000190');
  });

  test('converts opportunity details and market potential', () {
    final opportunity = CustomerOpportunity.fromJson(<String, dynamic>{
      'tax_id': '12345678000190',
      'source_customer_code': '205192',
      'client_name': 'Cliente Teste Ltda',
      'fantasy_name': 'Mercadinho Teste',
      'activity_code': '1',
      'activity_name': 'Mercadinho',
      'city': 'Fortaleza',
      'uf': 'ce',
      'district': 'Centro',
      'street': 'Rua Principal',
      'address_number': '100',
      'full_address': 'Rua Principal, 100',
      'postal_code': '60000000',
      'credit_limit': '2500.75',
      'market_potential': '1320.50',
      'market_potential_order_count': 3,
      'latitude': '-3.7319',
      'longitude': -38.5267,
      'suppliers': <Map<String, dynamic>>[
        <String, dynamic>{'code': '117', 'name': 'Bombril'},
      ],
    });

    expect(opportunity.displayName, 'Mercadinho Teste');
    expect(opportunity.activityLabel, '1 - Mercadinho');
    expect(opportunity.cityLabel, 'Fortaleza - CE');
    expect(opportunity.creditLimit, 2500.75);
    expect(opportunity.marketPotential, 1320.50);
    expect(opportunity.marketPotentialOrderCount, 3);
    expect(opportunity.latitude, -3.7319);
    expect(opportunity.suppliers.single.label, '117 - Bombril');
  });

  test('keeps market potential null when customer never purchased', () {
    final opportunity = CustomerOpportunity.fromJson(<String, dynamic>{
      'tax_id': '12345678901',
      'client_name': null,
      'fantasy_name': null,
      'city': 'Sobral',
      'market_potential': null,
      'market_potential_order_count': 0,
      'latitude': -3.69,
      'longitude': -40.35,
    });

    expect(opportunity.displayName, isEmpty);
    expect(opportunity.marketPotential, isNull);
    expect(opportunity.marketPotentialOrderCount, 0);
    expect(opportunity.suppliers, isEmpty);
  });

  test('converts compact map markers', () {
    final overview = CustomerOpportunitiesOverview.fromJson(<String, dynamic>{
      'opportunities': <List<dynamic>>[
        <dynamic>['12345678000190', -3.7319, -38.5267],
      ],
    });

    final marker = overview.opportunities.single;
    expect(marker.taxId, '12345678000190');
    expect(marker.latitude, -3.7319);
    expect(marker.longitude, -38.5267);
    expect(marker.displayName, isEmpty);
  });
}
