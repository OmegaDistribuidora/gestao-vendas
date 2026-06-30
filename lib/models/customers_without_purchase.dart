import '../utils/text_sanitizer.dart';

class CustomersWithoutPurchaseOverview {
  const CustomersWithoutPurchaseOverview({
    required this.viewerProfileSlug,
    required this.profileSlug,
    required this.selectedScopeProfileSlug,
    required this.selectedScopeOwnerCode,
    required this.periodStart,
    required this.periodEnd,
    required this.anchorMonth,
    required this.selectedSupplierCode,
    required this.availableScopes,
    required this.availableSuppliers,
    required this.totalClients,
    required this.regularClients,
    required this.semiRegularClients,
    required this.normalClients,
    required this.customers,
    this.lastUpdatedAt,
  });

  final String viewerProfileSlug;
  final String profileSlug;
  final String? selectedScopeProfileSlug;
  final String? selectedScopeOwnerCode;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime? anchorMonth;
  final String? selectedSupplierCode;
  final DateTime? lastUpdatedAt;
  final List<CustomerScopeOption> availableScopes;
  final List<CustomerSupplierOption> availableSuppliers;
  final int totalClients;
  final int regularClients;
  final int semiRegularClients;
  final int normalClients;
  final List<CustomerWithoutPurchase> customers;

  factory CustomersWithoutPurchaseOverview.empty() {
    return const CustomersWithoutPurchaseOverview(
      viewerProfileSlug: '',
      profileSlug: '',
      selectedScopeProfileSlug: null,
      selectedScopeOwnerCode: null,
      periodStart: null,
      periodEnd: null,
      anchorMonth: null,
      selectedSupplierCode: null,
      availableScopes: <CustomerScopeOption>[],
      availableSuppliers: <CustomerSupplierOption>[],
      totalClients: 0,
      regularClients: 0,
      semiRegularClients: 0,
      normalClients: 0,
      customers: <CustomerWithoutPurchase>[],
    );
  }

