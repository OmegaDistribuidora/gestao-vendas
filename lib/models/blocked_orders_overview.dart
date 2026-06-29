import '../utils/text_sanitizer.dart';

class BlockedOrdersOverview {
  const BlockedOrdersOverview({
    required this.profileSlug,
    required this.totalBlockedAmount,
    required this.totalBlockedOrders,
    required this.salesBlockedAmount,
    required this.salesBlockedOrders,
    required this.bonusBlockedAmount,
    required this.bonusBlockedOrders,
    required this.orders,
    this.lastUpdatedAt,
  });

  final String profileSlug;
  final double totalBlockedAmount;
  final int totalBlockedOrders;
  final double salesBlockedAmount;
  final int salesBlockedOrders;
  final double bonusBlockedAmount;
  final int bonusBlockedOrders;
  final List<BlockedOrderEntry> orders;
  final DateTime? lastUpdatedAt;

  factory BlockedOrdersOverview.empty() {
    return const BlockedOrdersOverview(
      profileSlug: '',
      totalBlockedAmount: 0,
      totalBlockedOrders: 0,
      salesBlockedAmount: 0,
      salesBlockedOrders: 0,
      bonusBlockedAmount: 0,
      bonusBlockedOrders: 0,
      orders: <BlockedOrderEntry>[],
      lastUpdatedAt: null,
    );
  }

  factory BlockedOrdersOverview.fromJson(Map<String, dynamic> json) {
    final rawOrders = json['orders'];
    return BlockedOrdersOverview(
      profileSlug: '${json['profile_slug'] ?? ''}',
      totalBlockedAmount: _toDouble(json['total_blocked_amount']),
      totalBlockedOrders: _toInt(json['total_blocked_orders']),
      salesBlockedAmount: _toDouble(json['sales_blocked_amount']),
      salesBlockedOrders: _toInt(json['sales_blocked_orders']),
      bonusBlockedAmount: _toDouble(json['bonus_blocked_amount']),
      bonusBlockedOrders: _toInt(json['bonus_blocked_orders']),
      orders: rawOrders is List
          ? rawOrders
                .whereType<Map>()
                .map(
                  (row) => BlockedOrderEntry.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <BlockedOrderEntry>[],
      lastUpdatedAt: _parseDateTime(json['last_updated_at']),
    );
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

  static int _toInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }
}

class BlockedOrderEntry {
  const BlockedOrderEntry({
    required this.numped,
    required this.codPosicao,
    required this.posicaoPedido,
    required this.dataPedido,
    required this.codcli,
    required this.clientName,
    required this.codusur,
    required this.sellerName,
    required this.codsupervisor,
    required this.supervisorName,
    required this.codgerente,
    required this.tipoVenda,
    required this.motivoBloqueio,
    required this.valorTotalPedido,
    required this.totalQuantity,
    required this.totalVolume,
    required this.itemCount,
    required this.items,
  });

  final String numped;
  final String codPosicao;
  final String posicaoPedido;
  final DateTime? dataPedido;
  final String codcli;
  final String clientName;
  final String codusur;
  final String sellerName;
  final String codsupervisor;
  final String supervisorName;
  final String codgerente;
  final int tipoVenda;
  final String motivoBloqueio;
  final double valorTotalPedido;
  final double totalQuantity;
  final double totalVolume;
  final int itemCount;
  final List<BlockedOrderItem> items;

  bool get isBonus => tipoVenda == 5;
  bool get isSale => tipoVenda == 1;

  String get tipoVendaLabel {
    if (isBonus) {
      return 'Bonificação';
    }
    if (isSale) {
      return 'Venda';
    }
    return 'Outros';
  }

  factory BlockedOrderEntry.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return BlockedOrderEntry(
      numped: '${json['numped'] ?? ''}'.trim(),
      codPosicao: '${json['cod_posicao'] ?? ''}'.trim(),
      posicaoPedido: TextSanitizer.normalize(
        json['posicao_pedido'] as String? ?? '',
      ),
      dataPedido: BlockedOrdersOverview._parseDateTime(json['data_pedido']),
      codcli: '${json['codcli'] ?? ''}'.trim(),
      clientName: TextSanitizer.normalize(json['client_name'] as String? ?? ''),
      codusur: '${json['codusur'] ?? ''}'.trim(),
      sellerName: TextSanitizer.normalize(json['seller_name'] as String? ?? ''),
      codsupervisor: '${json['codsupervisor'] ?? ''}'.trim(),
      supervisorName: TextSanitizer.toNameCase(
        json['supervisor_name'] as String? ?? '',
      ),
      codgerente: '${json['codgerente'] ?? ''}'.trim(),
      tipoVenda: BlockedOrdersOverview._toInt(json['tipo_venda']),
      motivoBloqueio: TextSanitizer.normalize(
        json['motivo_bloqueio'] as String? ?? '',
      ),
      valorTotalPedido: BlockedOrdersOverview._toDouble(
        json['valor_total_pedido'],
      ),
      totalQuantity: BlockedOrdersOverview._toDouble(json['total_quantity']),
      totalVolume: BlockedOrdersOverview._toDouble(json['total_volume']),
      itemCount: BlockedOrdersOverview._toInt(json['item_count']),
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (row) => BlockedOrderItem.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <BlockedOrderItem>[],
    );
  }
}

class BlockedOrderItem {
  const BlockedOrderItem({
    required this.codprod,
    required this.productName,
    required this.quantity,
    required this.volume,
    required this.itemValue,
  });

  final String codprod;
  final String productName;
  final double quantity;
  final double volume;
  final double itemValue;

  factory BlockedOrderItem.fromJson(Map<String, dynamic> json) {
    return BlockedOrderItem(
      codprod: '${json['codprod'] ?? ''}'.trim(),
      productName: TextSanitizer.normalize(
        json['product_name'] as String? ?? '',
      ),
      quantity: BlockedOrdersOverview._toDouble(json['quantity']),
      volume: BlockedOrdersOverview._toDouble(json['volume']),
      itemValue: BlockedOrdersOverview._toDouble(json['item_value']),
    );
  }
}
