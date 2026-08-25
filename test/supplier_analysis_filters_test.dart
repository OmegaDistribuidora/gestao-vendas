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
          'profile_slug': 'vendedor',
          'owner_code': '311',
          'display_name': 'Francisco',
        },
        {
          'profile_slug': 'coordenador',
          'owner_code': '10',
          'display_name': 'Coordenador Interior',
        },
        {
          'profile_slug': 'supervisor',
          'owner_code': '20',
          'display_name': 'Fabio',
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

  test('supervisor scope filter exposes only sellers', () {
    final analysis = SupplierAnalysis.fromJson({
      'metric_source': 'venda',
      'viewer_profile_slug': 'supervisor',
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

    expect(analysis.availableScopes, hasLength(1));
    expect(analysis.availableScopes.single.value, 'vendedor|311');
  });

  test('board scopes are ordered as coordinators supervisors and sellers', () {
    final analysis = SupplierAnalysis.fromJson({
      'metric_source': 'venda',
      'viewer_profile_slug': 'diretoria',
      'available_scopes': [
        {
          'profile_slug': 'vendedor',
          'owner_code': '311',
          'display_name': 'Francisco',
        },
        {
          'profile_slug': 'supervisor',
          'owner_code': '20',
          'display_name': 'Fabio',
        },
        {
          'profile_slug': 'coordenador',
          'owner_code': '10',
          'display_name': 'Coordenador Interior',
        },
      ],
      'suppliers': <Object?>[],
    });

    expect(analysis.availableScopes.map((scope) => scope.profileSlug), <String>[
      'coordenador',
      'supervisor',
      'vendedor',
    ]);
    expect(
      analysis.availableScopes.first.label,
      'Coordenador - 10 - Coordenador Interior',
    );
  });
}
