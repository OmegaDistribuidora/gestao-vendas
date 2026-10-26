class CoachMarketSectionDefinition {
  const CoachMarketSectionDefinition({
    required this.code,
    required this.name,
    required this.assetPath,
    this.supplierCode = 117,
    this.supplierName = 'Bombril',
  });

  final int supplierCode;
  final String supplierName;
  final int code;
  final String name;
  final String assetPath;
}

const List<CoachMarketSectionDefinition> coachMarketSections = [
  CoachMarketSectionDefinition(
    code: 1,
    name: 'Detergente Limpol',
    assetPath: 'assets/coach_mercado/bombril/detergente_limpol.webp',
  ),
  CoachMarketSectionDefinition(
    code: 2,
    name: 'Lã de aço',
    assetPath: 'assets/coach_mercado/bombril/la_de_aco.webp',
  ),
  CoachMarketSectionDefinition(
    code: 3,
    name: 'Amaciante Concentrado',
    assetPath: 'assets/coach_mercado/bombril/amaciante_concentrado.webp',
  ),
  CoachMarketSectionDefinition(
    code: 4,
    name: 'Amaciante Regular',
    assetPath: 'assets/coach_mercado/bombril/amaciante_regular.webp',
  ),
  CoachMarketSectionDefinition(
    code: 5,
    name: 'Limpol Multiuso',
    assetPath: 'assets/coach_mercado/bombril/limpol_multiuso.webp',
  ),
  CoachMarketSectionDefinition(
    code: 6,
    name: 'Limpol Perfumado',
    assetPath: 'assets/coach_mercado/bombril/limpol_perfumado.webp',
  ),
  CoachMarketSectionDefinition(
    code: 7,
    name: 'Desinfetante Leitoso',
    assetPath: 'assets/coach_mercado/bombril/desinfetante_leitoso.webp',
  ),
  CoachMarketSectionDefinition(
    code: 8,
    name: 'Desinfetante Translúcido',
    assetPath: 'assets/coach_mercado/bombril/desinfetante_translucido.webp',
  ),
  CoachMarketSectionDefinition(
    code: 9,
    name: 'Esponja Sintética',
    assetPath: 'assets/coach_mercado/bombril/esponja_sintetica.webp',
  ),
  CoachMarketSectionDefinition(
    code: 10,
    name: 'Sapólio Cremoso',
    assetPath: 'assets/coach_mercado/bombril/sapolio_cremoso.webp',
  ),
  CoachMarketSectionDefinition(
    code: 11,
    name: 'Lava Roupas Multiuso',
    assetPath: 'assets/coach_mercado/bombril/lava_roupas_multiuso.webp',
  ),
];

class CoachMarketCustomer {
  const CoachMarketCustomer({
    required this.code,
    required this.name,
    this.city,
    this.neighborhood,
    this.address,
    this.lastPurchaseDate,
    required this.neverPurchased,
    this.sellerAssignments = const [],
    this.history = const [],
  });

  final int code;
  final String name;
  final String? city;
  final String? neighborhood;
  final String? address;
  final DateTime? lastPurchaseDate;
  final bool neverPurchased;
  final List<CoachMarketSellerAssignment> sellerAssignments;
  final List<CoachMarketHistoryRecord> history;

  factory CoachMarketCustomer.fromJson(Map<String, dynamic> json) {
    final rawDate = json['lastPurchaseDate']?.toString();
    return CoachMarketCustomer(
      code: (json['customerCode'] as num).toInt(),
      name: json['customerName']?.toString() ?? '',
      city: _optionalText(json['customerCity']),
      neighborhood: _optionalText(json['customerNeighborhood']),
      address: _optionalText(json['customerAddress']),
      lastPurchaseDate: rawDate == null ? null : DateTime.tryParse(rawDate),
      neverPurchased: json['customerNeverPurchased'] as bool? ?? false,
      sellerAssignments: _mapList(
        json['sellerAssignments'],
        CoachMarketSellerAssignment.fromJson,
      ),
      history: _mapList(json['history'], CoachMarketHistoryRecord.fromJson),
    );
  }
}

class CoachMarketSellerAssignment {
  const CoachMarketSellerAssignment({
    required this.sellerCode,
    required this.sellerName,
    this.supervisorCode,
    required this.supervisorName,
  });

  final int sellerCode;
  final String sellerName;
  final int? supervisorCode;
  final String supervisorName;

