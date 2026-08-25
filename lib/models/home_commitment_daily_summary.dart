import 'app_profile.dart';
import 'commitment_overview.dart';
import '../utils/business_day_projection.dart';

class HomeCommitmentDailySummary {
  const HomeCommitmentDailySummary({
    required this.financialNeed,
    required this.positivationNeed,
    this.conflictingPeriodCount = 0,
  });

  final double? financialNeed;
  final double? positivationNeed;
  final int conflictingPeriodCount;

  bool get hasFinancialNeed => financialNeed != null;
  bool get hasPositivationNeed => positivationNeed != null;
  bool get hasPeriodConflict => conflictingPeriodCount > 1;

  static HomeCommitmentDailySummary? fromOverview({
    required CommitmentOverview overview,
    required String viewerProfileSlug,
    required DateTime referenceDate,
  }) {
    final startDate = overview.selectedStartDate;
    final endDate = overview.selectedEndDate;
    if (startDate == null || endDate == null) {
      return null;
    }

    final today = DateTime(
      referenceDate.year,
      referenceDate.month,
      referenceDate.day,
    );

    final activePeriodValues = overview.availablePeriods
        .where(
          (period) => _includesDate(
            startDate: period.startDate,
            endDate: period.endDate,
            date: today,
          ),
        )
        .map((period) => period.value)
        .toSet();
    if (_includesDate(startDate: startDate, endDate: endDate, date: today)) {
      activePeriodValues.add(
        CommitmentPeriod(startDate: startDate, endDate: endDate).value,
      );
    }
    if (activePeriodValues.length > 1) {
      return HomeCommitmentDailySummary(
        financialNeed: null,
        positivationNeed: null,
        conflictingPeriodCount: activePeriodValues.length,
      );
    }

    if (today.isBefore(startDate) || today.isAfter(endDate)) {
      return null;
    }

    final visibleItems = _itemsForHome(
      overview.items,
      viewerProfileSlug: viewerProfileSlug,
    );
    if (visibleItems.isEmpty) {
      return null;
    }

    final financialTarget = visibleItems.fold<double>(
      0,
      (total, item) => total + item.financialTarget,
    );
    final positivationTarget = visibleItems.fold<double>(
      0,
      (total, item) => total + item.positivationTarget,
    );
    final financialActual = visibleItems.fold<double>(
      0,
      (total, item) => total + item.financialActual,
    );
    final positivationActual = visibleItems.fold<double>(
      0,
      (total, item) => total + item.positivationActual,
    );

    final financialProjection = BusinessDayProjection.summarizePeriod(
      actualValue: financialActual,
      targetValue: financialTarget > 0 ? financialTarget : null,
      startDate: startDate,
      endDate: endDate,
      referenceDate: today,
    );
    final positivationProjection = BusinessDayProjection.summarizePeriod(
      actualValue: positivationActual,
      targetValue: positivationTarget > 0 ? positivationTarget : null,
      startDate: startDate,
      endDate: endDate,
      referenceDate: today,
    );

    return HomeCommitmentDailySummary(
      financialNeed: financialProjection.requiredPerBusinessDay,
      positivationNeed: positivationProjection.requiredPerBusinessDay,
    );
  }

  static List<CommitmentItem> _itemsForHome(
    List<CommitmentItem> items, {
    required String viewerProfileSlug,
  }) {
    if (viewerProfileSlug == AppProfile.supervisorSlug) {
      final supervisors = items
          .where((item) => item.profileSlug == AppProfile.supervisorSlug)
          .toList();
      return supervisors.isNotEmpty ? supervisors : items;
    }

    if (viewerProfileSlug == AppProfile.coordinatorSlug) {
      final coordinators = items
          .where((item) => item.profileSlug == AppProfile.coordinatorSlug)
          .toList();
      return coordinators.isNotEmpty ? coordinators : items;
    }

    if (viewerProfileSlug != AppProfile.boardSlug &&
        viewerProfileSlug != AppProfile.othersSlug) {
      return items;
    }

    final coordinators = items
        .where((item) => item.profileSlug == AppProfile.coordinatorSlug)
        .toList();
    if (coordinators.isNotEmpty) {
      return coordinators;
    }

    return items
        .where((item) => item.profileSlug == AppProfile.supervisorSlug)
        .toList();
  }

  static bool _includesDate({
    required DateTime startDate,
    required DateTime endDate,
    required DateTime date,
  }) {
    return !date.isBefore(startDate) && !date.isAfter(endDate);
  }
}
