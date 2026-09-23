class RoutingAnalysis {
  const RoutingAnalysis({
    required this.available,
    required this.applicable,
    required this.referenceDate,
    required this.startDate,
    required this.endDate,
    required this.requestedDays,
    required this.availableDays,
    required this.missingDates,
    required this.effectiveProfileSlug,
    required this.effectiveOwnerCode,
    required this.effectiveDisplayName,
    required this.availableScopes,
    required this.planned,
    required this.purchased,
    required this.saleAmount,
    required this.mapAvailable,
    required this.sellerSummaries,
    required this.items,
    this.percent,
    this.snapshotId,
    this.updatedAt,
    this.routingUpdatedAt,
    this.selectedScopeProfileSlug,
    this.selectedScopeOwnerCode,
  });

  final bool available;
  final bool applicable;
  final DateTime referenceDate;
  final DateTime startDate;
  final DateTime endDate;
  final int requestedDays;
  final int availableDays;
  final List<DateTime> missingDates;
  final String effectiveProfileSlug;
  final String effectiveOwnerCode;
  final String effectiveDisplayName;
  final List<RoutingScopeOption> availableScopes;
  final int planned;
  final int purchased;
  final double saleAmount;
  final double? percent;
  final bool mapAvailable;
  final List<RoutingSellerSummary> sellerSummaries;
  final List<RoutingCustomer> items;
  final String? snapshotId;
  final DateTime? updatedAt;
  final DateTime? routingUpdatedAt;
  final String? selectedScopeProfileSlug;
  final String? selectedScopeOwnerCode;

  int get pending => planned - purchased;
  bool get isSellerView => effectiveProfileSlug == 'vendedor';
  bool get isPeriod => startDate != endDate;
  bool get hasIncompletePeriod => availableDays < requestedDays;

  factory RoutingAnalysis.fromJson(Map<String, dynamic> json) {
    final parsedDate = DateTime.tryParse('${json['reference_date'] ?? ''}');
    final parsedStartDate = DateTime.tryParse('${json['start_date'] ?? ''}');
    final parsedEndDate = DateTime.tryParse('${json['end_date'] ?? ''}');
    final fallbackDate = parsedDate ?? DateTime.now();
    return RoutingAnalysis(
      available: json['available'] == true,
      applicable: json['applicable'] != false,
      referenceDate: fallbackDate,
      startDate: parsedStartDate ?? fallbackDate,
      endDate: parsedEndDate ?? parsedStartDate ?? fallbackDate,
      requestedDays: _integer(json['requested_days']) > 0
          ? _integer(json['requested_days'])
          : 1,
      availableDays: json.containsKey('available_days')
          ? _integer(json['available_days'])
          : (json['available'] == true ? 1 : 0),
      missingDates: _dates(json['missing_dates']),
      effectiveProfileSlug: '${json['effective_profile_slug'] ?? ''}',
      effectiveOwnerCode: '${json['effective_owner_code'] ?? ''}',
      effectiveDisplayName: '${json['effective_display_name'] ?? ''}',
      availableScopes: _maps(
        json['available_scopes'],
      ).map(RoutingScopeOption.fromJson).toList(),
      planned: _integer(json['planned']),
      purchased: _integer(json['purchased']),
      saleAmount: _decimal(json['sale_amount']),
      percent: _nullableDecimal(json['percent']),
      mapAvailable: json['map_available'] == true,
      sellerSummaries: _maps(
        json['seller_summaries'],
      ).map(RoutingSellerSummary.fromJson).toList(),
      items: _maps(json['items']).map(RoutingCustomer.fromJson).toList(),
      snapshotId: _nullableText(json['snapshot_id']),
      updatedAt: DateTime.tryParse('${json['source_updated_at'] ?? ''}'),
      routingUpdatedAt: DateTime.tryParse(
        '${json['routing_updated_at'] ?? ''}',
      ),
      selectedScopeProfileSlug: _nullableText(
        json['selected_scope_profile_slug'],
      ),
      selectedScopeOwnerCode: _nullableText(json['selected_scope_owner_code']),
    );
  }
}

