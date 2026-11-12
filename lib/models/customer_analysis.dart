class CustomerAnalysisSearchResult {
  const CustomerAnalysisSearchResult({
    required this.code,
    required this.name,
    this.tradeName,
    this.document,
    this.city,
    this.neighborhood,
    this.address,
    this.latitude,
    this.longitude,
    required this.blocked,
    this.distanceKm,
  });

  final int code;
  final String name;
  final String? tradeName;
  final String? document;
  final String? city;
  final String? neighborhood;
  final String? address;
  final double? latitude;
  final double? longitude;
  final bool blocked;
  final double? distanceKm;

  factory CustomerAnalysisSearchResult.fromJson(Map<String, dynamic> json) =>
      CustomerAnalysisSearchResult(
        code: (json['customerCode'] as num).toInt(),
        name: json['customerName']?.toString() ?? '',
        tradeName: _optionalText(json['tradeName']),
        document: _optionalText(json['document']),
        city: _optionalText(json['city']),
        neighborhood: _optionalText(json['neighborhood']),
        address: _optionalText(json['address']),
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        blocked: json['blocked'] as bool? ?? false,
        distanceKm: (json['distanceKm'] as num?)?.toDouble(),
      );
}

class CustomerAnalysisDetail {
  const CustomerAnalysisDetail({
    required this.customer,
    required this.periods,
    required this.quarterlyAverage,
    required this.semesterAverage,
    required this.metricAverages,
    required this.purchaseInsights,
    this.lastPurchase,
    required this.recentOrders,
    required this.topProducts,
    required this.topSuppliers,
    required this.lostProducts,
    required this.delinquency,
    required this.returnsSummary,
  });

  final CustomerAnalysisCustomer customer;
  final CustomerAnalysisPeriods periods;
  final double quarterlyAverage;
  final double semesterAverage;
  final CustomerMetricAverages metricAverages;
  final CustomerPurchaseInsights purchaseInsights;
  final CustomerOrderSummary? lastPurchase;
  final List<CustomerOrderSummary> recentOrders;
  final List<CustomerProductMetric> topProducts;
  final List<CustomerSupplierMetric> topSuppliers;
  final List<CustomerLostProduct> lostProducts;
  final CustomerDelinquencySummary delinquency;
  final CustomerReturnsSummary returnsSummary;

  factory CustomerAnalysisDetail.fromJson(
    Map<String, dynamic> json,
  ) => CustomerAnalysisDetail(
    customer: CustomerAnalysisCustomer.fromJson(_stringMap(json['customer'])),
    periods: CustomerAnalysisPeriods.fromJson(_stringMap(json['periods'])),
    quarterlyAverage: (json['quarterlyAverage'] as num?)?.toDouble() ?? 0,
    semesterAverage: (json['semesterAverage'] as num?)?.toDouble() ?? 0,
    metricAverages: CustomerMetricAverages.fromJson(
      _stringMap(json['metricAverages']),
      fallbackQuarterly: (json['quarterlyAverage'] as num?)?.toDouble() ?? 0,
      fallbackSemester: (json['semesterAverage'] as num?)?.toDouble() ?? 0,
    ),
    purchaseInsights: CustomerPurchaseInsights.fromJson(
      _stringMap(json['purchaseInsights']),
    ),
    lastPurchase: json['lastPurchase'] is Map
        ? CustomerOrderSummary.fromJson(_stringMap(json['lastPurchase']))
        : null,
    recentOrders: _mapList(json['recentOrders'], CustomerOrderSummary.fromJson),
    topProducts: _mapList(json['topProducts'], CustomerProductMetric.fromJson),
    topSuppliers: _mapList(
      json['topSuppliers'],
      CustomerSupplierMetric.fromJson,
    ),
    lostProducts: _mapList(json['lostProducts'], CustomerLostProduct.fromJson),
    delinquency: CustomerDelinquencySummary.fromJson(
      _stringMap(json['delinquency']),
    ),
    returnsSummary: CustomerReturnsSummary.fromJson(
      _stringMap(json['returns']),
    ),
  );
}

