import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_theme.dart';
import '../core/supabase_config.dart';
import '../models/kpi_metric_source.dart';
import '../models/supplier_analysis.dart';
import '../services/app_repository.dart';

enum _SupplierPeriodPreset {
  today,
  yesterday,
  currentMonth,
  previousMonth,
  currentYear,
  custom,
}

class SupplierAnalysisScreen extends StatefulWidget {
  const SupplierAnalysisScreen({super.key});

  @override
  State<SupplierAnalysisScreen> createState() => _SupplierAnalysisScreenState();
}

class _SupplierAnalysisScreenState extends State<SupplierAnalysisScreen> {
  final AppRepository _repository = AppRepository.instance;
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final NumberFormat _decimalFormat = NumberFormat.decimalPattern('pt_BR');
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');
  final DateFormat _dateTimeFormat = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');

  bool _loading = true;
  String? _errorMessage;
  SupplierAnalysis _analysis = SupplierAnalysis.empty();
  KpiMetricSource _selectedMetricSource = KpiMetricSource.venda;
  _SupplierPeriodPreset _selectedPeriod = _SupplierPeriodPreset.today;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  @override
  void initState() {
    super.initState();
    _loadAnalysis();
  }

  DateTime get _periodStart {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case _SupplierPeriodPreset.today:
        return DateTime(now.year, now.month, now.day);
      case _SupplierPeriodPreset.yesterday:
        final yesterday = now.subtract(const Duration(days: 1));
        return DateTime(yesterday.year, yesterday.month, yesterday.day);
      case _SupplierPeriodPreset.currentMonth:
        return DateTime(now.year, now.month, 1);
      case _SupplierPeriodPreset.previousMonth:
        return DateTime(now.year, now.month - 1, 1);
      case _SupplierPeriodPreset.currentYear:
        return DateTime(now.year, 1, 1);
      case _SupplierPeriodPreset.custom:
        final customStart = _customStartDate ?? now;
        return DateTime(customStart.year, customStart.month, customStart.day);
    }
  }

  DateTime get _periodEnd {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case _SupplierPeriodPreset.today:
        return DateTime(now.year, now.month, now.day, 23, 59, 59);
      case _SupplierPeriodPreset.yesterday:
        final yesterday = now.subtract(const Duration(days: 1));
        return DateTime(
          yesterday.year,
          yesterday.month,
          yesterday.day,
          23,
          59,
          59,
        );
      case _SupplierPeriodPreset.currentMonth:
        return DateTime(now.year, now.month, now.day, 23, 59, 59);
      case _SupplierPeriodPreset.previousMonth:
        return DateTime(now.year, now.month, 0, 23, 59, 59);
      case _SupplierPeriodPreset.currentYear:
        return DateTime(now.year, now.month, now.day, 23, 59, 59);
      case _SupplierPeriodPreset.custom:
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
      case _SupplierPeriodPreset.today:
        return 'Hoje';
      case _SupplierPeriodPreset.yesterday:
        return 'Ontem';
      case _SupplierPeriodPreset.currentMonth:
        return 'Mês atual';
      case _SupplierPeriodPreset.previousMonth:
        return 'Mês anterior';
      case _SupplierPeriodPreset.currentYear:
        return 'Ano atual';
      case _SupplierPeriodPreset.custom:
        return '${_dateFormat.format(_periodStart)} até ${_dateFormat.format(_periodEnd)}';
    }
  }

  Future<void> _loadAnalysis() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final analysis = await _repository.getSupplierAnalysis(
        start: _periodStart,
        end: _periodEnd,
        metricSource: _selectedMetricSource,
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
        _errorMessage = 'Falha ao carregar a análise por fornecedor.\n$error';
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

  Future<void> _handlePeriodChanged(_SupplierPeriodPreset? preset) async {
    if (preset == null) {
      return;
    }

    setState(() {
      _selectedPeriod = preset;
      if (preset == _SupplierPeriodPreset.custom) {
        final today = DateTime.now();
        _customStartDate ??= DateTime(today.year, today.month, today.day);
        _customEndDate ??= _customStartDate;
      }
    });

    await _loadAnalysis();
  }

  Future<void> _handleMetricSourceChanged(KpiMetricSource? metricSource) async {
    if (metricSource == null || metricSource == _selectedMetricSource) {
      return;
    }

    setState(() {
      _selectedMetricSource = metricSource;
    });
    await _loadAnalysis();
  }

  String _formatCurrency(double value) => _currencyFormat.format(value);

  String _formatVolume(double value) => _decimalFormat.format(
    double.parse(value.toStringAsFixed(1)),
  );

  String _supplierLogoUrl(String supplierCode) {
    return '${SupabaseConfig.url}/storage/v1/object/public/fornecedores-logos/$supplierCode.png';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Análise por Fornecedor')),
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
                    _ErrorCard(
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
                              'Resumo por fornecedor',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Compare o desempenho dos fornecedores no período selecionado, respeitando o escopo do seu perfil.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: const Color(0xFF5E6A7C)),
                            ),
                            const SizedBox(height: 18),
                            DropdownButtonFormField<KpiMetricSource>(
                              initialValue: _selectedMetricSource,
                              decoration: const InputDecoration(
                                labelText: 'Fonte dos indicadores',
                                prefixIcon: Icon(Icons.tune_outlined),
                              ),
                              items: KpiMetricSource.values
                                  .map(
                                    (source) => DropdownMenuItem(
                                      value: source,
                                      child: Text(source.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _handleMetricSourceChanged,
                            ),
                            const SizedBox(height: 14),
                            DropdownButtonFormField<_SupplierPeriodPreset>(
                              initialValue: _selectedPeriod,
                              decoration: const InputDecoration(
                                labelText: 'Período',
                                prefixIcon: Icon(Icons.date_range_outlined),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: _SupplierPeriodPreset.today,
                                  child: Text('Hoje'),
                                ),
                                DropdownMenuItem(
                                  value: _SupplierPeriodPreset.yesterday,
                                  child: Text('Ontem'),
                                ),
                                DropdownMenuItem(
                                  value: _SupplierPeriodPreset.currentMonth,
                                  child: Text('Mês atual'),
                                ),
                                DropdownMenuItem(
                                  value: _SupplierPeriodPreset.previousMonth,
                                  child: Text('Mês anterior'),
                                ),
                                DropdownMenuItem(
                                  value: _SupplierPeriodPreset.currentYear,
                                  child: Text('Ano atual'),
                                ),
                                DropdownMenuItem(
                                  value: _SupplierPeriodPreset.custom,
                                  child: Text('Personalizado'),
                                ),
                              ],
                              onChanged: _handlePeriodChanged,
                            ),
                            if (_selectedPeriod == _SupplierPeriodPreset.custom) ...[
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _pickCustomDate(isStart: true),
                                    icon: const Icon(Icons.event_outlined),
                                    label: Text(_dateFormat.format(_periodStart)),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _pickCustomDate(isStart: false),
                                    icon: const Icon(Icons.event_busy_outlined),
                                    label: Text(_dateFormat.format(_periodEnd)),
                                  ),
                                ],
                              ),
                            ],
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
                            Row(
                              children: [
                                const Icon(
                                  Icons.insights_outlined,
                                  color: primaryColor,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '${_selectedMetricSource.label} • $_periodDescription',
                                    style: Theme.of(context).textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _analysis.lastUpdatedAt != null
                                  ? 'Última atualização: ${_dateTimeFormat.format(_analysis.lastUpdatedAt!)}'
                                  : 'Última atualização: ainda não disponível',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_analysis.suppliers.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Nenhum fornecedor com dados no período selecionado.',
                          ),
                        ),
                      )
                    else
                      ..._analysis.suppliers.map(
                        (supplier) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _SupplierCard(
                            supplier: supplier,
                            formatCurrency: _formatCurrency,
                            formatVolume: _formatVolume,
                            logoUrl: _supplierLogoUrl(supplier.code),
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

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({
    required this.supplier,
    required this.formatCurrency,
    required this.formatVolume,
    required this.logoUrl,
  });

  final SupplierAnalysisItem supplier;
  final String Function(double value) formatCurrency;
  final String Function(double value) formatVolume;
  final String logoUrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    logoUrl,
                    width: 46,
                    height: 46,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7EBFF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.inventory_2_outlined,
                        color: primaryColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    supplier.supplierName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MiniMetricTile(
                  title: 'Financeiro Bruto',
                  value: formatCurrency(supplier.grossAmount),
                ),
                _MiniMetricTile(
                  title: 'Volume Bruto',
                  value: formatVolume(supplier.grossVolume),
                ),
                _MiniMetricTile(
                  title: 'Pedidos',
                  value: '${supplier.grossOrders}',
                ),
                _MiniMetricTile(
                  title: 'Positivação Bruta',
                  value: '${supplier.grossPositivation}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniMetricTile extends StatelessWidget {
  const _MiniMetricTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
          const SizedBox(height: 6),
          SizedBox(
            height: 28,
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

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

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
            const Icon(
              Icons.error_outline,
              size: 48,
              color: primaryColor,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
            ),
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