class RoutingScopeOption {
  const RoutingScopeOption({
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
  bool get isSeller => profileSlug == 'vendedor';

  factory RoutingScopeOption.fromJson(Map<String, dynamic> json) =>
      RoutingScopeOption(
        profileSlug: '${json['profile_slug'] ?? ''}',
        ownerCode: '${json['owner_code'] ?? ''}',
        displayName: '${json['display_name'] ?? ''}',
        label: '${json['label'] ?? ''}',
      );
}

class RoutingSellerSummary {
  const RoutingSellerSummary({
    required this.sellerCode,
    required this.sellerName,
    required this.supervisorCode,
    required this.coordinatorCode,
    required this.planned,
    required this.purchased,
    required this.saleAmount,
    this.percent,
  });

  final String sellerCode;
  final String sellerName;
  final String supervisorCode;
  final String coordinatorCode;
  final int planned;
  final int purchased;
  final double saleAmount;
  final double? percent;

  int get pending => planned - purchased;

  factory RoutingSellerSummary.fromJson(Map<String, dynamic> json) =>
      RoutingSellerSummary(
        sellerCode: '${json['seller_code'] ?? ''}',
        sellerName: '${json['seller_name'] ?? ''}',
        supervisorCode: '${json['supervisor_code'] ?? ''}',
        coordinatorCode: '${json['coordinator_code'] ?? ''}',
        planned: _integer(json['planned']),
        purchased: _integer(json['purchased']),
        saleAmount: _decimal(json['sale_amount']),
        percent: _nullableDecimal(json['percent']),
      );
}

class RoutingCustomer {
  const RoutingCustomer({
    required this.code,
    required this.name,
    required this.sellerCode,
    required this.sellerName,
    required this.address,
    required this.neighborhood,
    required this.city,
    required this.purchased,
    required this.saleAmount,
    required this.orderCount,
    required this.routeCode,
    required this.routeSequence,
    this.referenceDate,
    this.latitude,
    this.longitude,
  });

  final String code;
  final String name;
  final String sellerCode;
  final String sellerName;
  final String address;
  final String neighborhood;
  final String city;
  final bool purchased;
  final double saleAmount;
  final int orderCount;
  final String routeCode;
  final int routeSequence;
  final DateTime? referenceDate;
  final double? latitude;
  final double? longitude;

  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      latitude != 0 &&
      longitude != 0 &&
      latitude! >= -90 &&
      latitude! <= 90 &&
      longitude! >= -180 &&
      longitude! <= 180;

  String get addressLine {
    return <String>[
      address,
      neighborhood,
      city,
    ].where((part) => part.trim().isNotEmpty).join(' • ');
  }

  factory RoutingCustomer.fromJson(Map<String, dynamic> json) =>
      RoutingCustomer(
        code: '${json['customer_code'] ?? ''}',
        name: '${json['customer_name'] ?? ''}',
        sellerCode: '${json['seller_code'] ?? ''}',
        sellerName: '${json['seller_name'] ?? ''}',
        address: '${json['address'] ?? ''}',
        neighborhood: '${json['neighborhood'] ?? ''}',
        city: '${json['city'] ?? ''}',
        purchased: json['purchased'] == true,
        saleAmount: _decimal(json['sale_amount']),
        orderCount: _integer(json['order_count']),
        routeCode: '${json['route_code'] ?? ''}',
        routeSequence: _integer(json['route_sequence']),
        referenceDate: DateTime.tryParse('${json['reference_date'] ?? ''}'),
        latitude: _nullableDecimal(json['latitude']),
        longitude: _nullableDecimal(json['longitude']),
      );
}

List<DateTime> _dates(Object? value) {
  if (value is! List) {
    return const <DateTime>[];
  }
  return value
      .map((item) => DateTime.tryParse('$item'))
      .whereType<DateTime>()
      .toList(growable: false);
}

List<Map<String, dynamic>> _maps(Object? value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}

String? _nullableText(Object? value) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty ? null : text;
}

int _integer(Object? value) =>
    value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

double _decimal(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse('${value ?? ''}'.replaceAll(',', '.')) ?? 0;

double? _nullableDecimal(Object? value) {
  if (value == null) {
    return null;
  }
  return value is num
      ? value.toDouble()
      : double.tryParse('$value'.replaceAll(',', '.'));
}
