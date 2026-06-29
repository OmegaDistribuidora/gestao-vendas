import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../components/compact_metric_tile.dart';
import '../core/app_theme.dart';
import '../models/return_analysis.dart';
import '../services/app_repository.dart';

enum _ReturnPeriodPreset {
  today,
  yesterday,
  currentMonth,
  previousMonth,
  currentYear,
  custom,
}

class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  final AppRepository _repository = AppRepository.instance;
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final NumberFormat _decimalFormat = NumberFormat.decimalPattern('pt_BR');
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');
  final DateFormat _dateTimeFormat = DateFormat(
    "dd/MM/yyyy 'às' HH:mm",
    'pt_BR',
  );

  bool _loading = true;
  String? _errorMessage;
  ReturnAnalysis _analysis = ReturnAnalysis.empty();
  _ReturnPeriodPreset _selectedPeriod = _ReturnPeriodPreset.today;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _loadAnalysis();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime get _periodStart {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case _ReturnPeriodPreset.today:
        return DateTime(now.year, now.month, now.day);
      case _ReturnPeriodPreset.yesterday:
        final yesterday = now.subtract(const Duration(days: 1));
        return DateTime(yesterday.year, yesterday.month, yesterday.day);
      case _ReturnPeriodPreset.currentMonth:
        return DateTime(now.year, now.month, 1);
      case _ReturnPeriodPreset.previousMonth:
        return DateTime(now.year, now.month - 1, 1);
      case _ReturnPeriodPreset.currentYear:
        return DateTime(now.year, 1, 1);
      case _ReturnPeriodPreset.custom:
        final customStart = _customStartDate ?? now;
        return DateTime(customStart.year, customStart.month, customStart.day);
    }
  }

  DateTime get _periodEnd {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case _ReturnPeriodPreset.today:
        return DateTime(now.year, now.month, now.day, 23, 59, 59);
      case _ReturnPeriodPreset.yesterday:
        final yesterday = now.subtract(const Duration(days: 1));
        return DateTime(
          yesterday.year,
          yesterday.month,
          yesterday.day,
          23,
          59,
          59,
        );
      case _ReturnPeriodPreset.currentMonth:
        return DateTime(now.year, now.month, now.day, 23, 59, 59);
      case _ReturnPeriodPreset.previousMonth:
        return DateTime(now.year, now.month, 0, 23, 59, 59);
      case _ReturnPeriodPreset.currentYear:
        return DateTime(now.year, now.month, now.day, 23, 59, 59);
      case _ReturnPeriodPreset.custom:
        final customEnd = _customEndDate ?? _customStartDate ?? now;
        return DateTime(
          customEnd.year,
          customEnd.month,
          customEnd.day,
          23,
          59,
          59,
        );
    }
  }

  String get _periodDescription {
    switch (_selectedPeriod) {
      case _ReturnPeriodPreset.today:
        return 'Hoje';
      case _ReturnPeriodPreset.yesterday:
        return 'Ontem';
      case _ReturnPeriodPreset.currentMonth:
        return 'Mês atual';
      case _ReturnPeriodPreset.previousMonth:
        return 'Mês anterior';
      case _ReturnPeriodPreset.currentYear:
        return 'Ano atual';
      case _ReturnPeriodPreset.custom:
        return '${_dateFormat.format(_periodStart)} até ${_dateFormat.format(_periodEnd)}';
    }
  }

  List<ReturnOrderSummary> get _filteredOrders {
    final term = _searchTerm.trim().toLowerCase();
    if (term.isEmpty) {
      return _analysis.orders;
    }

    return _analysis.orders.where((order) {
      return order.numped.toLowerCase().contains(term) ||
          order.codcli.toLowerCase().contains(term) ||
          order.clientName.toLowerCase().contains(term);
    }).toList();
  }

  Future<void> _loadAnalysis() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final analysis = await _repository.getReturnAnalysis(
        start: _periodStart,
        end: _periodEnd,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _analysis = analysis;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = 'Falha ao carregar as devoluções.\n$error';
      });
    }
  }

  Future<void> _pickCustomDate({required bool isStart}) async {
    final initialDate = isStart
        ? (_customStartDate ?? DateTime.now())
        : (_customEndDate ?? _customStartDate ?? DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime.now(),
      locale: const Locale('pt', 'BR'),
    );

    if (picked == null) {
      return;
    }

    setState(() {
      if (isStart) {
        _customStartDate = picked;
        if (_customEndDate != null && _customEndDate!.isBefore(picked)) {
          _customEndDate = picked;
        }
      } else {
        _customEndDate = picked;
        if (_customStartDate != null && _customStartDate!.isAfter(picked)) {
          _customStartDate = picked;
        }
      }
    });

    await _loadAnalysis();
  }

  Future<void> _handlePeriodChanged(_ReturnPeriodPreset? preset) async {
    if (preset == null) {
      return;
    }

    setState(() {
      _selectedPeriod = preset;
      if (preset == _ReturnPeriodPreset.custom) {
        final today = DateTime.now();
        _customStartDate ??= DateTime(today.year, today.month, today.day);
        _customEndDate ??= _customStartDate;
      }
    });

    await _loadAnalysis();
  }

  String _formatCurrency(double value) => _currencyFormat.format(value);

  String _formatMetricCurrency(double value) {
    return _formatCurrency(value);
  }

  String _formatNumber(double value) =>
      _decimalFormat.format(double.parse(value.toStringAsFixed(1)));

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '--';
    }
    return _dateFormat.format(value);
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accentColor,
    required Color accentBackgroundColor,
  }) {
    return CompactMetricTile(
      title: title,
      value: value,
      icon: icon,
      accentColor: accentColor,
      accentBackgroundColor: accentBackgroundColor,
    );
  }

  Widget _buildMetricsSection() {
    final metrics = [
      _buildMetricCard(
        title: 'Financeiro',
        value: _formatMetricCurrency(_analysis.totalReturnAmount),
        icon: Icons.attach_money_outlined,
        accentColor: const Color(0xFFB42318),
        accentBackgroundColor: const Color(0xFFFDECEC),
      ),
      _buildMetricCard(
        title: 'Clientes',
        value: '${_analysis.totalClients}',
        icon: Icons.people_outline,
        accentColor: const Color(0xFF1D4ED8),
        accentBackgroundColor: const Color(0xFFE8EEFF),
      ),
      _buildMetricCard(
        title: 'Volume',
        value: _formatNumber(_analysis.totalVolume),
        icon: Icons.widgets_outlined,
        accentColor: const Color(0xFF7C3AED),
        accentBackgroundColor: const Color(0xFFF2EAFE),
      ),
      _buildMetricCard(
        title: 'Pedidos',
        value: '${_analysis.totalOrders}',
        icon: Icons.assignment_return_outlined,
        accentColor: const Color(0xFFFF7A00),
        accentBackgroundColor: const Color(0xFFFFF0DD),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 104,
      ),
      itemCount: metrics.length,
      itemBuilder: (context, index) => metrics[index],
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
                _analysis.lastUpdatedAt != null
                    ? 'Última atualização: ${_dateTimeFormat.format(_analysis.lastUpdatedAt!)}'
                    : 'Última atualização: ainda não disponível',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOrderDetails(ReturnOrderSummary order) async {
    if (order.returnDate == null) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.82,
          child: FutureBuilder<List<ReturnOrderDetail>>(
            future: _repository.getReturnOrderDetails(
              returnDate: order.returnDate!,
              orderNumber: order.numped,
            ),
            builder: (context, snapshot) {
              final details = snapshot.data ?? const <ReturnOrderDetail>[];
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${order.codcli} • ${order.clientName}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pedido ${order.numped}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF5E6A7C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      order.sellerName.trim().isNotEmpty
                          ? 'Vendedor: ${order.codusur} • ${order.sellerName}'
                          : 'Vendedor: ${order.codusur}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF5E6A7C),
                      ),
                    ),
                    if (order.returnReason.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Motivo: ${order.returnReason}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Expanded(
                      child: snapshot.connectionState == ConnectionState.waiting
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: primaryColor,
                              ),
                            )
                          : details.isEmpty
                          ? const Center(
                              child: Text(
                                'Nenhum item detalhado para esta devolução.',
                              ),
                            )
                          : ListView.separated(
                              itemCount: details.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = details[index];
                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF7F9FF),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFFE1E6F5),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${item.codprod} • ${item.productName}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 8,
                                        children: [
                                          _DetailChip(
                                            label: 'Valor',
                                            value: _formatCurrency(
                                              item.itemValue,
                                            ),
                                          ),
                                          _DetailChip(
                                            label: 'Quantidade',
                                            value: _formatNumber(item.quantity),
                                          ),
                                          _DetailChip(
                                            label: 'Volume',
                                            value: _formatNumber(item.volume),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildOrderRow(ReturnOrderSummary order) {
    return InkWell(
      onTap: () => _showOrderDetails(order),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFFDECEC),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.assignment_return_outlined,
                color: primaryColor,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pedido #${order.numped}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    order.returnReason.isEmpty
                        ? '${order.codcli} - ${order.clientName}'
                        : order.returnReason,
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
                  order.returnDate != null
                      ? _formatDate(order.returnDate)
                      : '--',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5E6A7C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatCurrency(order.totalValue),
                  style: const TextStyle(
                    color: primaryColor,
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
      appBar: AppBar(title: const Text('Devoluções')),
      body: SafeArea(
        child: RefreshIndicator(
          color: primaryColor,
          onRefresh: _loadAnalysis,
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: primaryColor),
                )
              : _errorMessage != null
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: [
                    _ReturnErrorCard(
                      message: _errorMessage!,
                      onRetry: _loadAnalysis,
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Devoluções por pedido',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Acompanhe os pedidos devolvidos, clientes, vendedores, motivos e itens do período selecionado.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: const Color(0xFF5E6A7C)),
                            ),
                            const SizedBox(height: 18),
                            DropdownButtonFormField<_ReturnPeriodPreset>(
                              initialValue: _selectedPeriod,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Período',
                                prefixIcon: Icon(Icons.date_range_outlined),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: _ReturnPeriodPreset.today,
                                  child: Text('Hoje'),
                                ),
                                DropdownMenuItem(
                                  value: _ReturnPeriodPreset.yesterday,
                                  child: Text('Ontem'),
                                ),
                                DropdownMenuItem(
                                  value: _ReturnPeriodPreset.currentMonth,
                                  child: Text('Mês atual'),
                                ),
                                DropdownMenuItem(
                                  value: _ReturnPeriodPreset.previousMonth,
                                  child: Text('Mês anterior'),
                                ),
                                DropdownMenuItem(
                                  value: _ReturnPeriodPreset.currentYear,
                                  child: Text('Ano atual'),
                                ),
                                DropdownMenuItem(
                                  value: _ReturnPeriodPreset.custom,
                                  child: Text('Personalizado'),
                                ),
                              ],
                              onChanged: _handlePeriodChanged,
                            ),
                            if (_selectedPeriod ==
                                _ReturnPeriodPreset.custom) ...[
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _pickCustomDate(isStart: true),
                                    icon: const Icon(Icons.event_outlined),
                                    label: Text(
                                      _dateFormat.format(_periodStart),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _pickCustomDate(isStart: false),
                                    icon: const Icon(Icons.event_busy_outlined),
                                    label: Text(_dateFormat.format(_periodEnd)),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _searchController,
                              textInputAction: TextInputAction.search,
                              decoration: const InputDecoration(
                                labelText: 'Buscar devolução',
                                hintText: 'Pedido, código ou nome do cliente',
                                prefixIcon: Icon(Icons.search),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _searchTerm = value;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Resumo • $_periodDescription',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 16),
                            _buildMetricsSection(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_filteredOrders.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Nenhuma devolução encontrada para o filtro informado.',
                          ),
                        ),
                      )
                    else
                      Card(
                        child: Column(
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
                    const SizedBox(height: 8),
                    _buildLastUpdateCard(),
                  ],
                ),
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE1E6F5)),
      ),
      child: Text('$label: $value'),
    );
  }
}

class _ReturnErrorCard extends StatelessWidget {
  const _ReturnErrorCard({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: primaryColor),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