class CustomerAnalysisCustomer {
  const CustomerAnalysisCustomer({
    required this.code,
    required this.name,
    this.tradeName,
    this.document,
    this.address,
    this.neighborhood,
    this.zipCode,
    this.city,
    this.state,
    this.commercialActivity,
    this.registrationStatus,
    required this.blocked,
    this.blockReason,
    this.blockedAt,
    this.lastPurchaseDate,
    required this.creditLimit,
    this.latitude,
    this.longitude,
    required this.sellerAssignments,
  });

  final int code;
  final String name;
  final String? tradeName;
  final String? document;
  final String? address;
  final String? neighborhood;
  final String? zipCode;
  final String? city;
  final String? state;
  final String? commercialActivity;
  final String? registrationStatus;
  final bool blocked;
  final String? blockReason;
  final DateTime? blockedAt;
  final DateTime? lastPurchaseDate;
  final double creditLimit;
  final double? latitude;
  final double? longitude;
  final List<CustomerSellerAssignment> sellerAssignments;

  factory CustomerAnalysisCustomer.fromJson(Map<String, dynamic> json) =>
      CustomerAnalysisCustomer(
        code: (json['customerCode'] as num).toInt(),
        name: json['customerName']?.toString() ?? '',
        tradeName: _optionalText(json['tradeName']),
        document: _optionalText(json['document']),
        address: _optionalText(json['address']),
        neighborhood: _optionalText(json['neighborhood']),
        zipCode: _optionalText(json['zipCode']),
        city: _optionalText(json['city']),
        state: _optionalText(json['state']),
        commercialActivity: _optionalText(json['commercialActivity']),
        registrationStatus: _optionalText(json['registrationStatus']),
        blocked: json['blocked'] as bool? ?? false,
        blockReason: _optionalText(json['blockReason']),
        blockedAt: _optionalDate(json['blockedAt']),
        lastPurchaseDate: _optionalDate(json['lastPurchaseDate']),
        creditLimit: (json['creditLimit'] as num?)?.toDouble() ?? 0,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        sellerAssignments: _mapList(
          json['sellerAssignments'],
          CustomerSellerAssignment.fromJson,
        ),
      );
}

class CustomerSellerAssignment {
  const CustomerSellerAssignment({
    required this.sellerCode,
    required this.sellerName,
    this.supervisorCode,
    this.supervisorName,
  });

  final int sellerCode;
  final String sellerName;
  final int? supervisorCode;
  final String? supervisorName;

  factory CustomerSellerAssignment.fromJson(Map<String, dynamic> json) =>
      CustomerSellerAssignment(
        sellerCode: (json['sellerCode'] as num).toInt(),
        sellerName: json['sellerName']?.toString() ?? '',
        supervisorCode: (json['supervisorCode'] as num?)?.toInt(),
        supervisorName: _optionalText(json['supervisorName']),
      );
}

class CustomerAnalysisPeriods {
  const CustomerAnalysisPeriods({
    required this.quarterMonths,
    required this.semesterMonths,
  });

  final List<DateTime> quarterMonths;
  final List<DateTime> semesterMonths;

  factory CustomerAnalysisPeriods.fromJson(Map<String, dynamic> json) =>
      CustomerAnalysisPeriods(
        quarterMonths: _dateList(json['quarterMonths']),
        semesterMonths: _dateList(json['semesterMonths']),
      );
}

class CustomerMetricValues {
  const CustomerMetricValues({
    required this.financial,
    required this.volume,
    required this.skus,
  });

  final double financial;
  final double volume;
  final double skus;

  factory CustomerMetricValues.fromJson(
    Map<String, dynamic> json, {
    double? fallbackFinancial,
  }) => CustomerMetricValues(
    financial:
        (json['financial'] as num?)?.toDouble() ?? fallbackFinancial ?? 0,
    volume: (json['volume'] as num?)?.toDouble() ?? 0,
    skus: (json['skus'] as num?)?.toDouble() ?? 0,
  );
}

class CustomerMetricAveragePair {
  const CustomerMetricAveragePair({
    required this.quarterly,
    required this.semester,
  });

