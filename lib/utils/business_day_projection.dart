class BusinessDayMonthContext {
  const BusinessDayMonthContext({
    required this.monthStart,
    required this.totalBusinessDays,
    required this.elapsedBusinessDays,
  });

  final DateTime monthStart;
  final int totalBusinessDays;
  final int elapsedBusinessDays;

  bool get hasElapsedBusinessDays => elapsedBusinessDays > 0;
}

enum ProjectionPaceStatus { onTrack, belowTarget, noTarget }

class BusinessDayProjectionSummary {
  const BusinessDayProjectionSummary({
    required this.monthContext,
    required this.actualValue,
    required this.targetValue,
    required this.projectedValue,
    required this.averagePerBusinessDay,
    required this.actualProgressPct,
    required this.projectedProgressPct,
    required this.paceStatus,
  });

  final BusinessDayMonthContext monthContext;
  final double actualValue;
  final double? targetValue;
  final double projectedValue;
  final double averagePerBusinessDay;
  final double? actualProgressPct;
  final double? projectedProgressPct;
  final ProjectionPaceStatus paceStatus;
}

class BusinessDayProjection {
  static const List<(int, int)> _nationalHolidays = <(int, int)>[
    (1, 1),
    (4, 21),
    (5, 1),
    (9, 7),
    (10, 12),
    (11, 2),
    (11, 15),
    (11, 20),
    (12, 25),
  ];

  static const List<(int, int)> _cearaStateHolidays = <(int, int)>[
    (3, 19),
    (3, 25),
  ];

  static BusinessDayMonthContext buildMonthContext(
    DateTime monthStart, {
    DateTime? referenceDate,
  }) {
    final normalizedMonthStart = DateTime(monthStart.year, monthStart.month, 1);
    final normalizedReferenceDate = _normalizeDate(
      referenceDate ?? DateTime.now(),
    );
    final lastDayOfMonth = DateTime(
      normalizedMonthStart.year,
      normalizedMonthStart.month + 1,
      0,
    );

    final totalBusinessDays = _countBusinessDays(
      start: normalizedMonthStart,
      end: lastDayOfMonth,
    );

    final elapsedBusinessDays = switch (_compareMonths(
      normalizedMonthStart,
      normalizedReferenceDate,
    )) {
      -1 => totalBusinessDays,
      0 => _countBusinessDays(
        start: normalizedMonthStart,
        end: normalizedReferenceDate.isBefore(lastDayOfMonth)
            ? normalizedReferenceDate
            : lastDayOfMonth,
      ),
      _ => 0,
    };

    return BusinessDayMonthContext(
      monthStart: normalizedMonthStart,
      totalBusinessDays: totalBusinessDays,
      elapsedBusinessDays: elapsedBusinessDays,
    );
  }

  static BusinessDayProjectionSummary summarize({
    required double actualValue,
    required double? targetValue,
    required DateTime monthStart,
    DateTime? referenceDate,
  }) {
    final monthContext = buildMonthContext(
      monthStart,
      referenceDate: referenceDate,
    );

    final double averagePerBusinessDay = monthContext.hasElapsedBusinessDays
        ? actualValue / monthContext.elapsedBusinessDays
        : 0.0;
    final double projectedValue = monthContext.hasElapsedBusinessDays
        ? averagePerBusinessDay * monthContext.totalBusinessDays
        : actualValue;
    final actualProgressPct = _progressPct(actualValue, targetValue);
    final projectedProgressPct = _progressPct(projectedValue, targetValue);
    final paceStatus = switch (targetValue) {
      null => ProjectionPaceStatus.noTarget,
      <= 0 => ProjectionPaceStatus.noTarget,
      _ when projectedValue >= targetValue => ProjectionPaceStatus.onTrack,
      _ => ProjectionPaceStatus.belowTarget,
    };

    return BusinessDayProjectionSummary(
      monthContext: monthContext,
      actualValue: actualValue,
      targetValue: targetValue,
      projectedValue: projectedValue,
      averagePerBusinessDay: averagePerBusinessDay,
      actualProgressPct: actualProgressPct,
      projectedProgressPct: projectedProgressPct,
      paceStatus: paceStatus,
    );
  }

  static bool isBusinessDay(DateTime date) {
    final normalizedDate = _normalizeDate(date);
    if (normalizedDate.weekday == DateTime.saturday ||
        normalizedDate.weekday == DateTime.sunday) {
      return false;
    }

    final holidays = _holidaysForYear(normalizedDate.year);
    return !holidays.contains(normalizedDate);
  }

  static int _countBusinessDays({
    required DateTime start,
    required DateTime end,
  }) {
    if (end.isBefore(start)) {
      return 0;
    }

    var cursor = _normalizeDate(start);
    final normalizedEnd = _normalizeDate(end);
    var count = 0;

    while (!cursor.isAfter(normalizedEnd)) {
      if (isBusinessDay(cursor)) {
        count += 1;
      }
      cursor = cursor.add(const Duration(days: 1));
    }

    return count;
  }

  static Set<DateTime> _holidaysForYear(int year) {
    final dates = <DateTime>{};
    for (final (month, day) in _nationalHolidays) {
      dates.add(DateTime(year, month, day));
    }
    for (final (month, day) in _cearaStateHolidays) {
      dates.add(DateTime(year, month, day));
    }
    return dates;
  }

  static double? _progressPct(double value, double? targetValue) {
    if (targetValue == null || targetValue <= 0) {
      return null;
    }
    return (value / targetValue) * 100;
  }

  static int _compareMonths(DateTime monthStart, DateTime referenceDate) {
    if (monthStart.year == referenceDate.year &&
        monthStart.month == referenceDate.month) {
      return 0;
    }
    if (monthStart.isBefore(
      DateTime(referenceDate.year, referenceDate.month, 1),
    )) {
      return -1;
    }
    return 1;
  }

  static DateTime _normalizeDate(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}
