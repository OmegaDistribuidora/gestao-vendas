import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_theme.dart';
import '../core/supabase_config.dart';
import '../models/app_profile.dart';
import '../models/kpi_metric_source.dart';
import '../models/performance_overview.dart';
import '../services/app_repository.dart';
import '../utils/business_day_projection.dart';

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  final AppRepository _repository = AppRepository.instance;
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final NumberFormat _compactCurrencyFormat = NumberFormat.compactCurrency(
    locale: 'pt_BR',
    symbol: 'R\$',
    decimalDigits: 1,
  );
  final NumberFormat _integerFormat = NumberFormat.decimalPattern('pt_BR');
  final NumberFormat _percentFormat = NumberFormat.decimalPattern('pt_BR');
  final DateFormat _dateTimeFormat = DateFormat(
    "dd/MM/yyyy 'as' HH:mm",
    'pt_BR',
  );

  bool _loading = true;
  String? _errorMessage;
  PerformanceOverview _overview = PerformanceOverview.empty();
  String? _selectedMonthValue;
  KpiMetricSource _selectedMetricSource = KpiMetricSource.venda;

  bool get _isSeller => _overview.profileSlug == AppProfile.sellerSlug;
  bool get _isSupervisor => _overview.profileSlug == AppProfile.supervisorSlug;
  bool get _isCoordinator =>
      _overview.profileSlug == AppProfile.coordinatorSlug;
  bool get _isNamedProfile => _isSeller || _isSupervisor || _isCoordinator;
  bool get _showsMetricSourceSelector => !_isNamedProfile;

  DateTime get _projectionMonthStart {
    final selectedMonthStart = _overview.selectedMonthStart;
    if (selectedMonthStart != null) {
      return DateTime(selectedMonthStart.year, selectedMonthStart.month, 1);
    }
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  @override
  void initState() {
    super.initState();
    _loadOverview();
  }

  Future<void> _loadOverview({
    DateTime? monthStart,
    KpiMetricSource? metricSource,
  }) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final overview = await _repository.getPerformanceOverview(
        monthStart: monthStart,
        metricSource: metricSource ?? _selectedMetricSource,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _overview = overview;
        _selectedMetricSource = overview.metricSource;
        _selectedMonthValue = overview.selectedMonthStart
            ?.toIso8601String()
            .split('T')
            .first;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage = 'Falha ao carregar a performance.\n$error';
      });
    }
  }

  Future<void> _handleMonthChanged(String? value) async {
    if (value == null || value == _selectedMonthValue) {
      return;
    }

    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return;
    }

    await _loadOverview(monthStart: parsed);
  }

  Future<void> _handleMetricSourceChanged(KpiMetricSource? source) async {
    if (source == null || source == _selectedMetricSource) {
      return;
    }

    await _loadOverview(
      monthStart: _overview.selectedMonthStart,
      metricSource: source,
    );
  }

  String _formatCurrency(double value) => _currencyFormat.format(value);

  String _formatInteger(num value) => _integerFormat.format(value);

  String _formatCompactCurrency(double value) =>
      _compactCurrencyFormat.format(value);

  String _formatPercent(double? value) {
    if (value == null) {
      return 'Sem meta';
    }
    final fixed = double.parse(value.toStringAsFixed(1));
    return '${_percentFormat.format(fixed)}%';
  }

  String _profileLabel(String slug) {
    switch (slug) {
      case AppProfile.sellerSlug:
        return 'Vendedor';
      case AppProfile.supervisorSlug:
        return 'Supervisor';
      case AppProfile.coordinatorSlug:
        return 'Coordenador';
      case AppProfile.adminSlug:
        return 'Administracao';
      case AppProfile.othersSlug:
        return 'Usuario';
      default:
        return 'Usuario';
    }
  }

  String _profileRuleDescription() {
    if (_isSeller) {
      return 'Financeiro em venda liquida. Positivacao e SKU em venda bruta.';
    }
    if (_isSupervisor) {
      return 'Geral com faturamento liquido. Fornecedores, positivacao e SKU em venda bruta.';
    }
    if (_isCoordinator) {
      return 'Financeiro em faturamento liquido. Positivacao e SKU em faturamento bruto.';
    }
    return 'Meta consolidada pela soma dos coordenadores. Positivacao sempre como metrica secundaria.';
  }

  String _supplierLogoUrl(String supplierCode) {
    return '${SupabaseConfig.url}/storage/v1/object/public/fornecedores-logos/$supplierCode.png';
  }

  List<String> _buildLastUpdateLines() {
    final lines = <String>[
      _overview.lastTargetsUpdatedAt != null
          ? 'Metas atualizadas em ${_dateTimeFormat.format(_overview.lastTargetsUpdatedAt!.toLocal())}'
          : 'Metas: atualizacao ainda nao disponivel',
    ];

    if (_showsMetricSourceSelector &&
        _selectedMetricSource == KpiMetricSource.venda) {
      lines.add(
        _overview.lastSalesUpdatedAt != null
            ? 'Venda atualizada em ${_dateTimeFormat.format(_overview.lastSalesUpdatedAt!.toLocal())}'
            : 'Venda: atualizacao ainda nao disponivel',
      );
    }

    if (_isSeller || _isSupervisor) {
      lines.add(
        _overview.lastSalesUpdatedAt != null
            ? 'Venda atualizada em ${_dateTimeFormat.format(_overview.lastSalesUpdatedAt!.toLocal())}'
            : 'Venda: atualizacao ainda nao disponivel',
      );
    }

    if ((_showsMetricSourceSelector &&
            _selectedMetricSource == KpiMetricSource.faturamento) ||
        _isSeller ||
        _isSupervisor ||
        _isCoordinator) {
      lines.add(
        _overview.lastFinancialUpdatedAt != null
            ? 'Faturamento/devolucao atualizado em ${_dateTimeFormat.format(_overview.lastFinancialUpdatedAt!.toLocal())}'
            : 'Faturamento/devolucao: atualizacao ainda nao disponivel',
      );
    }

    if (_isNamedProfile) {
      final skuSourceLabel = _isCoordinator ? 'faturamento' : 'venda';
      lines.add(
        _overview.lastSkuUpdatedAt != null
            ? 'SKU de $skuSourceLabel atualizado em ${_dateTimeFormat.format(_overview.lastSkuUpdatedAt!.toLocal())}'
            : 'SKU: atualizacao ainda nao disponivel',
      );
    }

    return lines;
  }

  Widget _buildLastUpdatesCard() {
    final lines = _buildLastUpdateLines();

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.schedule_outlined, color: primaryColor),
                const SizedBox(width: 10),
                Text(
                  'Ultimas atualizacoes',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...lines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(line),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthFilterCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Performance mensal',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '${_profileLabel(_overview.profileSlug)}. ${_profileRuleDescription()}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF5E6A7C)),
            ),
            const SizedBox(height: 16),
            if (_showsMetricSourceSelector) ...[
              DropdownButtonFormField<KpiMetricSource>(
                initialValue: _selectedMetricSource,
                decoration: const InputDecoration(
                  labelText: 'Fonte dos indicadores',
                  prefixIcon: Icon(Icons.tune_outlined),
                ),
                items: KpiMetricSource.values
                    .map(
                      (source) => DropdownMenuItem<KpiMetricSource>(
                        value: source,
                        child: Text(source.label),
                      ),
                    )
                    .toList(),
                onChanged: _handleMetricSourceChanged,
              ),
              const SizedBox(height: 14),
            ],
            DropdownButtonFormField<String>(
              key: ValueKey<String>(_selectedMonthValue ?? ''),
              initialValue: _selectedMonthValue,
              decoration: const InputDecoration(
                labelText: 'Mes de referencia',
                prefixIcon: Icon(Icons.calendar_month_outlined),
              ),
              items: _overview.availableMonths
                  .map(
                    (month) => DropdownMenuItem<String>(
                      value: month.value,
                      child: Text(month.label),
                    ),
                  )
                  .toList(),
              onChanged: _handleMonthChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Legenda da projecao',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'A projecao considera dias uteis de segunda a sexta, excluindo feriados nacionais e do Ceara.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF5E6A7C)),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: const [
                _LegendBadge(
                  label: 'Realizado',
                  color: Color(0xFF0F766E),
                  style: _LegendBadgeStyle.solid,
                ),
                _LegendBadge(
                  label: 'Projecao ate o fim do mes',
                  color: Color(0xFF4F7CFF),
                  style: _LegendBadgeStyle.projected,
                ),
                _LegendBadge(
                  label: 'Meta do mes (100%)',
                  color: Color(0xFF7A8597),
                  style: _LegendBadgeStyle.goal,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<_MetricPanelData> _buildMetricPanels(PerformanceOverviewItem item) {
    final panels = <_MetricPanelData>[_buildFinancialPanel(item)];

    if (item.hasSecondaryMetric ||
        item.secondaryTarget != null ||
        item.secondaryActual > 0) {
      panels.add(_buildSecondaryPanel(item));
    }

    return panels;
  }

  _MetricPanelData _buildFinancialPanel(PerformanceOverviewItem item) {
    final summary = BusinessDayProjection.summarize(
      actualValue: item.actualFin,
      targetValue: item.targetFin,
      monthStart: _projectionMonthStart,
    );

    return _MetricPanelData(
      title: item.financialLabel,
      icon: Icons.paid_outlined,
      accentColor: const Color(0xFF0F766E),
      showProjection: true,
      actualLabel: _formatCurrency(item.actualFin),
      targetLabel: _formatCurrency(item.targetFin),
      projectedLabel: _formatCurrency(summary.projectedValue),
      remainingLabel: _formatCurrency(
        math.max(item.targetFin - item.actualFin, 0),
      ),
      averageLabel:
          '${_formatCompactCurrency(summary.averagePerBusinessDay)}/dia util',
      actualProgressPct: summary.actualProgressPct,
      projectedProgressPct: summary.projectedProgressPct,
      elapsedBusinessDays: summary.monthContext.elapsedBusinessDays,
      totalBusinessDays: summary.monthContext.totalBusinessDays,
      paceStatus: summary.paceStatus,
    );
  }

  _MetricPanelData _buildSecondaryPanel(PerformanceOverviewItem item) {
    final actualValue = item.secondaryActual.toDouble();
    final targetValue = item.secondaryTarget?.toDouble();
    final summary = BusinessDayProjection.summarize(
      actualValue: actualValue,
      targetValue: targetValue,
      monthStart: _projectionMonthStart,
    );

    return _MetricPanelData(
      title: item.secondaryLabel,
      icon: item.usesSkuMetric
          ? Icons.inventory_2_outlined
          : Icons.groups_outlined,
      accentColor: item.usesSkuMetric
          ? const Color(0xFF7C3AED)
          : const Color(0xFF1D4ED8),
      showProjection: false,
      actualLabel: _formatInteger(item.secondaryActual),
      targetLabel: item.secondaryTarget == null
          ? 'Sem meta'
          : _formatInteger(item.secondaryTarget!),
      projectedLabel: _formatInteger(summary.projectedValue.round()),
      remainingLabel: item.secondaryTarget == null
          ? 'Sem meta'
          : _formatInteger(
              math.max(item.secondaryTarget! - item.secondaryActual, 0),
            ),
      averageLabel:
          '${_formatInteger(summary.averagePerBusinessDay.round())}/dia util',
      actualProgressPct: summary.actualProgressPct,
      projectedProgressPct: summary.projectedProgressPct,
      elapsedBusinessDays: summary.monthContext.elapsedBusinessDays,
      totalBusinessDays: summary.monthContext.totalBusinessDays,
      paceStatus: summary.paceStatus,
    );
  }

  Widget _buildOverallCard(PerformanceOverviewItem item) {
    final panels = _buildMetricPanels(item);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF8FAFF), Color(0xFFEAF0FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCE5FF),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.auto_graph_outlined,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Desempenho geral',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Geral',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF5E6A7C),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ...panels.asMap().entries.map(
              (entry) => Padding(
                padding: EdgeInsets.only(
                  bottom: entry.key == panels.length - 1 ? 0 : 12,
                ),
                child: _MetricProjectionPanel(
                  data: entry.value,
                  formatPercent: _formatPercent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupplierCard(PerformanceOverviewItem item) {
    final panels = _buildMetricPanels(item);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    _supplierLogoUrl(item.code),
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7EBFF),
                        borderRadius: BorderRadius.circular(16),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.supplierName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Fornecedor ${item.code}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF5E6A7C),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ...panels.asMap().entries.map(
              (entry) => Padding(
                padding: EdgeInsets.only(
                  bottom: entry.key == panels.length - 1 ? 0 : 12,
                ),
                child: _MetricProjectionPanel(
                  data: entry.value,
                  formatPercent: _formatPercent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnsupportedCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48, color: primaryColor),
            const SizedBox(height: 14),
            const Text(
              'Este modulo esta disponivel apenas para vendedor, supervisor e coordenador.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _loadOverview,
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Atualizar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCard() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Nenhuma meta disponivel para o mes selecionado.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildBody() {
    final overallItem = _overview.overallItem;
    final supplierItems = _overview.supplierItems;

    return RefreshIndicator(
      color: primaryColor,
      onRefresh: _loadOverview,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          _buildMonthFilterCard(),
          const SizedBox(height: 12),
          _buildLegendCard(),
          const SizedBox(height: 16),
          if (!_overview.supported)
            _buildUnsupportedCard()
          else if (_overview.items.isEmpty)
            _buildEmptyCard()
          else ...[
            if (overallItem != null) ...[
              _buildOverallCard(overallItem),
              const SizedBox(height: 20),
            ],
            Text(
              'Fornecedores',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ...supplierItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildSupplierCard(item),
              ),
            ),
            const SizedBox(height: 8),
            _buildLastUpdatesCard(),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Performance')),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: primaryColor),
              )
            : _errorMessage != null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  _ErrorCard(message: _errorMessage!, onRetry: _loadOverview),
                ],
              )
            : _buildBody(),
      ),
    );
  }
}

class _MetricPanelData {
  const _MetricPanelData({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.showProjection,
    required this.actualLabel,
    required this.targetLabel,
    required this.projectedLabel,
    required this.remainingLabel,
    required this.averageLabel,
    required this.actualProgressPct,
    required this.projectedProgressPct,
    required this.elapsedBusinessDays,
    required this.totalBusinessDays,
    required this.paceStatus,
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final bool showProjection;
  final String actualLabel;
  final String targetLabel;
  final String projectedLabel;
  final String remainingLabel;
  final String averageLabel;
  final double? actualProgressPct;
  final double? projectedProgressPct;
  final int elapsedBusinessDays;
  final int totalBusinessDays;
  final ProjectionPaceStatus paceStatus;
}

class _MetricProjectionPanel extends StatelessWidget {
  const _MetricProjectionPanel({
    required this.data,
    required this.formatPercent,
  });

  final _MetricPanelData data;
  final String Function(double? value) formatPercent;

  @override
  Widget build(BuildContext context) {
    final actualFraction = _normalizedProgress(data.actualProgressPct);
    final projectedFraction = data.showProjection
        ? _normalizedProgress(data.projectedProgressPct)
        : actualFraction;
    final projectedPercentLabel = data.projectedProgressPct == null
        ? 'Tend. --'
        : 'Tend. ${formatPercent(data.projectedProgressPct)}';
    final statusData = _buildStatusData(data);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDCE3F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: data.accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(data.icon, color: data.accentColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    data.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      height: 1.05,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    height: 28,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatPercent(data.actualProgressPct),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: data.accentColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (data.showProjection)
                    Text(
                      projectedPercentLabel,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: data.accentColor.withValues(alpha: 0.88),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ProjectedProgressBar(
            color: data.accentColor,
            actualFraction: actualFraction,
            projectedFraction: projectedFraction,
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFE3E8F5)),
          const SizedBox(height: 14),
          Column(
            children: [
              _MetricInfoTile(title: 'Meta', value: data.targetLabel),
              const SizedBox(height: 8),
              _MetricInfoTile(title: 'Realizado', value: data.actualLabel),
              if (data.showProjection) ...[
                const SizedBox(height: 8),
                _MetricInfoTile(title: 'Tendencia', value: data.projectedLabel),
              ],
              const SizedBox(height: 8),
              _MetricInfoTile(
                title: 'Falta para meta',
                value: data.remainingLabel,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFE3E8F5)),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoPill(
                    icon: Icons.calendar_month_outlined,
                    label:
                        'Dias uteis: ${data.elapsedBusinessDays}/${data.totalBusinessDays}',
                    maxWidth: constraints.maxWidth,
                  ),
                  _InfoPill(
                    icon: Icons.bar_chart_outlined,
                    label: 'Media/dia util: ${data.averageLabel}',
                    maxWidth: constraints.maxWidth,
                  ),
                  _InfoPill(
                    icon: statusData.icon,
                    label: statusData.label,
                    foregroundColor: statusData.foregroundColor,
                    backgroundColor: statusData.backgroundColor,
                    maxWidth: constraints.maxWidth,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  double _normalizedProgress(double? value) {
    if (value == null) {
      return 0;
    }
    return (value / 100).clamp(0.0, 1.0);
  }

  _StatusPillData _buildStatusData(_MetricPanelData data) {
    switch (data.paceStatus) {
      case ProjectionPaceStatus.onTrack:
        return const _StatusPillData(
          label: 'No ritmo',
          icon: Icons.trending_up_rounded,
          foregroundColor: Color(0xFF15803D),
          backgroundColor: Color(0xFFEAF8EE),
        );
      case ProjectionPaceStatus.belowTarget:
        return const _StatusPillData(
          label: 'Abaixo da meta',
          icon: Icons.trending_down_rounded,
          foregroundColor: Color(0xFFDC2626),
          backgroundColor: Color(0xFFFDECEC),
        );
      case ProjectionPaceStatus.noTarget:
        return const _StatusPillData(
          label: 'Sem meta',
          icon: Icons.remove_rounded,
          foregroundColor: Color(0xFF64748B),
          backgroundColor: Color(0xFFF1F5F9),
        );
    }
  }
}

class _StatusPillData {
  const _StatusPillData({
    required this.label,
    required this.icon,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  final String label;
  final IconData icon;
  final Color foregroundColor;
  final Color backgroundColor;
}

class _ProjectedProgressBar extends StatelessWidget {
  const _ProjectedProgressBar({
    required this.color,
    required this.actualFraction,
    required this.projectedFraction,
  });

  final Color color;
  final double actualFraction;
  final double projectedFraction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth = constraints.maxWidth;
              final normalizedActual = actualFraction.clamp(0.0, 1.0);
              final normalizedProjected = projectedFraction.clamp(0.0, 1.0);
              final actualWidth = trackWidth * normalizedActual;
              final projectedWidth = trackWidth * normalizedProjected;
              final projectedExtensionWidth = math.max<double>(
                projectedWidth - actualWidth,
                0,
              );

              return SizedBox(
                height: 18,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8EEF8),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    if (actualWidth > 0)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: actualWidth,
                        child: Container(
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.horizontal(
                              left: const Radius.circular(999),
                              right: Radius.circular(
                                projectedExtensionWidth > 0 ? 3 : 999,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (projectedExtensionWidth > 0)
                      Positioned(
                        left: actualWidth,
                        top: 0,
                        bottom: 0,
                        width: projectedExtensionWidth,
                        child: CustomPaint(
                          painter: _ProjectedBorderPainter(color),
                          child: Container(
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.14),
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(3),
                                right: Radius.circular(999),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 0,
                      top: -2,
                      bottom: -2,
                      child: Container(
                        width: 2,
                        decoration: BoxDecoration(
                          color: const Color(0xFF94A3B8),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '100%',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF64748B),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ProjectedBorderPainter extends CustomPainter {
  const _ProjectedBorderPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final radius = Radius.circular(size.height / 2);
    final rect = RRect.fromRectAndRadius(Offset.zero & size, radius);
    _drawDashedRRect(canvas, rect, paint);
  }

  void _drawDashedRRect(Canvas canvas, RRect rect, Paint paint) {
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        const dashLength = 6.0;
        const gapLength = 4.0;
        final nextDistance = math.min<double>(
          distance + dashLength,
          metric.length,
        );
        canvas.drawPath(metric.extractPath(distance, nextDistance), paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ProjectedBorderPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _MetricInfoTile extends StatelessWidget {
  const _MetricInfoTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E8F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    this.foregroundColor = const Color(0xFF334155),
    this.backgroundColor = const Color(0xFFF4F7FD),
    this.maxWidth,
  });

  final IconData icon;
  final String label;
  final Color foregroundColor;
  final Color backgroundColor;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: maxWidth == null
          ? null
          : BoxConstraints(maxWidth: maxWidth!),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foregroundColor),
            const SizedBox(width: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foregroundColor,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _LegendBadgeStyle { solid, projected, goal }

class _LegendBadge extends StatelessWidget {
  const _LegendBadge({
    required this.label,
    required this.color,
    required this.style,
  });

  final String label;
  final Color color;
  final _LegendBadgeStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE1E6F5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            child: CustomPaint(
              painter: _LegendMarkPainter(color: color, style: style),
              size: const Size(28, 10),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF334155),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendMarkPainter extends CustomPainter {
  const _LegendMarkPainter({required this.color, required this.style});

  final Color color;
  final _LegendBadgeStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final paint = Paint()
      ..color = style == _LegendBadgeStyle.goal
          ? color
          : color.withValues(
              alpha: style == _LegendBadgeStyle.projected ? 0.8 : 1,
            )
      ..strokeWidth = style == _LegendBadgeStyle.goal ? 2 : 4
      ..strokeCap = StrokeCap.round;

    if (style == _LegendBadgeStyle.goal) {
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        paint,
      );
      return;
    }

    if (style == _LegendBadgeStyle.solid) {
      canvas.drawLine(Offset(2, y), Offset(size.width - 2, y), paint);
      return;
    }

    var x = 2.0;
    while (x < size.width - 2) {
      final endX = math.min<double>(x + 6, size.width - 2);
      canvas.drawLine(Offset(x, y), Offset(endX, y), paint);
      x += 9;
    }
  }

  @override
  bool shouldRepaint(covariant _LegendMarkPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.style != style;
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
