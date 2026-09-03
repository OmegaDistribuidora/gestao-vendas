import '../utils/text_sanitizer.dart';

class HomePositiveCustomers {
  const HomePositiveCustomers({
    required this.totalClients,
    required this.totalNewCustomers,
    required this.totalAmount,
    required this.items,
  });

  final int totalClients;
  final int totalNewCustomers;
  final double totalAmount;
  final List<HomePositiveCustomer> items;

  factory HomePositiveCustomers.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return HomePositiveCustomers(
      totalClients: (json['total_clients'] as num?)?.toInt() ?? 0,
      totalNewCustomers: (json['total_new_customers'] as num?)?.toInt() ?? 0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (row) => HomePositiveCustomer.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <HomePositiveCustomer>[],
    );
  }
}

class HomePositiveCustomer {
  const HomePositiveCustomer({
    required this.clientCode,
    required this.clientName,
    required this.totalAmount,
    required this.isNewInMonth,
    required this.sellerCode,
    required this.sellerName,
  });

  final String clientCode;
  final String clientName;
  final double totalAmount;
  final bool isNewInMonth;
  final String sellerCode;
  final String sellerName;

  String get sellerLabel {
    if (sellerCode.isEmpty) {
      return sellerName;
    }
    if (sellerName.isEmpty || sellerName == sellerCode) {
      return sellerCode;
    }
    return '$sellerCode - $sellerName';
  }

  factory HomePositiveCustomer.fromJson(Map<String, dynamic> json) {
    return HomePositiveCustomer(
      clientCode: '${json['client_code'] ?? ''}'.trim(),
      clientName: TextSanitizer.normalize(
        '${json['client_name'] ?? ''}'.trim(),
      ),
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      isNewInMonth: json['is_new_in_month'] == true,
      sellerCode: '${json['seller_code'] ?? ''}'.trim(),
      sellerName: TextSanitizer.normalize(
        '${json['seller_name'] ?? ''}'.trim(),
      ),
    );
  }
}
