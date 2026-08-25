import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_vendas/models/home_dashboard.dart';

void main() {
  test('parses selected home scope and its dashboard payloads', () {
    final dashboard = HomeDashboard.fromJson(<String, dynamic>{
      'viewer_profile_slug': 'coordenador',
      'effective_profile_slug': 'vendedor',
      'effective_owner_code': '311',
      'selected_scope_profile_slug': 'vendedor',
      'selected_scope_owner_code': '311',
      'available_scopes': <Map<String, dynamic>>[
        <String, dynamic>{
          'profile_slug': 'supervisor',
          'owner_code': '33',
          'display_name': 'Felipe',
          'label': 'Supervisor - 33 - Felipe',
        },
        <String, dynamic>{
          'profile_slug': 'vendedor',
          'owner_code': '311',
          'display_name': 'Francisco',
          'label': 'Vendedor - 311 - Francisco',
        },
      ],
      'home_kpis': <String, dynamic>{
        'metric_source': 'venda',
        'gross_amount': 2485.80,
        'gross_positivation': 2,
        'daily_new_positivation': 1,
      },
      'positive_customers': <String, dynamic>{
        'total_clients': 2,
        'total_new_customers': 1,
        'total_amount': 2485.80,
        'items': <Map<String, dynamic>>[],
      },
      'performance_overview': <String, dynamic>{
        'supported': true,
        'viewer_profile_slug': 'vendedor',
        'profile_slug': 'vendedor',
        'items': <Map<String, dynamic>>[],
      },
      'commitment_overview': <String, dynamic>{
        'viewer_profile_slug': '',
        'available_periods': <Map<String, dynamic>>[],
        'available_scopes': <Map<String, dynamic>>[],
        'items': <Map<String, dynamic>>[],
      },
    });

    expect(dashboard.viewerProfileSlug, 'coordenador');
    expect(dashboard.effectiveProfileSlug, 'vendedor');
    expect(dashboard.effectiveOwnerCode, '311');
    expect(dashboard.selectedScopeProfileSlug, 'vendedor');
    expect(dashboard.selectedScopeOwnerCode, '311');
    expect(dashboard.availableScopes, hasLength(2));
    expect(dashboard.availableScopes.first.profileLabel, 'Supervisor');
    expect(dashboard.availableScopes.last.value, 'vendedor|311');
    expect(dashboard.kpis.grossAmount, 2485.80);
    expect(dashboard.kpis.dailyNewPositivation, 1);
    expect(dashboard.positiveCustomers.totalNewCustomers, 1);
  });
}
