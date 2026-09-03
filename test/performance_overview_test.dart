import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_vendas/models/app_profile.dart';
import 'package:gestao_vendas/models/performance_overview.dart';

void main() {
  test('selected seller uses seller display rules for a supervisor viewer', () {
    final overview = PerformanceOverview.fromJson(<String, dynamic>{
      'supported': true,
      'viewer_profile_slug': 'supervisor',
      'profile_slug': 'vendedor',
      'selected_scope_profile_slug': 'vendedor',
      'selected_scope_owner_code': '311',
      'metric_source': 'venda',
      'items': <Object?>[],
      'available_scopes': <Object?>[],
      'available_months': <Object?>[],
    });

    expect(overview.viewerProfileSlug, 'supervisor');
    expect(overview.isSellerView, isTrue);
    expect(overview.isNamedProfileView, isTrue);
    expect(overview.isBroadProfileView, isFalse);
  });

  test('selected coordinator uses prize-capable display for board viewer', () {
    final overview = PerformanceOverview.fromJson(<String, dynamic>{
      'supported': true,
      'viewer_profile_slug': 'diretoria',
      'profile_slug': 'coordenador',
      'selected_scope_profile_slug': 'coordenador',
      'selected_scope_owner_code': '12',
      'metric_source': 'venda',
      'items': <Object?>[],
      'available_scopes': <Object?>[],
      'available_months': <Object?>[],
    });

    expect(overview.viewerProfileSlug, 'diretoria');
    expect(overview.isCoordinatorView, isTrue);
    expect(overview.isNamedProfileView, isTrue);
    expect(overview.isBroadProfileView, isFalse);
  });

  test('unfiltered board view remains broad and without personal prizes', () {
    final overview = PerformanceOverview.fromJson(<String, dynamic>{
      'supported': true,
      'viewer_profile_slug': 'diretoria',
      'profile_slug': 'diretoria',
      'metric_source': 'venda',
      'items': <Object?>[],
      'available_scopes': <Object?>[],
      'available_months': <Object?>[],
    });

    expect(overview.isNamedProfileView, isFalse);
    expect(overview.isBroadProfileView, isTrue);
  });

  test('unfiltered management view follows broad performance rules', () {
    final overview = PerformanceOverview.fromJson(<String, dynamic>{
      'supported': true,
      'viewer_profile_slug': AppProfile.managementSlug,
      'profile_slug': AppProfile.managementSlug,
      'metric_source': 'venda',
      'items': <Object?>[],
      'available_scopes': <Object?>[],
      'available_months': <Object?>[],
    });

    expect(overview.isNamedProfileView, isFalse);
    expect(overview.isBroadProfileView, isTrue);
  });

  test('prize-paying suppliers are shown first for a named profile', () {
    final overview = PerformanceOverview.fromJson(<String, dynamic>{
      'supported': true,
      'viewer_profile_slug': 'supervisor',
      'profile_slug': 'vendedor',
      'metric_source': 'venda',
      'available_scopes': <Object?>[],
      'available_months': <Object?>[],
      'items': <Object?>[
        <String, dynamic>{
          'code': '200',
          'supplier_name': 'Sem premio A',
          'possibility_total': 0,
        },
        <String, dynamic>{
          'code': '117',
          'supplier_name': 'Top 5 A',
          'possibility_total': 180,
        },
        <String, dynamic>{
          'code': '201',
          'supplier_name': 'Sem premio B',
          'possibility_total': 0,
        },
        <String, dynamic>{
          'code': '967',
          'supplier_name': 'Top 5 B',
          'metrics': <Object?>[
            <String, dynamic>{
              'key': 'volume',
              'label': 'Volume',
              'possibility': 60,
            },
          ],
        },
      ],
    });

    expect(overview.supplierItems.map((item) => item.code), <String>[
      '117',
      '967',
      '200',
      '201',
    ]);
    expect(overview.supplierItems.first.hasPrizePossibility, isTrue);
    expect(overview.supplierItems[1].hasPrizePossibility, isTrue);
  });

  test('broad profiles keep supplier order and do not prioritize prizes', () {
    final overview = PerformanceOverview.fromJson(<String, dynamic>{
      'supported': true,
      'viewer_profile_slug': 'diretoria',
      'profile_slug': 'diretoria',
      'metric_source': 'venda',
      'available_scopes': <Object?>[],
      'available_months': <Object?>[],
      'items': <Object?>[
        <String, dynamic>{
          'code': '200',
          'supplier_name': 'Primeiro',
          'possibility_total': 0,
        },
        <String, dynamic>{
          'code': '117',
          'supplier_name': 'Segundo',
          'possibility_total': 180,
        },
      ],
    });

    expect(overview.supplierItems.map((item) => item.code), <String>[
      '200',
      '117',
    ]);
  });
}
