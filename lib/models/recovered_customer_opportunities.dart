import '../utils/text_sanitizer.dart';

class RecoveredCustomerOpportunitiesOverview {
  const RecoveredCustomerOpportunitiesOverview({
    required this.viewerProfileSlug,
    required this.viewerUserCode,
    required this.totalRecovered,
    required this.customers,
    this.lastUpdatedAt,
  });

  final String viewerProfileSlug;
  final String viewerUserCode;
  final int totalRecovered;
  final List<RecoveredCustomerOpportunity> customers;
  final DateTime? lastUpdatedAt;

  factory RecoveredCustomerOpportunitiesOverview.empty() {
    return const RecoveredCustomerOpportunitiesOverview(
      viewerProfileSlug: '',
      viewerUserCode: '',
      totalRecovered: 0,
      customers: <RecoveredCustomerOpportunity>[],
    );
  }

  factory RecoveredCustomerOpportunitiesOverview.fromJson(
    Map<String, dynamic> json,
  ) {
    return RecoveredCustomerOpportunitiesOverview(
      viewerProfileSlug: '${json['viewer_profile_slug'] ?? ''}',
      viewerUserCode: '${json['viewer_user_code'] ?? ''}',
      totalRecovered: _toInt(json['total_recovered']),
      lastUpdatedAt: _parseDateTime(json['last_updated_at']),
      customers: _parseList(
        json['customers'],
        RecoveredCustomerOpportunity.fromJson,
      ),
    );
  }
}

class RecoveredCustomerOpportunity {
  const RecoveredCustomerOpportunity({
    required this.taxId,
    required this.sourceCustomerCode,
    required this.clientName,
    required this.fantasyName,
    required this.activityCode,
    required this.activityName,
    required this.city,
    required this.uf,
    required this.district,
    required this.fullAddress,
    required this.creditLimit,
    required this.marketPotentialOrderCount,
    required this.recoveredAt,
    this.marketPotential,
  });

  final String taxId;
  final String sourceCustomerCode;
  final String clientName;
  final String fantasyName;
  final String activityCode;
  final String activityName;
  final String city;
  final String uf;
  final String district;
  final String fullAddress;
  final double creditLimit;
  final double? marketPotential;
  final int marketPotentialOrderCount;
  final DateTime? recoveredAt;

  String get displayName => fantasyName.isNotEmpty ? fantasyName : clientName;

  String get secondaryName =>
      displayName == clientName ? fantasyName : clientName;

  String get cityLabel => uf.isEmpty ? city : '$city - $uf';

  String get activityLabel {
    if (activityCode.isNotEmpty && activityName.isNotEmpty) {
      return '$activityCode - $activityName';
    }
    return activityName.isNotEmpty ? activityName : activityCode;
  }

  factory RecoveredCustomerOpportunity.fromJson(Map<String, dynamic> json) {
    return RecoveredCustomerOpportunity(
      taxId: '${json['tax_id'] ?? ''}'.trim(),
      sourceCustomerCode: '${json['source_customer_code'] ?? ''}'.trim(),
      clientName: _clean(json['client_name']),
      fantasyName: _clean(json['fantasy_name']),
      activityCode: '${json['activity_code'] ?? ''}'.trim(),
      activityName: _clean(json['activity_name']),
      city: _clean(json['city']),
      uf: '${json['uf'] ?? ''}'.trim().toUpperCase(),
      district: _clean(json['district']),
      fullAddress: _clean(json['full_address']),
      creditLimit: _toDouble(json['credit_limit']),
      marketPotential: _toNullableDouble(json['market_potential']),
      marketPotentialOrderCount: _toInt(json['market_potential_order_count']),
      recoveredAt: _parseDateTime(json['recovered_at']),
    );
  }
}

List<T> _parseList<T>(Object? value, T Function(Map<String, dynamic>) parse) {
  if (value is! List) {
    return <T>[];
  }
  return value
      .whereType<Map>()
      .map((row) => parse(row.map((key, item) => MapEntry('$key', item))))
      .toList();
}

String _clean(Object? value) {
  if (value == null) {
    return '';
  }
  return TextSanitizer.normalize(value is String ? value : '$value').trim();
}

DateTime? _parseDateTime(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}

int _toInt(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse('$value') ?? 0;
}

double _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse('$value') ?? 0;
}

double? _toNullableDouble(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse('$value');
}