  final double quarterly;
  final double semester;

  factory CustomerMetricAveragePair.fromJson(
    Map<String, dynamic> json, {
    double fallbackQuarterly = 0,
    double fallbackSemester = 0,
  }) => CustomerMetricAveragePair(
    quarterly: (json['quarterly'] as num?)?.toDouble() ?? fallbackQuarterly,
    semester: (json['semester'] as num?)?.toDouble() ?? fallbackSemester,
  );
}

class CustomerMetricAverages {
  const CustomerMetricAverages({
    required this.financial,
    required this.volume,
    required this.skus,
  });

  final CustomerMetricAveragePair financial;
  final CustomerMetricAveragePair volume;
  final CustomerMetricAveragePair skus;

  factory CustomerMetricAverages.fromJson(
    Map<String, dynamic> json, {
    double fallbackQuarterly = 0,
    double fallbackSemester = 0,
  }) => CustomerMetricAverages(
    financial: CustomerMetricAveragePair.fromJson(
      _stringMap(json['financial']),
      fallbackQuarterly: fallbackQuarterly,
      fallbackSemester: fallbackSemester,
    ),
    volume: CustomerMetricAveragePair.fromJson(_stringMap(json['volume'])),
    skus: CustomerMetricAveragePair.fromJson(_stringMap(json['skus'])),
  );
}

class CustomerMetricOrders {
  const CustomerMetricOrders({this.financial, this.volume, this.skus});

  final CustomerOrderSummary? financial;
  final CustomerOrderSummary? volume;
  final CustomerOrderSummary? skus;

  factory CustomerMetricOrders.fromJson(
    Map<String, dynamic> json, {
    CustomerOrderSummary? fallbackFinancial,
  }) => CustomerMetricOrders(
    financial: json['financial'] is Map
        ? CustomerOrderSummary.fromJson(_stringMap(json['financial']))
        : fallbackFinancial,
    volume: json['volume'] is Map
        ? CustomerOrderSummary.fromJson(_stringMap(json['volume']))
        : null,
    skus: json['skus'] is Map
        ? CustomerOrderSummary.fromJson(_stringMap(json['skus']))
        : null,
  );
}

class CustomerPurchaseInsights {
  const CustomerPurchaseInsights({
    this.daysWithoutPurchase,
    this.averageFrequencyDays,
    required this.averageTicketLastFiveOrders,
    required this.averageTickets,
    this.currentMonth,
    required this.currentMonthAmount,
    this.previousMonth,
    required this.previousMonthAmount,
    this.monthVariationPercent,
    required this.currentMonthMetrics,
    required this.previousMonthMetrics,
    required this.monthVariations,
    this.largestOrder,
    required this.largestOrders,
    required this.monthlyEvolution,
  });

  final int? daysWithoutPurchase;
  final int? averageFrequencyDays;
  final double averageTicketLastFiveOrders;
  final CustomerMetricValues averageTickets;
  final DateTime? currentMonth;
  final double currentMonthAmount;
  final DateTime? previousMonth;
  final double previousMonthAmount;
  final double? monthVariationPercent;
  final CustomerMetricValues currentMonthMetrics;
  final CustomerMetricValues previousMonthMetrics;
  final CustomerMetricValues monthVariations;
  final CustomerOrderSummary? largestOrder;
  final CustomerMetricOrders largestOrders;
  final List<CustomerMonthlySale> monthlyEvolution;

