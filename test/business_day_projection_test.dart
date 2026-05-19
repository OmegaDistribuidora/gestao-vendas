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
}
