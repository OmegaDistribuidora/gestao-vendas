import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_vendas/utils/business_day_projection.dart';

void main() {
  test(
    'ignores weekends and Ceara state holidays when counting business days',
    () {
      final context = BusinessDayProjection.buildMonthContext(
        DateTime(2026, 3, 1),
        referenceDate: DateTime(2026, 3, 31),
      );

      expect(context.totalBusinessDays, 20);
      expect(context.elapsedBusinessDays, 20);
    },
  );

  test('counts elapsed business days only up to the reference date', () {
    final context = BusinessDayProjection.buildMonthContext(
      DateTime(2026, 3, 1),
      referenceDate: DateTime(2026, 3, 20),
    );

    expect(context.totalBusinessDays, 20);
    expect(context.elapsedBusinessDays, 14);
  });

  test('projects value based on elapsed business days', () {
    final summary = BusinessDayProjection.summarize(
      actualValue: 1400,
      targetValue: 2000,
      monthStart: DateTime(2026, 3, 1),
      referenceDate: DateTime(2026, 3, 20),
    );

    expect(summary.monthContext.elapsedBusinessDays, 14);
    expect(summary.monthContext.totalBusinessDays, 20);
    expect(summary.averagePerBusinessDay, closeTo(100, 0.001));
    expect(summary.projectedValue, closeTo(2000, 0.001));
    expect(summary.actualProgressPct, closeTo(70, 0.001));
    expect(summary.projectedProgressPct, closeTo(100, 0.001));
    expect(summary.paceStatus, ProjectionPaceStatus.onTrack);
  });

  test(
    'calculates required daily value including the current business day',
    () {
      final summary = BusinessDayProjection.summarize(
        actualValue: 1400,
        targetValue: 2100,
        monthStart: DateTime(2026, 3, 1),
        referenceDate: DateTime(2026, 3, 20),
      );

      expect(summary.monthContext.remainingBusinessDays, 7);
      expect(summary.requiredPerBusinessDay, closeTo(100, 0.001));
    },
  );

  test('does not include reference date when it is not a business day', () {
    final summary = BusinessDayProjection.summarize(
      actualValue: 1400,
      targetValue: 2000,
      monthStart: DateTime(2026, 3, 1),
      referenceDate: DateTime(2026, 3, 21),
    );

    expect(summary.monthContext.remainingBusinessDays, 6);
    expect(summary.requiredPerBusinessDay, closeTo(100, 0.001));
  });

  test('returns zero required daily value when target is already reached', () {
    final summary = BusinessDayProjection.summarize(
      actualValue: 2200,
      targetValue: 2000,
      monthStart: DateTime(2026, 3, 1),
      referenceDate: DateTime(2026, 3, 20),
    );

    expect(summary.requiredPerBusinessDay, 0);
  });

  test('projects a commitment inside its own business-day period', () {
    final summary = BusinessDayProjection.summarizePeriod(
      actualValue: 150,
      projectionActualValue: 100,
      targetValue: 300,
      startDate: DateTime(2026, 8, 17),
      endDate: DateTime(2026, 8, 21),
      referenceDate: DateTime(2026, 8, 19),
    );

    expect(summary.periodContext.totalBusinessDays, 5);
    expect(summary.periodContext.elapsedBusinessDays, 3);
    expect(summary.periodContext.completedBusinessDays, 2);
    expect(summary.periodContext.remainingBusinessDays, 3);
    expect(summary.averagePerBusinessDay, 50);
    expect(summary.projectedValue, 250);
    expect(summary.requiredPerBusinessDay, closeTo(66.6667, 0.001));
    expect(summary.paceStatus, ProjectionPaceStatus.belowTarget);
  });

  test('does not create a projection before the commitment starts', () {
    final summary = BusinessDayProjection.summarizePeriod(
      actualValue: 0,
      projectionActualValue: 0,
      targetValue: 300,
      startDate: DateTime(2026, 8, 17),
      endDate: DateTime(2026, 8, 21),
      referenceDate: DateTime(2026, 8, 16),
    );

    expect(summary.periodContext.elapsedBusinessDays, 0);
    expect(summary.periodContext.completedBusinessDays, 0);
    expect(summary.periodContext.remainingBusinessDays, 5);
    expect(summary.projectedValue, 0);
    expect(summary.requiredPerBusinessDay, 60);
  });

  test('uses only closed days for trend on the final commitment day', () {
    final summary = BusinessDayProjection.summarizePeriod(
      actualValue: 227,
      projectionActualValue: 180,
      targetValue: 250,
      startDate: DateTime(2026, 8, 17),
      endDate: DateTime(2026, 8, 21),
      referenceDate: DateTime(2026, 8, 21),
    );

    expect(summary.periodContext.completedBusinessDays, 4);
    expect(summary.periodContext.remainingBusinessDays, 1);
    expect(summary.averagePerBusinessDay, 45);
    expect(summary.projectedValue, 225);
    expect(summary.requiredPerBusinessDay, 70);
    expect(summary.paceStatus, ProjectionPaceStatus.belowTarget);
  });

  test('projects a commitment live before the first day closes', () {
    final summary = BusinessDayProjection.summarizePeriod(
      actualValue: 40,
      projectionActualValue: 0,
      targetValue: 250,
      startDate: DateTime(2026, 8, 17),
      endDate: DateTime(2026, 8, 21),
      referenceDate: DateTime(2026, 8, 17),
    );

    expect(summary.periodContext.completedBusinessDays, 0);
    expect(summary.periodContext.projectionBusinessDays, 1);
    expect(summary.projectionActualValue, 40);
    expect(summary.averagePerBusinessDay, 40);
    expect(summary.projectedValue, 200);
    expect(summary.requiredPerBusinessDay, 50);
    expect(summary.paceStatus, ProjectionPaceStatus.belowTarget);
  });

  test('recalculates the live first-day trend for the current commitment', () {
    final summary = BusinessDayProjection.summarizePeriod(
      actualValue: 4628.02,
      projectionActualValue: 0,
      targetValue: 250000,
      startDate: DateTime(2026, 8, 24),
      endDate: DateTime(2026, 8, 31),
      referenceDate: DateTime(2026, 8, 24),
    );

    expect(summary.periodContext.totalBusinessDays, 6);
    expect(summary.periodContext.completedBusinessDays, 0);
    expect(summary.averagePerBusinessDay, closeTo(4628.02, 0.001));
    expect(summary.projectedValue, closeTo(27768.12, 0.001));
    expect(summary.requiredPerBusinessDay, closeTo(41666.6667, 0.001));
  });

  test('uses only the first closed day in second-day commitment need', () {
    final summary = BusinessDayProjection.summarizePeriod(
      actualValue: 30000,
      projectionActualValue: 25000,
      targetValue: 250000,
      startDate: DateTime(2026, 8, 24),
      endDate: DateTime(2026, 8, 31),
      referenceDate: DateTime(2026, 8, 25),
    );

    expect(summary.periodContext.totalBusinessDays, 6);
    expect(summary.periodContext.completedBusinessDays, 1);
    expect(summary.periodContext.remainingBusinessDays, 5);
    expect(summary.requiredPerBusinessDay, closeTo(45000, 0.001));
  });

  test('uses only closed days in third-day commitment need', () {
    final summary = BusinessDayProjection.summarizePeriod(
      actualValue: 70000,
      projectionActualValue: 55000,
      targetValue: 250000,
      startDate: DateTime(2026, 8, 24),
      endDate: DateTime(2026, 8, 31),
      referenceDate: DateTime(2026, 8, 26),
    );

    expect(summary.periodContext.totalBusinessDays, 6);
    expect(summary.periodContext.completedBusinessDays, 2);
    expect(summary.periodContext.remainingBusinessDays, 4);
    expect(summary.requiredPerBusinessDay, closeTo(48750, 0.001));
  });

  test('keeps first-day commitment need fixed despite live sales', () {
    final summary = BusinessDayProjection.summarizePeriod(
      actualValue: 13590.23,
      projectionActualValue: 0,
      targetValue: 355000,
      startDate: DateTime(2026, 8, 24),
      endDate: DateTime(2026, 8, 31),
      referenceDate: DateTime(2026, 8, 24),
    );

    expect(summary.periodContext.totalBusinessDays, 6);
    expect(summary.periodContext.completedBusinessDays, 0);
    expect(summary.requiredPerBusinessDay, closeTo(59166.6667, 0.001));
  });
}