  factory CustomerPurchaseInsights.fromJson(
    Map<String, dynamic> json,
  ) => CustomerPurchaseInsights(
    daysWithoutPurchase: (json['daysWithoutPurchase'] as num?)?.toInt(),
    averageFrequencyDays: (json['averageFrequencyDays'] as num?)?.toInt(),
    averageTicketLastFiveOrders:
        (json['averageTicketLastFiveOrders'] as num?)?.toDouble() ?? 0,
    averageTickets: CustomerMetricValues.fromJson(
      _stringMap(json['averageTickets']),
      fallbackFinancial:
          (json['averageTicketLastFiveOrders'] as num?)?.toDouble() ?? 0,
    ),
    currentMonth: _optionalDate(json['currentMonth']),
    currentMonthAmount: (json['currentMonthAmount'] as num?)?.toDouble() ?? 0,
    previousMonth: _optionalDate(json['previousMonth']),
    previousMonthAmount: (json['previousMonthAmount'] as num?)?.toDouble() ?? 0,
    monthVariationPercent: (json['monthVariationPercent'] as num?)?.toDouble(),
    currentMonthMetrics: CustomerMetricValues.fromJson(
      _stringMap(json['currentMonthMetrics']),
      fallbackFinancial: (json['currentMonthAmount'] as num?)?.toDouble() ?? 0,
    ),
    previousMonthMetrics: CustomerMetricValues.fromJson(
      _stringMap(json['previousMonthMetrics']),
      fallbackFinancial: (json['previousMonthAmount'] as num?)?.toDouble() ?? 0,
    ),
    monthVariations: CustomerMetricValues.fromJson(
      _stringMap(json['monthVariations']),
      fallbackFinancial: (json['monthVariationPercent'] as num?)?.toDouble(),
    ),
    largestOrder: json['largestOrder'] is Map
        ? CustomerOrderSummary.fromJson(_stringMap(json['largestOrder']))
        : null,
    largestOrders: CustomerMetricOrders.fromJson(
      _stringMap(json['largestOrders']),
      fallbackFinancial: json['largestOrder'] is Map
          ? CustomerOrderSummary.fromJson(_stringMap(json['largestOrder']))
          : null,
    ),
    monthlyEvolution: _mapList(
      json['monthlyEvolution'],
      CustomerMonthlySale.fromJson,
    ),
  );
}

class CustomerMonthlySale {
  const CustomerMonthlySale({
    required this.month,
    required this.amount,
    required this.volume,
    required this.skus,
  });

  final DateTime month;
  final double amount;
  final double volume;
  final double skus;

  factory CustomerMonthlySale.fromJson(Map<String, dynamic> json) =>
      CustomerMonthlySale(
        month: DateTime.parse(json['month'].toString()),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        volume: (json['volume'] as num?)?.toDouble() ?? 0,
        skus: (json['skus'] as num?)?.toDouble() ?? 0,
      );
}

class CustomerLostProduct {
  const CustomerLostProduct({
    required this.productCode,
    required this.productName,
    this.package,
    required this.lastPurchaseDate,
    required this.previousOrderCount,
    required this.quantity,
    required this.boxes,
    required this.volume,
    required this.amount,
  });

  final int productCode;
  final String productName;
  final String? package;
  final DateTime lastPurchaseDate;
  final int previousOrderCount;
  final double quantity;
  final double boxes;
  final double volume;
  final double amount;

  factory CustomerLostProduct.fromJson(Map<String, dynamic> json) =>
      CustomerLostProduct(
        productCode: (json['productCode'] as num).toInt(),
        productName: json['productName']?.toString() ?? '',
        package: _optionalText(json['package']),
        lastPurchaseDate: DateTime.parse(json['lastPurchaseDate'].toString()),
        previousOrderCount: (json['previousOrderCount'] as num?)?.toInt() ?? 0,
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        boxes: (json['boxes'] as num?)?.toDouble() ?? 0,
        volume: (json['volume'] as num?)?.toDouble() ?? 0,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
      );
}

class CustomerDelinquencySummary {
  const CustomerDelinquencySummary({
    required this.hasOpenTitles,
    required this.titleCount,
    required this.totalAmount,
    required this.titles,
  });

  final bool hasOpenTitles;
  final int titleCount;
  final double totalAmount;
  final List<CustomerDelinquencyTitle> titles;

  factory CustomerDelinquencySummary.fromJson(Map<String, dynamic> json) =>
      CustomerDelinquencySummary(
        hasOpenTitles: json['hasOpenTitles'] as bool? ?? false,
        titleCount: (json['titleCount'] as num?)?.toInt() ?? 0,
        totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0,
        titles: _mapList(json['titles'], CustomerDelinquencyTitle.fromJson),
      );
}

