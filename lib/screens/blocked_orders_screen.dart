import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_theme.dart';
import '../models/app_profile.dart';
import '../models/blocked_orders_overview.dart';
import '../services/app_repository.dart';

class BlockedOrdersScreen extends StatefulWidget {
  const BlockedOrdersScreen({super.key});

  @override
  State<BlockedOrdersScreen> createState() => _BlockedOrdersScreenState();
}

class _BlockedOrdersScreenState extends State<BlockedOrdersScreen> {
  final AppRepository _repository = AppRepository.instance;
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');
  final DateFormat _dateTimeFormat = DateFormat(
    "dd/MM/yyyy 'as' HH:mm",
    'pt_BR',
  );

  bool _loading = true;
  String? _errorMessage;
  String _searchTerm = '';
  BlockedOrdersOverview _overview = BlockedOrdersOverview.empty();

  @override
  void initState() {
    super.initState();
    _loadOverview();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<BlockedOrderEntry> get _filteredOrders {
    final term = _searchTerm.trim().toLowerCase();
    if (term.isEmpty) {
      return _overview.orders;
    }

    return _overview.orders.where((order) {
      return order.numped.toLowerCase().contains(term) ||
          order.codcli.toLowerCase().contains(term) ||
          order.clientName.toLowerCase().contains(term) ||
          order.codusur.toLowerCase().contains(term) ||
          order.sellerName.toLowerCase().contains(term) ||
          order.motivoBloqueio.toLowerCase().contains(term) ||
          order.items.any(
            (product) =>
                product.codprod.toLowerCase().contains(term) ||
                product.productName.toLowerCase().contains(term),
          );
    }).toList();
  }

  Future<void> _loadOverview() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final overview = await _repository.getBlockedOrdersOverview();
      if (!mounted) {
        return;
      }
      setState(() {
        _overview = overview;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = 'Falha ao carregar os pedidos bloqueados.\n$error';
      });
    }
  }

  String _screenDescription() {
    switch (_overview.profileSlug) {
      case AppProfile.sellerSlug:
        return 'Visao consolidada dos seus pedidos bloqueados.';
      case AppProfile.supervisorSlug:
        return 'Visao consolidada dos pedidos bloqueados da sua supervisao.';
      case AppProfile.coordinatorSlug:
        return 'Visao consolidada da sua coordenacao.';
      default:
        return 'Visao consolidada da operacao.';
    }
  }

  String _formatCurrency(double value) => _currencyFormat.format(value);

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '--';
    }
    return _dateFormat.format(value);
  }

  Color _typeColor(BlockedOrderEntry order) {
    if (order.isBonus) {
      return const Color(0xFF6D28D9);
    }
    return const Color(0xFF1D4ED8);
  }

  Color _typeBackgroundColor(BlockedOrderEntry order) {
    if (order.isBonus) {
      return const Color(0xFFF2EAFE);
    }
    return const Color(0xFFE8EEFF);
  }

  IconData _orderTypeIcon(BlockedOrderEntry order) {
    if (order.isBonus) {
      return Icons.card_giftcard;
    }
    return Icons.monetization_on_outlined;
  }

  Widget _buildOverviewHeroCard() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFFFFFF), Color(0xFFF5F8FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8EEFF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.receipt_long_outlined,
                      color: primaryColor,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Pedidos Bloqueados',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _screenDescription(),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF5E6A7C),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 124,
              height: 124,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0xFFE7EEFF), Color(0xFFF8FAFF)],
                ),
              ),
              child: const Icon(
                Icons.admin_panel_settings_outlined,
                color: primaryColor,
                size: 68,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastUpdateCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            const Icon(Icons.schedule_outlined, color: primaryColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _overview.lastUpdatedAt != null
                    ? 'Ultima atualizacao: ${_dateTimeFormat.format(_overview.lastUpdatedAt!)}'
                    : 'Ultima atualizacao: ainda nao disponivel',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accentColor,
    required Color accentBackgroundColor,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF5E6A7C),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 40,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: accentBackgroundColor,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: accentColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsSection() {
    return Column(
      children: [
        _buildMetricCard(
          title: 'Venda bloqueada',
          value: _formatCurrency(_overview.salesBlockedAmount),
          icon: Icons.monetization_on_outlined,
          accentColor: const Color(0xFF16924C),
          accentBackgroundColor: const Color(0xFFE7F6EC),
        ),
        const SizedBox(height: 12),
        _buildMetricCard(
          title: 'Pedidos de venda',
          value: '${_overview.salesBlockedOrders}',
          icon: Icons.shopping_cart_outlined,
          accentColor: const Color(0xFF1D4ED8),
          accentBackgroundColor: const Color(0xFFE8EEFF),
        ),
        const SizedBox(height: 12),
        _buildMetricCard(
          title: 'Bonificação bloqueada',
          value: _formatCurrency(_overview.bonusBlockedAmount),
          icon: Icons.card_giftcard,
          accentColor: const Color(0xFF6D28D9),
          accentBackgroundColor: const Color(0xFFF2EAFE),
        ),
        const SizedBox(height: 12),
        _buildMetricCard(
          title: 'Pedidos de bonificação',
          value: '${_overview.bonusBlockedOrders}',
          icon: Icons.inventory_2_outlined,
          accentColor: const Color(0xFFFF7A00),
          accentBackgroundColor: const Color(0xFFFFF0DD),
        ),
        const SizedBox(height: 12),
        _buildMetricCard(
          title: 'Total bloqueado',
          value: _formatCurrency(_overview.totalBlockedAmount),
          icon: Icons.attach_money_outlined,
          accentColor: const Color(0xFF0F766E),
          accentBackgroundColor: const Color(0xFFE7F6F3),
        ),
        const SizedBox(height: 12),
        _buildMetricCard(
          title: 'Total de pedidos',
          value: '${_overview.totalBlockedOrders}',
          icon: Icons.lock_outline,
          accentColor: primaryColor,
          accentBackgroundColor: const Color(0xFFE8EEFF),
        ),
      ],
    );
  }

  Widget _buildProductDetail(BlockedOrderItem product) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E6F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${product.codprod} - ${product.productName}',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              Chip(
                label: Text(_formatCurrency(product.itemValue)),
                avatar: const Icon(Icons.attach_money_outlined, size: 18),
              ),
              Chip(
                label: Text('Qtd. ${_formatNumber(product.quantity)}'),
                avatar: const Icon(Icons.inventory_2_outlined, size: 18),
              ),
              Chip(
                label: Text('Vol. ${_formatNumber(product.volume)}'),
                avatar: const Icon(Icons.widgets_outlined, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showOrderProducts(BlockedOrderEntry order) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.82,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${order.codcli} - ${order.clientName}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  order.isBonus
                      ? 'Bonificação ${order.numped}'
                      : 'Pedido ${order.numped}',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF5E6A7C),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  order.sellerName.trim().isNotEmpty
                      ? 'Vendedor: ${order.codusur} - ${order.sellerName}'
                      : 'Vendedor: ${order.codusur}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5E6A7C),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Motivo: ${order.motivoBloqueio.isEmpty ? 'Nao informado' : order.motivoBloqueio}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(_formatCurrency(order.valorTotalPedido)),
                      avatar: const Icon(Icons.attach_money_outlined, size: 18),
                    ),
                    Chip(
                      label: Text('${order.itemCount} produto(s)'),
                      avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                    ),
                    Chip(
                      label: Text('Qtd. ${_formatNumber(order.totalQuantity)}'),
                      avatar: const Icon(Icons.layers_outlined, size: 18),
                    ),
                    Chip(
                      label: Text('Vol. ${_formatNumber(order.totalVolume)}'),
                      avatar: const Icon(Icons.widgets_outlined, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: order.items.isEmpty
                      ? const Center(
                          child: Text(
                            'Nenhum produto detalhado para este pedido.',
                          ),
                        )
                      : ListView.separated(
                          itemCount: order.items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            return _buildProductDetail(order.items[index]);
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrderRow(BlockedOrderEntry order) {
    final typeColor = _typeColor(order);
    final typeBackgroundColor = _typeBackgroundColor(order);

    return InkWell(
      onTap: () => _showOrderProducts(order),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: typeBackgroundColor,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(_orderTypeIcon(order), color: typeColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.isBonus
                        ? 'Bonificação #${order.numped}'
                        : 'Pedido #${order.numped}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    order.motivoBloqueio.isEmpty
                        ? 'Motivo do bloqueio nao informado.'
                        : order.motivoBloqueio,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF5E6A7C),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatDate(order.dataPedido),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5E6A7C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatCurrency(order.valorTotalPedido),
                  style: TextStyle(
                    color: typeColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF8A94A6)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos Bloqueados'),
        actions: [
          IconButton(
            onPressed: _loadOverview,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: primaryColor,
          onRefresh: _loadOverview,
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: primaryColor),
                )
              : _errorMessage != null
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: [
                    _buildOverviewHeroCard(),
                    const SizedBox(height: 12),
                    _buildLastUpdateCard(),
                    const SizedBox(height: 12),
                    _buildMetricsSection(),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        labelText:
                            'Buscar por pedido, cliente, vendedor, motivo ou produto',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchTerm = value;
                        });
                      },
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Pedidos recentes',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          '${_filteredOrders.length} pedido(s)',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF5E6A7C)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: _filteredOrders.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                'Nenhum pedido bloqueado encontrado.',
                              ),
                            )
                          : Column(
                              children: [
                                for (
                                  var index = 0;
                                  index < _filteredOrders.length;
                                  index++
                                ) ...[
                                  _buildOrderRow(_filteredOrders[index]),
                                  if (index != _filteredOrders.length - 1)
                                    const Divider(
                                      height: 1,
                                      indent: 18,
                                      endIndent: 18,
                                    ),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
