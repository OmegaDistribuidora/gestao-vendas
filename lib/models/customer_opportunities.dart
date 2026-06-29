import '../utils/text_sanitizer.dart';

class CustomerOpportunitiesOverview {
  const CustomerOpportunitiesOverview({
    required this.viewerProfileSlug,
    required this.viewerUserCode,
    required this.selectedNeighborhoodKey,
    required this.selectedActivityKey,
    required this.availableSupervisors,
    required this.availableSellers,
    required this.servedNeighborhoods,
    required this.availableActivities,
    required this.totalOpportunities,
    required this.opportunities,
    required this.selectionRequired,
    required this.accessDeniedReason,
    this.selectedSupervisorCode,
    this.selectedSellerCode,
    this.lastUpdatedAt,
  });

  final String viewerProfileSlug;
  final String viewerUserCode;
  final String? selectedSupervisorCode;
  final String? selectedSellerCode;
  final String selectedNeighborhoodKey;
  final String selectedActivityKey;
  final DateTime? lastUpdatedAt;
  final List<CustomerOpportunityScopeOption> availableSupervisors;
  final List<CustomerOpportunityScopeOption> availableSellers;
  final List<CustomerOpportunityNeighborhood> servedNeighborhoods;
  final List<CustomerOpportunityActivity> availableActivities;
  final int totalOpportunities;
  final List<CustomerOpportunity> opportunities;
  final String selectionRequired;
  final String accessDeniedReason;

  bool get requiresSupervisor => selectionRequired == 'supervisor';
  bool get requiresSeller => selectionRequired == 'seller';
  bool get accessDenied => accessDeniedReason.isNotEmpty;

  factory CustomerOpportunitiesOverview.empty() {
    return const CustomerOpportunitiesOverview(
      viewerProfileSlug: '',
      viewerUserCode: '',
      selectedNeighborhoodKey: '',
      selectedActivityKey: '',
      availableSupervisors: <CustomerOpportunityScopeOption>[],
      availableSellers: <CustomerOpportunityScopeOption>[],
      servedNeighborhoods: <CustomerOpportunityNeighborhood>[],
      availableActivities: <CustomerOpportunityActivity>[],
      totalOpportunities: 0,
      opportunities: <CustomerOpportunity>[],
      selectionRequired: '',
      accessDeniedReason: '',
    );
  }

  factory CustomerOpportunitiesOverview.fromJson(Map<String, dynamic> json) {
    final rawOpportunities = json['opportunities'];
    return CustomerOpportunitiesOverview(
      viewerProfileSlug: '${json['viewer_profile_slug'] ?? ''}',
      viewerUserCode: '${json['viewer_user_code'] ?? ''}',
      selectedSupervisorCode: _nullableText(json['selected_supervisor_code']),
      selectedSellerCode: _nullableText(json['selected_seller_code']),
      selectedNeighborhoodKey: '${json['selected_neighborhood_key'] ?? ''}',
      selectedActivityKey: '${json['selected_activity_key'] ?? ''}',
      lastUpdatedAt: _parseDateTime(json['last_updated_at']),
      availableSupervisors: _parseList(
        json['available_supervisors'],
        CustomerOpportunityScopeOption.fromJson,
      ),
      availableSellers: _parseList(
        json['available_sellers'],
        CustomerOpportunityScopeOption.fromJson,
      ),
      servedNeighborhoods: _parseList(
        json['served_neighborhoods'],
        CustomerOpportunityNeighborhood.fromJson,
      ),
      availableActivities: _parseList(
        json['available_activities'],
        CustomerOpportunityActivity.fromJson,
      ),
      totalOpportunities: _toInt(json['total_opportunities']),
      opportunities: rawOpportunities is List
          ? rawOpportunities
                .map(CustomerOpportunity.fromMarkerJson)
                .whereType<CustomerOpportunity>()
                .toList()
          : const <CustomerOpportunity>[],
      selectionRequired: '${json['selection_required'] ?? ''}',
      accessDeniedReason: _clean(json['access_denied_reason']),
    );
  }
}

class CustomerOpportunityScopeOption {
  const CustomerOpportunityScopeOption({
    required this.code,
    required this.name,
    required this.label,
  });

  final String code;
  final String name;
  final String label;

  factory CustomerOpportunityScopeOption.fromJson(Map<String, dynamic> json) {
    final code = '${json['code'] ?? ''}'.trim();
    final name = _clean(json['name']);
    return CustomerOpportunityScopeOption(
      code: code,
      name: name,
      label: _clean(json['label']).isEmpty
          ? (name.isEmpty || name == code ? code : '$code - $name')
          : _clean(json['label']),
    );
  }
}

class CustomerOpportunityNeighborhood {
  const CustomerOpportunityNeighborhood({
    required this.key,
    required this.city,
    required this.district,
    required this.opportunityCount,
    required this.centerLatitude,
    required this.centerLongitude,
  });

  final String key;
  final String city;
  final String district;
  final int opportunityCount;
  final double centerLatitude;
  final double centerLongitude;

  String get label => '$city - $district';

  factory CustomerOpportunityNeighborhood.fromJson(Map<String, dynamic> json) {
    return CustomerOpportunityNeighborhood(
      key: '${json['neighborhood_key'] ?? ''}',
      city: _clean(json['city']),
      district: _clean(json['district']),
      opportunityCount: _toInt(json['opportunity_count']),
      centerLatitude: _toDouble(json['center_latitude']),
      centerLongitude: _toDouble(json['center_longitude']),
    );
  }
}

