import '../utils/text_sanitizer.dart';
import 'app_profile.dart';

class CommitmentOverview {
  const CommitmentOverview({
    required this.viewerProfileSlug,
    required this.selectedStartDate,
    required this.selectedEndDate,
    required this.selectedScopeProfileSlug,
    required this.selectedScopeOwnerCode,
    required this.availablePeriods,
    required this.availableScopes,
    required this.items,
    required this.lastUpdatedAt,
  });

  final String viewerProfileSlug;
  final DateTime? selectedStartDate;
  final DateTime? selectedEndDate;
  final String? selectedScopeProfileSlug;
  final String? selectedScopeOwnerCode;
  final List<CommitmentPeriod> availablePeriods;
  final List<CommitmentScope> availableScopes;
  final List<CommitmentItem> items;
  final DateTime? lastUpdatedAt;

  factory CommitmentOverview.empty() {
    return const CommitmentOverview(
      viewerProfileSlug: '',
      selectedStartDate: null,
      selectedEndDate: null,
      selectedScopeProfileSlug: null,
      selectedScopeOwnerCode: null,
      availablePeriods: <CommitmentPeriod>[],
      availableScopes: <CommitmentScope>[],
      items: <CommitmentItem>[],
      lastUpdatedAt: null,
    );
  }

  factory CommitmentOverview.fromJson(Map<String, dynamic> json) {
    return CommitmentOverview(
      viewerProfileSlug: '${json['viewer_profile_slug'] ?? ''}'.trim(),
      selectedStartDate: _parseDate(json['selected_start_date']),
      selectedEndDate: _parseDate(json['selected_end_date']),
      selectedScopeProfileSlug: _nullableString(
        json['selected_scope_profile_slug'],
      ),
      selectedScopeOwnerCode: _nullableString(
        json['selected_scope_owner_code'],
      ),
      availablePeriods: _parseList(
        json['available_periods'],
        CommitmentPeriod.fromJson,
      ),
      availableScopes: _parseList(
        json['available_scopes'],
        CommitmentScope.fromJson,
      ),
      items: _parseList(json['items'], CommitmentItem.fromJson),
      lastUpdatedAt: _parseDateTime(json['last_updated_at']),
    );
  }

  static List<T> _parseList<T>(
    Object? value,
    T Function(Map<String, dynamic>) parser,
  ) {
    if (value is! List) {
      return <T>[];
    }
    return value
        .whereType<Map>()
        .map((row) => parser(row.map((key, value) => MapEntry('$key', value))))
        .toList();
  }

  static DateTime? _parseDate(Object? value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(text);
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }

  static DateTime? _parseDateTime(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : DateTime.tryParse(text)?.toLocal();
  }

  static String? _nullableString(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }
}

class CommitmentPeriod {
  const CommitmentPeriod({required this.startDate, required this.endDate});

  final DateTime startDate;
  final DateTime endDate;

  String get value => '${_dateValue(startDate)}|${_dateValue(endDate)}';

  factory CommitmentPeriod.fromJson(Map<String, dynamic> json) {
    return CommitmentPeriod(
      startDate: _requiredDate(json['start_date']),
      endDate: _requiredDate(json['end_date']),
    );
  }

