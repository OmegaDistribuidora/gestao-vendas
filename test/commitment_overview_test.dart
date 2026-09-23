import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_vendas/models/app_profile.dart';
import 'package:gestao_vendas/models/commitment_overview.dart';

void main() {
  test('company total sums coordinators without duplicating supervisors', () {
    final total = CommitmentItem.companyTotalFrom(<CommitmentItem>[
      _item(
        profileSlug: AppProfile.coordinatorSlug,
        ownerCode: '10',
        financialTarget: 1012000,
        positivationTarget: 800,
        financialActual: 500000,
        positivationActual: 420,
        financialClosedActual: 450000,
        positivationClosedActual: 390,
        lastUpdatedAt: DateTime(2026, 8, 25, 9),
      ),
      _item(
        profileSlug: AppProfile.coordinatorSlug,
        ownerCode: '12',
        financialTarget: 900000,
        positivationTarget: 700,
        financialActual: 400000,
        positivationActual: 310,
        financialClosedActual: 360000,
        positivationClosedActual: 280,
        lastUpdatedAt: DateTime(2026, 8, 25, 10),
      ),
      _item(
        profileSlug: AppProfile.supervisorSlug,
        ownerCode: '20',
        financialTarget: 250000,
        positivationTarget: 200,
        financialActual: 100000,
        positivationActual: 90,
        financialClosedActual: 90000,
        positivationClosedActual: 80,
        lastUpdatedAt: DateTime(2026, 8, 25, 11),
      ),
    ]);

    expect(total, isNotNull);
    expect(total!.profileSlug, CommitmentItem.companyProfileSlug);
    expect(total.displayName, 'Ômega Distribuidora');
    expect(total.financialTarget, 1912000);
    expect(total.positivationTarget, 1500);
    expect(total.financialActual, 900000);
    expect(total.positivationActual, 730);
    expect(total.financialClosedActual, 810000);
    expect(total.positivationClosedActual, 670);
    expect(total.lastUpdatedAt, DateTime(2026, 8, 25, 10));
  });

  test('company total is absent when there are no coordinator rows', () {
    final total = CommitmentItem.companyTotalFrom(<CommitmentItem>[
      _item(
        profileSlug: AppProfile.supervisorSlug,
        ownerCode: '20',
        financialTarget: 250000,
        positivationTarget: 200,
        financialActual: 100000,
        positivationActual: 90,
        financialClosedActual: 90000,
        positivationClosedActual: 80,
      ),
    ]);

    expect(total, isNull);
  });

  test(
    'routing is parsed only when the commitment item has planned visits',
    () {
      final withRouting = CommitmentItem.fromJson(<String, dynamic>{
        'profile_slug': 'supervisor',
        'owner_code': '20',
        'display_name': 'Supervisor 20',
        'routing_planned': 18,
        'routing_purchased': 9,
        'routing_percent': 50,
        'routing_sale_amount': 1250.50,
        'routing_requested_days': 6,
        'routing_available_days': 5,
      });
      final withoutRouting = CommitmentItem.fromJson(<String, dynamic>{
        'profile_slug': 'supervisor',
        'owner_code': '33',
        'display_name': 'Supervisor 33',
      });

      expect(withRouting.hasRouting, isTrue);
      expect(withRouting.routingPlanned, 18);
      expect(withRouting.routingPurchased, 9);
      expect(withRouting.routingPercent, 50);
      expect(withoutRouting.hasRouting, isFalse);
      expect(withoutRouting.routingPlanned, isNull);
    },
  );
}

CommitmentItem _item({
  required String profileSlug,
  required String ownerCode,
  required double financialTarget,
  required double positivationTarget,
  required double financialActual,
  required int positivationActual,
  required double financialClosedActual,
  required int positivationClosedActual,
  DateTime? lastUpdatedAt,
}) {
  return CommitmentItem(
    profileSlug: profileSlug,
    ownerCode: ownerCode,
    displayName: ownerCode,
    financialTarget: financialTarget,
    positivationTarget: positivationTarget,
    financialActual: financialActual,
    positivationActual: positivationActual,
    financialClosedActual: financialClosedActual,
    positivationClosedActual: positivationClosedActual,
    lastUpdatedAt: lastUpdatedAt,
  );
}