class CustomerOpportunityActivity {
  const CustomerOpportunityActivity({
    required this.key,
    required this.code,
    required this.name,
    required this.opportunityCount,
  });

  final String key;
  final String code;
  final String name;
  final int opportunityCount;

  String get label {
    final rawLabel = code.isEmpty
        ? name
        : name.isEmpty || name == code
        ? code
        : '$code - $name';
    return _activityLabel(rawLabel);
  }

  factory CustomerOpportunityActivity.fromJson(Map<String, dynamic> json) {
    return CustomerOpportunityActivity(
      key: '${json['activity_key'] ?? ''}'.trim(),
      code: '${json['activity_code'] ?? ''}'.trim(),
      name: _clean(json['activity_name']),
      opportunityCount: _toInt(json['opportunity_count']),
    );
  }
}

class CustomerOpportunitySupplier {
  const CustomerOpportunitySupplier({required this.code, required this.name});

  final String code;
  final String name;

  String get label => name.isEmpty || name == code ? code : '$code - $name';

  factory CustomerOpportunitySupplier.fromJson(Map<String, dynamic> json) {
    return CustomerOpportunitySupplier(
      code: '${json['code'] ?? ''}'.trim(),
      name: _clean(json['name']),
    );
  }
}

class CustomerOpportunity {
  const CustomerOpportunity({
    required this.taxId,
    required this.sourceCustomerCode,
    required this.clientName,
    required this.fantasyName,
    required this.activityCode,
    required this.activityName,
    required this.city,
    required this.uf,
    required this.district,
    required this.street,
    required this.addressNumber,
    required this.fullAddress,
    required this.postalCode,
    required this.creditLimit,
    required this.marketPotentialOrderCount,
    required this.latitude,
    required this.longitude,
    required this.suppliers,
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
  final String street;
  final String addressNumber;
  final String fullAddress;
  final String postalCode;
  final double creditLimit;
  final double? marketPotential;
  final int marketPotentialOrderCount;
  final double latitude;
  final double longitude;
  final List<CustomerOpportunitySupplier> suppliers;

  String get displayName => fantasyName.isNotEmpty ? fantasyName : clientName;

  String get activityLabel {
    final rawLabel = activityCode.isNotEmpty && activityName.isNotEmpty
        ? '$activityCode - $activityName'
        : activityName.isNotEmpty
        ? activityName
        : activityCode;
    return _activityLabel(rawLabel);
  }

  String get cityLabel => uf.isEmpty ? city : '$city - $uf';

  factory CustomerOpportunity.fromJson(Map<String, dynamic> json) {
    final rawSuppliers = json['suppliers'];
    return CustomerOpportunity(
      taxId: '${json['tax_id'] ?? ''}'.trim(),
      sourceCustomerCode: '${json['source_customer_code'] ?? ''}'.trim(),
      clientName: _clean(json['client_name']),
      fantasyName: _clean(json['fantasy_name']),
      activityCode: '${json['activity_code'] ?? ''}'.trim(),
      activityName: _clean(json['activity_name']),
      city: _clean(json['city']),
      uf: '${json['uf'] ?? ''}'.trim().toUpperCase(),
      district: _clean(json['district']),
      street: _clean(json['street']),
      addressNumber: _clean(json['address_number']),
      fullAddress: _clean(json['full_address']),
      postalCode: '${json['postal_code'] ?? ''}'.trim(),
      creditLimit: _toDouble(json['credit_limit']),
      marketPotential: _toNullableDouble(json['market_potential']),
      marketPotentialOrderCount: _toInt(json['market_potential_order_count']),
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      suppliers: rawSuppliers is List
          ? rawSuppliers
                .whereType<Map>()
                .map(
                  (row) => CustomerOpportunitySupplier.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <CustomerOpportunitySupplier>[],
    );
  }

  static CustomerOpportunity? fromMarkerJson(Object? value) {
    if (value is Map) {
      return CustomerOpportunity.fromJson(
        value.map((key, item) => MapEntry('$key', item)),
      );
    }
    if (value is! List || value.length < 3) {
      return null;
    }

    final taxId = '${value[0] ?? ''}'.trim();
    if (taxId.isEmpty) {
      return null;
    }

    return CustomerOpportunity(
      taxId: taxId,
      sourceCustomerCode: '',
      clientName: '',
      fantasyName: '',
      activityCode: '',
      activityName: '',
      city: '',
      uf: '',
      district: '',
      street: '',
      addressNumber: '',
      fullAddress: '',
      postalCode: '',
      creditLimit: 0,
      marketPotential: null,
      marketPotentialOrderCount: 0,
      latitude: _toDouble(value[1]),
      longitude: _toDouble(value[2]),
      suppliers: const <CustomerOpportunitySupplier>[],
    );
  }
}

String _activityLabel(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty || RegExp(r'^\d+$').hasMatch(normalized)) {
    return 'Sem ramo de atividade';
  }
  return normalized;
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

String? _nullableText(Object? value) {
  if (value == null) {
    return null;
  }
  final text = '$value'.trim();
  return text.isEmpty || text == 'null' ? null : text;
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