  static DateTime _requiredDate(Object? value) {
    final parsed = DateTime.parse('$value');
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static String _dateValue(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class CommitmentScope {
  const CommitmentScope({
    required this.profileSlug,
    required this.ownerCode,
    required this.displayName,
    required this.label,
  });

  final String profileSlug;
  final String ownerCode;
  final String displayName;
  final String label;

  String get value => '$profileSlug|$ownerCode';

  factory CommitmentScope.fromJson(Map<String, dynamic> json) {
    return CommitmentScope(
      profileSlug: '${json['profile_slug'] ?? ''}'.trim(),
      ownerCode: '${json['owner_code'] ?? ''}'.trim(),
      displayName: TextSanitizer.normalize(
        '${json['display_name'] ?? ''}'.trim(),
      ),
      label: TextSanitizer.normalize('${json['label'] ?? ''}'.trim()),
    );
  }
}

class CommitmentItem {
  static const String companyProfileSlug = 'empresa';

  const CommitmentItem({
    required this.profileSlug,
    required this.ownerCode,
    required this.displayName,
    required this.financialTarget,
    required this.positivationTarget,
    required this.financialActual,
    required this.positivationActual,
    required this.financialClosedActual,
    required this.positivationClosedActual,
    required this.lastUpdatedAt,
    this.routingPlanned,
    this.routingPurchased,
    this.routingPercent,
    this.routingSaleAmount,
    this.routingRequestedDays,
    this.routingAvailableDays,
    this.routingUpdatedAt,
  });

  final String profileSlug;
  final String ownerCode;
  final String displayName;
  final double financialTarget;
  final double positivationTarget;
  final double financialActual;
  final int positivationActual;
  final double financialClosedActual;
  final int positivationClosedActual;
  final DateTime? lastUpdatedAt;
  final int? routingPlanned;
  final int? routingPurchased;
  final double? routingPercent;
  final double? routingSaleAmount;
  final int? routingRequestedDays;
  final int? routingAvailableDays;
  final DateTime? routingUpdatedAt;

  bool get hasRouting => (routingPlanned ?? 0) > 0;

  static CommitmentItem? companyTotalFrom(Iterable<CommitmentItem> items) {
    final coordinators = items
        .where((item) => item.profileSlug == AppProfile.coordinatorSlug)
        .toList();
    if (coordinators.isEmpty) {
      return null;
    }

    DateTime? mostRecentUpdate;
    DateTime? mostRecentRoutingUpdate;
    var hasRouting = false;
    for (final item in coordinators) {
      final updatedAt = item.lastUpdatedAt;
      if (updatedAt != null &&
          (mostRecentUpdate == null || updatedAt.isAfter(mostRecentUpdate))) {
        mostRecentUpdate = updatedAt;
      }
      final routingUpdatedAt = item.routingUpdatedAt;
      if (routingUpdatedAt != null &&
          (mostRecentRoutingUpdate == null ||
              routingUpdatedAt.isAfter(mostRecentRoutingUpdate))) {
        mostRecentRoutingUpdate = routingUpdatedAt;
      }
      hasRouting = hasRouting || item.hasRouting;
    }

    final routingPlanned = hasRouting
        ? coordinators.fold<int>(
            0,
            (total, item) => total + (item.routingPlanned ?? 0),
          )
        : null;
    final routingPurchased = hasRouting
        ? coordinators.fold<int>(
            0,
            (total, item) => total + (item.routingPurchased ?? 0),
          )
        : null;

    return CommitmentItem(
      profileSlug: companyProfileSlug,
      ownerCode: '',
      displayName: 'Ômega Distribuidora',
      financialTarget: coordinators.fold(
        0,
        (total, item) => total + item.financialTarget,
      ),
      positivationTarget: coordinators.fold(
        0,
        (total, item) => total + item.positivationTarget,
      ),
      financialActual: coordinators.fold(
        0,
        (total, item) => total + item.financialActual,
      ),
      positivationActual: coordinators.fold(
        0,
        (total, item) => total + item.positivationActual,
      ),
      financialClosedActual: coordinators.fold(
        0,
        (total, item) => total + item.financialClosedActual,
      ),
      positivationClosedActual: coordinators.fold(
        0,
        (total, item) => total + item.positivationClosedActual,
      ),
      lastUpdatedAt: mostRecentUpdate,
      routingPlanned: routingPlanned,
      routingPurchased: routingPurchased,
      routingPercent: routingPlanned == null || routingPlanned == 0
          ? null
          : routingPurchased! * 100 / routingPlanned,
      routingSaleAmount: hasRouting
          ? coordinators.fold<double>(
              0,
              (total, item) => total + (item.routingSaleAmount ?? 0),
            )
          : null,
      routingRequestedDays: hasRouting
          ? coordinators
                .map((item) => item.routingRequestedDays ?? 0)
                .fold<int>(
                  0,
                  (largest, value) => value > largest ? value : largest,
                )
          : null,
      routingAvailableDays: hasRouting
          ? coordinators
                .map((item) => item.routingAvailableDays ?? 0)
                .fold<int>(
                  0,
                  (largest, value) => value > largest ? value : largest,
                )
          : null,
      routingUpdatedAt: mostRecentRoutingUpdate,
    );
  }

  factory CommitmentItem.fromJson(Map<String, dynamic> json) {
    return CommitmentItem(
      profileSlug: '${json['profile_slug'] ?? ''}'.trim(),
      ownerCode: '${json['owner_code'] ?? ''}'.trim(),
      displayName: TextSanitizer.normalize(
        '${json['display_name'] ?? ''}'.trim(),
      ),
      financialTarget: (json['financial_target'] as num?)?.toDouble() ?? 0,
      positivationTarget:
          (json['positivation_target'] as num?)?.toDouble() ?? 0,
      financialActual: (json['financial_actual'] as num?)?.toDouble() ?? 0,
      positivationActual: (json['positivation_actual'] as num?)?.toInt() ?? 0,
      financialClosedActual:
          (json['financial_closed_actual'] as num?)?.toDouble() ??
          (json['financial_actual'] as num?)?.toDouble() ??
          0,
      positivationClosedActual:
          (json['positivation_closed_actual'] as num?)?.toInt() ??
          (json['positivation_actual'] as num?)?.toInt() ??
          0,
      lastUpdatedAt: _parseDateTime(json['last_updated_at']),
      routingPlanned: _nullableInt(json['routing_planned']),
      routingPurchased: _nullableInt(json['routing_purchased']),
      routingPercent: _nullableDouble(json['routing_percent']),
      routingSaleAmount: _nullableDouble(json['routing_sale_amount']),
      routingRequestedDays: _nullableInt(json['routing_requested_days']),
      routingAvailableDays: _nullableInt(json['routing_available_days']),
      routingUpdatedAt: _parseDateTime(json['routing_updated_at']),
    );
  }

  static DateTime? _parseDateTime(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : DateTime.tryParse(text)?.toLocal();
  }

  static int? _nullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    return value is num ? value.toInt() : int.tryParse('$value');
  }

  static double? _nullableDouble(Object? value) {
    if (value == null) {
      return null;
    }
    return value is num ? value.toDouble() : double.tryParse('$value');
  }
}