  factory CoachMarketSellerAssignment.fromJson(Map<String, dynamic> json) =>
      CoachMarketSellerAssignment(
        sellerCode: (json['sellerCode'] as num).toInt(),
        sellerName: json['sellerName']?.toString() ?? '',
        supervisorCode: (json['supervisorCode'] as num?)?.toInt(),
        supervisorName: json['supervisorName']?.toString() ?? '',
      );
}

class CoachMarketHistoryAnswer {
  const CoachMarketHistoryAnswer({
    required this.sectionCode,
    required this.sectionName,
    required this.hasSection,
  });

  final int sectionCode;
  final String sectionName;
  final bool hasSection;

  factory CoachMarketHistoryAnswer.fromJson(Map<String, dynamic> json) =>
      CoachMarketHistoryAnswer(
        sectionCode: (json['sectionCode'] as num).toInt(),
        sectionName: json['sectionName']?.toString() ?? '',
        hasSection: json['hasSection'] as bool? ?? false,
      );
}

class CoachMarketHistoryRecord {
  const CoachMarketHistoryRecord({
    required this.submissionId,
    required this.filledAt,
    required this.filledByName,
    this.filledByCode,
    required this.supplierName,
    required this.yesCount,
    required this.totalCount,
    required this.yesPercentage,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.locationAddress,
    required this.answers,
  });

  final String submissionId;
  final DateTime filledAt;
  final String filledByName;
  final String? filledByCode;
  final String supplierName;
  final int yesCount;
  final int totalCount;
  final double yesPercentage;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final String? locationAddress;
  final List<CoachMarketHistoryAnswer> answers;

  factory CoachMarketHistoryRecord.fromJson(Map<String, dynamic> json) =>
      CoachMarketHistoryRecord(
        submissionId: json['submissionId']?.toString() ?? '',
        filledAt:
            DateTime.tryParse(json['filledAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        filledByName: json['filledByName']?.toString() ?? 'Usuário',
        filledByCode: _optionalText(json['filledByCode']),
        supplierName: json['supplierName']?.toString() ?? 'Bombril',
        yesCount: (json['yesCount'] as num?)?.toInt() ?? 0,
        totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
        yesPercentage: (json['yesPercentage'] as num?)?.toDouble() ?? 0,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
        locationAddress: _optionalText(json['locationAddress']),
        answers: _mapList(json['answers'], CoachMarketHistoryAnswer.fromJson),
      );
}

class CoachMarketLocation {
  const CoachMarketLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    this.address,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final String? address;
  final DateTime capturedAt;

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracyMeters': accuracyMeters,
    if (address != null) 'address': address,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
  };
}

class CoachMarketSubmission {
  const CoachMarketSubmission({
    required this.submissionId,
    required this.customer,
    required this.customerDataSource,
    required this.customerLookupSucceeded,
    required this.location,
    required this.filledAt,
    required this.appVersion,
    required this.answers,
  });

  final String submissionId;
  final CoachMarketCustomer customer;
  final String customerDataSource;
  final bool customerLookupSucceeded;
  final CoachMarketLocation location;
  final DateTime filledAt;
  final String appVersion;
  final Map<int, bool> answers;

  Map<String, dynamic> toJson() => {
    'submissionId': submissionId,
    'customerCode': customer.code,
    'customerName': customer.name,
    'customerCity': customer.city,
    'customerNeighborhood': customer.neighborhood,
    'customerAddress': customer.address,
    'lastPurchaseDate': customer.lastPurchaseDate == null
        ? null
        : _dateOnly(customer.lastPurchaseDate!),
    'customerNeverPurchased': customer.neverPurchased,
    'customerDataSource': customerDataSource,
    'customerLookupSucceeded': customerLookupSucceeded,
    'location': location.toJson(),
    'filledAt': filledAt.toUtc().toIso8601String(),
    'appVersion': appVersion,
    'answers': coachMarketSections
        .map(
          (section) => {
            'supplierCode': section.supplierCode,
            'supplierName': section.supplierName,
            'sectionCode': section.code,
            'sectionName': section.name,
            'hasSection': answers[section.code],
          },
        )
        .toList(growable: false),
  };
}

String? _optionalText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

List<T> _mapList<T>(Object? value, T Function(Map<String, dynamic>) fromJson) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (item) =>
            fromJson(item.map((key, value) => MapEntry(key.toString(), value))),
      )
      .toList(growable: false);
}

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