class CustomerDelinquencyTitle {
  const CustomerDelinquencyTitle({
    this.issueDate,
    required this.dueDate,
    this.orderNumber,
    this.installment,
    this.document,
    this.collectionCode,
    required this.amount,
    required this.originalAmount,
    required this.daysOverdue,
  });

  final DateTime? issueDate;
  final DateTime dueDate;
  final int? orderNumber;
  final String? installment;
  final String? document;
  final String? collectionCode;
  final double amount;
  final double originalAmount;
  final int daysOverdue;

  factory CustomerDelinquencyTitle.fromJson(Map<String, dynamic> json) =>
      CustomerDelinquencyTitle(
        issueDate: _optionalDate(json['issueDate']),
        dueDate: DateTime.parse(json['dueDate'].toString()),
        orderNumber: (json['orderNumber'] as num?)?.toInt(),
        installment: _optionalText(json['installment']),
        document: _optionalText(json['document']),
        collectionCode: _optionalText(json['collectionCode']),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        originalAmount: (json['originalAmount'] as num?)?.toDouble() ?? 0,
        daysOverdue: (json['daysOverdue'] as num?)?.toInt() ?? 0,
      );
}

class CustomerReturnsSummary {
  const CustomerReturnsSummary({
    required this.hasReturns,
    required this.returnCount,
    required this.totalAmount,
    required this.totalVolume,
    required this.totalSkus,
    required this.latest,
  });

  final bool hasReturns;
  final int returnCount;
  final double totalAmount;
  final double totalVolume;
  final int totalSkus;
  final List<CustomerReturnSummary> latest;

  factory CustomerReturnsSummary.fromJson(Map<String, dynamic> json) =>
      CustomerReturnsSummary(
        hasReturns: json['hasReturns'] as bool? ?? false,
        returnCount: (json['returnCount'] as num?)?.toInt() ?? 0,
        totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0,
        totalVolume: (json['totalVolume'] as num?)?.toDouble() ?? 0,
        totalSkus: (json['totalSkus'] as num?)?.toInt() ?? 0,
        latest: _mapList(json['latest'], CustomerReturnSummary.fromJson),
      );
}

class CustomerReturnSummary {
  const CustomerReturnSummary({
    required this.date,
    this.orderNumber,
    this.invoiceNumber,
    this.reason,
    required this.amount,
    required this.volume,
    required this.quantity,
    required this.itemCount,
  });

  final DateTime date;
  final int? orderNumber;
  final String? invoiceNumber;
  final String? reason;
  final double amount;
  final double volume;
  final double quantity;
  final int itemCount;

  factory CustomerReturnSummary.fromJson(Map<String, dynamic> json) =>
      CustomerReturnSummary(
        date: DateTime.parse(json['date'].toString()),
        orderNumber: (json['orderNumber'] as num?)?.toInt(),
        invoiceNumber: _optionalText(json['invoiceNumber']),
        reason: _optionalText(json['reason']),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        volume: (json['volume'] as num?)?.toDouble() ?? 0,
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      );
}

class CustomerOrderSummary {
  const CustomerOrderSummary({
    required this.orderNumber,
    required this.date,
    required this.amount,
    required this.volume,
    required this.quantity,
    required this.productCount,
    this.sellerCode,
  });

  final int orderNumber;
  final DateTime date;
  final double amount;
  final double volume;
  final double quantity;
  final int productCount;
  final int? sellerCode;

  factory CustomerOrderSummary.fromJson(Map<String, dynamic> json) =>
      CustomerOrderSummary(
        orderNumber: (json['orderNumber'] as num).toInt(),
        date: DateTime.parse(json['date'].toString()),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        volume: (json['volume'] as num?)?.toDouble() ?? 0,
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        productCount: (json['productCount'] as num?)?.toInt() ?? 0,
        sellerCode: (json['sellerCode'] as num?)?.toInt(),
      );
}

