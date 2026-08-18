import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_vendas/models/delinquency_overview.dart';
import 'package:gestao_vendas/models/supplier_analysis.dart';

void main() {
  test('parses delinquency client address from enriched overview', () {
    final client = DelinquencyClientSummary.fromJson({
      'codcli': '58787',
      'client_name': 'Super Bom Preco',
      'address': 'Av Vicente Alves Costa, 104 - Zezinho Costa - Varzea Alegre',
      'total_amount': 29000,
      'total_orders': 4,
      'orders': <Object?>[],
    });

    expect(client.codcli, '58787');
    expect(
      client.address,
      'Av Vicente Alves Costa, 104 - Zezinho Costa - Varzea Alegre',
    );
  });

  test('parses hierarchy scopes used by supplier analysis filter', () {
    final analysis = SupplierAnalysis.fromJson({
      'metric_source': 'venda',
      'viewer_profile_slug': 'coordenador',
      'selected_scope_profile_slug': 'vendedor',
      'selected_scope_owner_code': '311',
      'available_scopes': [
        {
          'profile_slug': 'supervisor',
          'owner_code': '20',
          'display_name': 'Fabio',
        },
        {
          'profile_slug': 'vendedor',
          'owner_code': '311',
          'display_name': 'Francisco',
        },
      ],
      'suppliers': <Object?>[],
    });

    expect(analysis.viewerProfileSlug, 'coordenador');
    expect(analysis.selectedScopeProfileSlug, 'vendedor');
    expect(analysis.selectedScopeOwnerCode, '311');
    expect(analysis.availableScopes, hasLength(2));
    expect(analysis.availableScopes.first.value, 'supervisor|20');
    expect(analysis.availableScopes.first.label, 'Supervisor - 20 - Fabio');
    expect(analysis.availableScopes.last.value, 'vendedor|311');
  });
}
