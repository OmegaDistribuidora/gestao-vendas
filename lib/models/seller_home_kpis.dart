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
      totalVenda: (json['total_venda'] as num?)?.toDouble() ?? 0,
      totalVolume: (json['total_volume'] as num?)?.toDouble() ?? 0,
      totalPedidos: (json['total_pedidos'] as num?)?.toInt() ?? 0,
      totalPositivacao: (json['total_positivacao'] as num?)?.toInt() ?? 0,
    );
  }
}