class CustomerOrderDetail {
  const CustomerOrderDetail({
    required this.orderNumber,
    required this.date,
    required this.amount,
    required this.volume,
    required this.quantity,
    required this.items,
    required this.truncated,
  });

  final int orderNumber;
  final DateTime date;
  final double amount;
  final double volume;
  final double quantity;
  final List<CustomerOrderItem> items;
  final bool truncated;

  factory CustomerOrderDetail.fromJson(Map<String, dynamic> json) =>
      CustomerOrderDetail(
        orderNumber: (json['orderNumber'] as num).toInt(),
        date: DateTime.parse(json['date'].toString()),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        volume: (json['volume'] as num?)?.toDouble() ?? 0,
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        items: _mapList(json['items'], CustomerOrderItem.fromJson),
        truncated: json['truncated'] as bool? ?? false,
      );
}

class CustomerOrderItem {
  const CustomerOrderItem({
    required this.productCode,
    required this.productName,
    this.package,
    required this.supplierCode,
    required this.supplierName,
    required this.quantity,
    required this.boxes,
    required this.volume,
    required this.amount,
    required this.unitPrice,
  });

  final int productCode;
  final String productName;
  final String? package;
  final int supplierCode;
  final String supplierName;
  final double quantity;
  final double boxes;
  final double volume;
  final double amount;
  final double unitPrice;

  factory CustomerOrderItem.fromJson(Map<String, dynamic> json) =>
      CustomerOrderItem(
        productCode: (json['productCode'] as num).toInt(),
        productName: json['productName']?.toString() ?? '',
        package: _optionalText(json['package']),
        supplierCode: (json['supplierCode'] as num).toInt(),
        supplierName: json['supplierName']?.toString() ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        boxes: (json['boxes'] as num?)?.toDouble() ?? 0,
        volume: (json['volume'] as num?)?.toDouble() ?? 0,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
      );
}

class CustomerProductMetric {
  const CustomerProductMetric({
    required this.productCode,
    required this.productName,
    this.package,
    required this.quantity,
    required this.boxes,
    required this.volume,
    required this.amount,
  });

  final int productCode;
  final String productName;
  final String? package;
  final double quantity;
  final double boxes;
  final double volume;
  final double amount;

  factory CustomerProductMetric.fromJson(Map<String, dynamic> json) =>
      CustomerProductMetric(
        productCode: (json['productCode'] as num).toInt(),
        productName: json['productName']?.toString() ?? '',
        package: _optionalText(json['package']),
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        boxes: (json['boxes'] as num?)?.toDouble() ?? 0,
        volume: (json['volume'] as num?)?.toDouble() ?? 0,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
      );
}

class CustomerSupplierMetric {
  const CustomerSupplierMetric({
    required this.supplierCode,
    required this.supplierName,
    required this.amount,
    required this.volume,
    required this.skuCount,
  });

  final int supplierCode;
  final String supplierName;
  final double amount;
  final double volume;
  final int skuCount;

  factory CustomerSupplierMetric.fromJson(Map<String, dynamic> json) =>
      CustomerSupplierMetric(
        supplierCode: (json['supplierCode'] as num).toInt(),
        supplierName: json['supplierName']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        volume: (json['volume'] as num?)?.toDouble() ?? 0,
        skuCount: (json['skuCount'] as num?)?.toInt() ?? 0,
      );
}

String? _optionalText(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _optionalDate(dynamic value) {
  final text = _optionalText(value);
  return text == null ? null : DateTime.tryParse(text);
}

List<DateTime> _dateList(dynamic value) {
  if (value is! List) return const <DateTime>[];
  return value.map(_optionalDate).whereType<DateTime>().toList(growable: false);
}

Map<String, dynamic> _stringMap(dynamic value) {
  if (value is! Map) return const <String, dynamic>{};
  return value.map((key, item) => MapEntry('$key', item));
}

List<T> _mapList<T>(dynamic value, T Function(Map<String, dynamic>) converter) {
  if (value is! List) return <T>[];
  return value
      .whereType<Map>()
      .map((item) => converter(_stringMap(item)))
      .toList(growable: false);
}
