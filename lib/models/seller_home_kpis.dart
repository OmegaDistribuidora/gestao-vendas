class SellerHomeKpis {
  const SellerHomeKpis({
    required this.totalVenda,
    required this.totalVolume,
    required this.totalPedidos,
    required this.totalPositivacao,
  });

  final double totalVenda;
  final double totalVolume;
  final int totalPedidos;
  final int totalPositivacao;

  factory SellerHomeKpis.empty() {
    return const SellerHomeKpis(
      totalVenda: 0,
      totalVolume: 0,
      totalPedidos: 0,
      totalPositivacao: 0,
    );
  }

  factory SellerHomeKpis.fromJson(Map<String, dynamic> json) {
    return SellerHomeKpis(
      totalVenda: (json['venda_hoje'] as num?)?.toDouble() ?? 0,
      totalVolume: (json['volume_hoje'] as num?)?.toDouble() ?? 0,
      totalPedidos: (json['pedidos_hoje'] as num?)?.toInt() ?? 0,
      totalPositivacao: (json['positivacao_hoje'] as num?)?.toInt() ?? 0,
    );
  }
}