  factory CustomersWithoutPurchaseOverview.fromJson(Map<String, dynamic> json) {
    final rawScopes = json['available_scopes'];
    final rawSuppliers = json['available_suppliers'];
    final rawCustomers = json['customers'];
    return CustomersWithoutPurchaseOverview(
      viewerProfileSlug: '${json['viewer_profile_slug'] ?? ''}',
      profileSlug: '${json['profile_slug'] ?? ''}',
      selectedScopeProfileSlug: _toNullableString(
        json['selected_scope_profile_slug'],
      ),
      selectedScopeOwnerCode: _toNullableString(
        json['selected_scope_owner_code'],
      ),
      periodStart: _parseDate(json['period_start']),
      periodEnd: _parseDate(json['period_end']),
      anchorMonth: _parseDate(json['anchor_month']),
      selectedSupplierCode: _toNullableString(json['selected_supplier_code']),
      lastUpdatedAt: _parseDateTime(json['last_updated_at']),
      availableScopes: rawScopes is List
          ? rawScopes
                .whereType<Map>()
                .map(
                  (row) => CustomerScopeOption.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <CustomerScopeOption>[],
      availableSuppliers: rawSuppliers is List
          ? rawSuppliers
                .whereType<Map>()
                .map(
                  (row) => CustomerSupplierOption.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <CustomerSupplierOption>[],
      totalClients: _toInt(json['total_clients']),
      regularClients: _toInt(json['regular_clients']),
      semiRegularClients: _toInt(json['semi_regular_clients']),
      normalClients: _toInt(json['normal_clients']),
      customers: rawCustomers is List
          ? rawCustomers
                .whereType<Map>()
                .map(
                  (row) => CustomerWithoutPurchase.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <CustomerWithoutPurchase>[],
    );
  }

  static String? _toNullableString(Object? value) {
    final text = '$value'.trim();
    if (value == null || text.isEmpty || text == 'null') {
      return null;
    }
    return text;
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }

  static int _toInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  static double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? 0;
    }
    return 0;
  }
}

class CustomerScopeOption {
  const CustomerScopeOption({
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

  factory CustomerScopeOption.fromJson(Map<String, dynamic> json) {
    return CustomerScopeOption(
      profileSlug: '${json['profile_slug'] ?? ''}',
      ownerCode: '${json['owner_code'] ?? ''}',
      displayName: TextSanitizer.normalize(
        json['display_name'] as String? ?? '',
      ),
      label: TextSanitizer.normalize(json['label'] as String? ?? ''),
    );
  }
}

class CustomerSupplierOption {
  const CustomerSupplierOption({
    required this.code,
    required this.supplierName,
  });

  final String code;
  final String supplierName;

  String get label {
    if (supplierName.trim().isEmpty) {
      return code;
    }
    return '$code - $supplierName';
  }

  factory CustomerSupplierOption.fromJson(Map<String, dynamic> json) {
    return CustomerSupplierOption(
      code: '${json['code'] ?? ''}'.trim(),
      supplierName: TextSanitizer.normalize(
        json['supplier_name'] as String? ?? '',
      ),
    );
  }
}

class CustomerWithoutPurchase {
  const CustomerWithoutPurchase({
    required this.codcli,
    required this.clientName,
    required this.codCliente,
    required this.fantasia,
    required this.codFantasia,
    required this.address,
    required this.district,
    required this.cityName,
    required this.cep,
    required this.activityCode,
    required this.cityCode,
    required this.networkCode,
    required this.marketCode,
    required this.uf,
    required this.creditLimit,
    required this.ibgeCode,
    required this.status,
    required this.blockReason,
    required this.cnpj,
    required this.codusur,
    required this.sellerName,
    required this.codsupervisor,
    required this.supervisorName,
    required this.codgerente,
    required this.coordinatorName,
    required this.lastPurchaseAmount,
    required this.daysWithoutPurchase,
    required this.regularityLabel,
    required this.recentOrders,
    this.blockedAt,
    this.lastPurchaseDate,
  });

  final String codcli;
  final String clientName;
  final String codCliente;
  final String fantasia;
  final String codFantasia;
  final String address;
  final String district;
  final String cityName;
  final String cep;
  final String activityCode;
  final String cityCode;
  final String networkCode;
  final String marketCode;
  final String uf;
  final double creditLimit;
  final String ibgeCode;
  final String status;
  final String blockReason;
  final DateTime? blockedAt;
  final String cnpj;
  final String codusur;
  final String sellerName;
  final String codsupervisor;
  final String supervisorName;
  final String codgerente;
  final String coordinatorName;
  final DateTime? lastPurchaseDate;
  final double lastPurchaseAmount;
  final int daysWithoutPurchase;
  final String regularityLabel;
  final List<CustomerRecentOrder> recentOrders;

  String get displayName {
    if (clientName.trim().isNotEmpty) {
      return clientName;
    }
    if (fantasia.trim().isNotEmpty) {
      return fantasia;
    }
    return codcli;
  }

  factory CustomerWithoutPurchase.fromJson(Map<String, dynamic> json) {
    final rawOrders = json['recent_orders'];
    return CustomerWithoutPurchase(
      codcli: '${json['codcli'] ?? ''}'.trim(),
      clientName: TextSanitizer.normalize(json['client_name'] as String? ?? ''),
      codCliente: TextSanitizer.normalize(json['cod_cliente'] as String? ?? ''),
      fantasia: TextSanitizer.normalize(json['fantasia'] as String? ?? ''),
      codFantasia: TextSanitizer.normalize(
        json['cod_fantasia'] as String? ?? '',
      ),
      address: TextSanitizer.normalize(json['address'] as String? ?? ''),
      district: TextSanitizer.normalize(json['district'] as String? ?? ''),
      cityName: TextSanitizer.normalize(json['city_name'] as String? ?? ''),
      cep: '${json['cep'] ?? ''}'.trim(),
      activityCode: '${json['activity_code'] ?? ''}'.trim(),
      cityCode: '${json['city_code'] ?? ''}'.trim(),
      networkCode: '${json['network_code'] ?? ''}'.trim(),
      marketCode: '${json['market_code'] ?? ''}'.trim(),
      uf: '${json['uf'] ?? ''}'.trim(),
      creditLimit: CustomersWithoutPurchaseOverview._toDouble(
        json['credit_limit'],
      ),
      ibgeCode: '${json['ibge_code'] ?? ''}'.trim(),
      status: TextSanitizer.normalize(json['status'] as String? ?? ''),
      blockReason: TextSanitizer.normalize(
        json['block_reason'] as String? ?? '',
      ),
      blockedAt: CustomersWithoutPurchaseOverview._parseDate(
        json['blocked_at'],
      ),
      cnpj: '${json['cnpj'] ?? ''}'.trim(),
      codusur: '${json['codusur'] ?? ''}'.trim(),
      sellerName: TextSanitizer.normalize(json['seller_name'] as String? ?? ''),
      codsupervisor: '${json['codsupervisor'] ?? ''}'.trim(),
      supervisorName: TextSanitizer.normalize(
        json['supervisor_name'] as String? ?? '',
      ),
      codgerente: '${json['codgerente'] ?? ''}'.trim(),
      coordinatorName: TextSanitizer.normalize(
        json['coordinator_name'] as String? ?? '',
      ),
      lastPurchaseDate: CustomersWithoutPurchaseOverview._parseDate(
        json['last_purchase_date'],
      ),
      lastPurchaseAmount: CustomersWithoutPurchaseOverview._toDouble(
        json['last_purchase_amount'],
      ),
      daysWithoutPurchase: CustomersWithoutPurchaseOverview._toInt(
        json['days_without_purchase'],
      ),
      regularityLabel: '${json['regularity_label'] ?? 'Normal'}'.trim(),
      recentOrders: rawOrders is List
          ? rawOrders
                .whereType<Map>()
                .map(
                  (row) => CustomerRecentOrder.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <CustomerRecentOrder>[],
    );
  }
}

class CustomerRecentOrder {
  const CustomerRecentOrder({
    required this.numped,
    required this.totalAmount,
    required this.totalVolume,
    required this.itemCount,
    required this.items,
    this.salesDate,
  });

  final String numped;
  final DateTime? salesDate;
  final double totalAmount;
  final double totalVolume;
  final int itemCount;
  final List<CustomerRecentOrderItem> items;

  factory CustomerRecentOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map(
                (row) => CustomerRecentOrderItem.fromJson(
                  row.map((key, value) => MapEntry('$key', value)),
                ),
              )
              .toList()
        : const <CustomerRecentOrderItem>[];
    final distinctProductCodes = items
        .map((item) => item.codprod)
        .where((code) => code.isNotEmpty)
        .toSet();

    return CustomerRecentOrder(
      numped: '${json['numped'] ?? ''}'.trim(),
      salesDate: CustomersWithoutPurchaseOverview._parseDate(
        json['sales_date'],
      ),
      totalAmount: CustomersWithoutPurchaseOverview._toDouble(
        json['total_amount'],
      ),
      totalVolume: CustomersWithoutPurchaseOverview._toDouble(
        json['total_volume'],
      ),
      itemCount: distinctProductCodes.isNotEmpty
          ? distinctProductCodes.length
          : CustomersWithoutPurchaseOverview._toInt(json['item_count']),
      items: items,
    );
  }
}

class CustomerRecentOrderItem {
  const CustomerRecentOrderItem({
    required this.codfornec,
    required this.supplierName,
    required this.codprod,
    required this.productName,
    required this.itemValue,
    required this.quantity,
    required this.volume,
  });

  final String codfornec;
  final String supplierName;
  final String codprod;
  final String productName;
  final double itemValue;
  final double quantity;
  final double volume;

  factory CustomerRecentOrderItem.fromJson(Map<String, dynamic> json) {
    return CustomerRecentOrderItem(
      codfornec: '${json['codfornec'] ?? ''}'.trim(),
      supplierName: TextSanitizer.normalize(
        json['supplier_name'] as String? ?? '',
      ),
      codprod: '${json['codprod'] ?? ''}'.trim(),
      productName: TextSanitizer.normalize(
        json['product_name'] as String? ?? '',
      ),
      itemValue: CustomersWithoutPurchaseOverview._toDouble(json['item_value']),
      quantity: CustomersWithoutPurchaseOverview._toDouble(json['quantity']),
      volume: CustomersWithoutPurchaseOverview._toDouble(json['volume']),
    );
  }
}
