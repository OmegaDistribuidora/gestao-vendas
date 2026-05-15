import '../utils/text_sanitizer.dart';

class ReturnAnalysis {
  const ReturnAnalysis({
    required this.lastUpdatedAt,
    required this.totalReturnAmount,
    required this.totalClients,
    required this.totalVolume,
    required this.totalOrders,
    required this.orders,
  });

  final DateTime? lastUpdatedAt;
  final double totalReturnAmount;
  final int totalClients;
  final double totalVolume;
  final int totalOrders;
  final List<ReturnOrderSummary> orders;

  factory ReturnAnalysis.empty() {
    return const ReturnAnalysis(
      lastUpdatedAt: null,
      totalReturnAmount: 0,
      totalClients: 0,
      totalVolume: 0,
      totalOrders: 0,
      orders: <ReturnOrderSummary>[],
    );
  }

  factory ReturnAnalysis.fromJson(Map<String, dynamic> json) {
    final ordersJson = json['orders'];
    return ReturnAnalysis(
      lastUpdatedAt: _parseDate(json['last_updated_at']),
      totalReturnAmount: (json['total_return_amount'] as num?)?.toDouble() ?? 0,
      totalClients: (json['total_clients'] as num?)?.toInt() ?? 0,
      totalVolume: (json['total_volume'] as num?)?.toDouble() ?? 0,
      totalOrders: (json['total_orders'] as num?)?.toInt() ?? 0,
      orders: ordersJson is List
          ? ordersJson
                .whereType<Map>()
                .map(
                  (row) => ReturnOrderSummary.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <ReturnOrderSummary>[],
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }
}

class ReturnOrderSummary {
  const ReturnOrderSummary({
    required this.returnDate,
    required this.numped,
    required this.codcli,
    required this.clientName,
    required this.codusur,
    required this.sellerName,
    required this.returnReason,
    required this.totalValue,
    required this.totalVolume,
    required this.totalQuantity,
    required this.itemCount,
  });

  final DateTime? returnDate;
  final String numped;
  final String codcli;
  final String clientName;
  final String codusur;
  final String sellerName;
  final String returnReason;
  final double totalValue;
  final double totalVolume;
  final double totalQuantity;
  final int itemCount;

  factory ReturnOrderSummary.fromJson(Map<String, dynamic> json) {
    return ReturnOrderSummary(
      returnDate: ReturnAnalysis._parseDate(json['return_date']),
      numped: '${json['numped'] ?? ''}'.trim(),
      codcli: '${json['codcli'] ?? ''}'.trim(),
      clientName: TextSanitizer.normalize(json['client_name'] as String? ?? ''),
      codusur: '${json['codusur'] ?? ''}'.trim(),
      sellerName: TextSanitizer.normalize(json['seller_name'] as String? ?? ''),
      returnReason: TextSanitizer.normalize(
        json['return_reason'] as String? ?? '',
      ),
      totalValue: (json['total_value'] as num?)?.toDouble() ?? 0,
      totalVolume: (json['total_volume'] as num?)?.toDouble() ?? 0,
      totalQuantity: (json['total_quantity'] as num?)?.toDouble() ?? 0,
      itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class ReturnOrderDetail {
  const ReturnOrderDetail({
    required this.codprod,
    required this.productName,
    required this.itemValue,
    required this.quantity,
    required this.volume,
    required this.returnReason,
  });

  final String codprod;
  final String productName;
  final double itemValue;
  final double quantity;
  final double volume;
  final String returnReason;

  factory ReturnOrderDetail.fromJson(Map<String, dynamic> json) {
    return ReturnOrderDetail(
      codprod: '${json['codprod'] ?? ''}'.trim(),
      productName: TextSanitizer.normalize(
        json['product_name'] as String? ?? '',
      ),
      itemValue: (json['item_value'] as num?)?.toDouble() ?? 0,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      volume: (json['volume'] as num?)?.toDouble() ?? 0,
      returnReason: TextSanitizer.normalize(
        json['return_reason'] as String? ?? '',
      ),
    );
  }
}
