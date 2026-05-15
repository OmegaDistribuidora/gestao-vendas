import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  final DateFormat _dateTimeFormat = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');

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

  String _formatNumber(double value) =>
      _decimalFormat.format(double.parse(value.toStringAsFixed(1)));

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
                                            value: _formatNumber(
                                              item.quantity,
                                            ),
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
                            if (_selectedPeriod == _ReturnPeriodPreset.custom) ...[
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
                                    icon: const Icon(
                                      Icons.event_busy_outlined,
                                    ),
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
                            const SizedBox(height: 10),
                            Text(
                              _analysis.lastUpdatedAt != null
                                  ? 'Última atualização: ${_dateTimeFormat.format(_analysis.lastUpdatedAt!)}'
                                  : 'Última atualização: ainda não disponível',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _SummaryMetricCard(
                                  title: 'Financeiro devolvido',
                                  value: _formatCurrency(
                                    _analysis.totalReturnAmount,
                                  ),
                                ),
                                _SummaryMetricCard(
                                  title: 'Clientes com devolução',
                                  value: '${_analysis.totalClients}',
                                ),
                                _SummaryMetricCard(
                                  title: 'Volume devolvido',
                                  value: _formatNumber(_analysis.totalVolume),
                                ),
                                _SummaryMetricCard(
                                  title: 'Pedidos devolvidos',
                                  value: '${_analysis.totalOrders}',
                                ),
                              ],
                            ),
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
                      ..._filteredOrders.map(
                        (order) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              leading: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFDECEC),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.assignment_return_outlined,
                                  color: primaryColor,
                                ),
                              ),
                              title: Text(
                                '${order.codcli} • ${order.clientName}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Pedido ${order.numped}'),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        order.sellerName.trim().isNotEmpty
                                            ? 'Vendedor: ${order.codusur} • ${order.sellerName}'
                                            : 'Vendedor: ${order.codusur}',
                                      ),
                                    ),
                                    if (order.returnReason.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          'Motivo: ${order.returnReason}',
                                        ),
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Valor: ${_formatCurrency(order.totalValue)} • Volume: ${_formatNumber(order.totalVolume)} • Itens: ${order.itemCount}',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _showOrderDetails(order),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SummaryMetricCard extends StatelessWidget {
  const _SummaryMetricCard({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 154,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E6F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF5E6A7C),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 30,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
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
