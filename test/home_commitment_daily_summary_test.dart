import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_vendas/models/app_profile.dart';
import 'package:gestao_vendas/models/commitment_overview.dart';
import 'package:gestao_vendas/models/home_commitment_daily_summary.dart';

void main() {
  test('uses the active supervisor commitment daily need on the home', () {
    final summary = HomeCommitmentDailySummary.fromOverview(
      overview: _overview(<CommitmentItem>[
        _item(
          profileSlug: AppProfile.supervisorSlug,
          ownerCode: '20',
          financialTarget: 250000,
          positivationTarget: 200,
          financialActual: 4628.02,
          positivationActual: 9,
        ),
      ]),
      viewerProfileSlug: AppProfile.supervisorSlug,
      referenceDate: DateTime(2026, 8, 24),
    );

    expect(summary, isNotNull);
    expect(summary!.financialNeed, closeTo(41666.6667, 0.001));
    expect(summary.positivationNeed, closeTo(33.3333, 0.001));
  });

  test(
    'board home consolidates coordinators without duplicating supervisors',
    () {
      final summary = HomeCommitmentDailySummary.fromOverview(
        overview: _overview(<CommitmentItem>[
          _item(
            profileSlug: AppProfile.coordinatorSlug,
            ownerCode: '10',
            financialTarget: 850000,
            positivationTarget: 600,
            financialActual: 100000,
            positivationActual: 100,
          ),
          _item(
            profileSlug: AppProfile.supervisorSlug,
            ownerCode: '20',
            financialTarget: 250000,
            positivationTarget: 200,
            financialActual: 30000,
            positivationActual: 30,
          ),
        ]),
        viewerProfileSlug: AppProfile.boardSlug,
        referenceDate: DateTime(2026, 8, 24),
      );

      expect(summary, isNotNull);
      expect(summary!.financialNeed, closeTo(141666.6667, 0.001));
      expect(summary.positivationNeed, 100);
    },
  );

  test(
    'coordinator home uses its consolidated row without adding supervisors',
    () {
      final summary = HomeCommitmentDailySummary.fromOverview(
        overview: _overview(<CommitmentItem>[
          _item(
            profileSlug: AppProfile.coordinatorSlug,
            ownerCode: '10',
            financialTarget: 850000,
            positivationTarget: 600,
            financialActual: 100000,
            positivationActual: 100,
          ),
          _item(
            profileSlug: AppProfile.supervisorSlug,
            ownerCode: '20',
            financialTarget: 250000,
            positivationTarget: 200,
            financialActual: 30000,
            positivationActual: 30,
          ),
        ]),
        viewerProfileSlug: AppProfile.coordinatorSlug,
        referenceDate: DateTime(2026, 8, 24),
      );

      expect(summary, isNotNull);
      expect(summary!.financialNeed, closeTo(141666.6667, 0.001));
      expect(summary.positivationNeed, 100);
    },
  );

  test('reports overlapping commitment periods instead of choosing one', () {
    final summary = HomeCommitmentDailySummary.fromOverview(
      overview: CommitmentOverview(
        viewerProfileSlug: AppProfile.supervisorSlug,
        selectedStartDate: DateTime(2026, 8, 24),
        selectedEndDate: DateTime(2026, 8, 31),
        selectedScopeProfileSlug: null,
        selectedScopeOwnerCode: null,
        availablePeriods: <CommitmentPeriod>[
          CommitmentPeriod(
            startDate: DateTime(2026, 8, 24),
            endDate: DateTime(2026, 8, 31),
          ),
          CommitmentPeriod(
            startDate: DateTime(2026, 8, 20),
            endDate: DateTime(2026, 8, 28),
          ),
        ],
        availableScopes: const <CommitmentScope>[],
        items: <CommitmentItem>[
          _item(
            profileSlug: AppProfile.supervisorSlug,
            ownerCode: '20',
            financialTarget: 250000,
            positivationTarget: 200,
            financialActual: 4628.02,
            positivationActual: 9,
          ),
        ],
        lastUpdatedAt: null,
      ),
      viewerProfileSlug: AppProfile.supervisorSlug,
      referenceDate: DateTime(2026, 8, 24),
    );

    expect(summary, isNotNull);
    expect(summary!.hasPeriodConflict, isTrue);
    expect(summary.conflictingPeriodCount, 2);
    expect(summary.financialNeed, isNull);
    expect(summary.positivationNeed, isNull);
  });

  test('does not expose an old commitment as a daily home target', () {
    final summary = HomeCommitmentDailySummary.fromOverview(
      overview: _overview(<CommitmentItem>[
        _item(
          profileSlug: AppProfile.supervisorSlug,
          ownerCode: '20',
          financialTarget: 250000,
          positivationTarget: 200,
          financialActual: 250000,
          positivationActual: 200,
        ),
      ]),
      viewerProfileSlug: AppProfile.supervisorSlug,
      referenceDate: DateTime(2026, 9, 1),
    );

    expect(summary, isNull);
  });
}

CommitmentOverview _overview(List<CommitmentItem> items) {
  return CommitmentOverview(
    viewerProfileSlug: '',
    selectedStartDate: DateTime(2026, 8, 24),
    selectedEndDate: DateTime(2026, 8, 31),
    selectedScopeProfileSlug: null,
    selectedScopeOwnerCode: null,
    availablePeriods: const <CommitmentPeriod>[],
    availableScopes: const <CommitmentScope>[],
    items: items,
    lastUpdatedAt: null,
  );
}

CommitmentItem _item({
  required String profileSlug,
  required String ownerCode,
  required double financialTarget,
  required double positivationTarget,
  required double financialActual,
  required int positivationActual,
}) {
  return CommitmentItem(
    profileSlug: profileSlug,
    ownerCode: ownerCode,
    displayName: ownerCode,
    financialTarget: financialTarget,
    positivationTarget: positivationTarget,
    financialActual: financialActual,
    positivationActual: positivationActual,
    financialClosedActual: 0,
    positivationClosedActual: 0,
    lastUpdatedAt: null,
  );
}
