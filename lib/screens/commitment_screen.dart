import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_theme.dart';
import '../models/app_profile.dart';
import '../models/commitment_overview.dart';
import '../services/app_repository.dart';
import '../utils/business_day_projection.dart';

class CommitmentScreen extends StatefulWidget {
  const CommitmentScreen({super.key});

  @override
  State<CommitmentScreen> createState() => _CommitmentScreenState();
}

class _CommitmentScreenState extends State<CommitmentScreen> {
  final AppRepository _repository = AppRepository.instance;
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');
  final DateFormat _updatedFormat = DateFormat('dd/MM HH:mm', 'pt_BR');
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final NumberFormat _integerFormat = NumberFormat.decimalPattern('pt_BR');
  final NumberFormat _percentFormat = NumberFormat.decimalPatternDigits(
    locale: 'pt_BR',
    decimalDigits: 1,
  );

  CommitmentOverview _overview = CommitmentOverview.empty();
  bool _loading = true;
  String? _errorMessage;
  String? _selectedPeriodValue;
  String? _selectedScopeValue;

  bool get _showsUserFilter => const <String>{
    AppProfile.boardSlug,
    AppProfile.othersSlug,
  }.contains(_overview.viewerProfileSlug);

  List<CommitmentItem> get _displayItems {
    if (!_showsUserFilter || _selectedScopeValue != null) {
      return _overview.items;
    }
    final companyTotal = CommitmentItem.companyTotalFrom(_overview.items);
    return companyTotal == null
        ? _overview.items
        : <CommitmentItem>[companyTotal, ..._overview.items];
  }

  @override
  void initState() {
    super.initState();
    _loadOverview();
  }

  Future<void> _loadOverview({
    CommitmentPeriod? period,
    CommitmentScope? scope,
    bool preserveScope = true,
  }) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final effectivePeriod = period ?? _selectedPeriod;
      final effectiveScope = preserveScope ? (scope ?? _selectedScope) : scope;
      final result = await _repository.getCommitmentOverview(
        startDate: effectivePeriod?.startDate,
        endDate: effectivePeriod?.endDate,
        targetScopeProfileSlug: effectiveScope?.profileSlug,
        targetScopeOwnerCode: effectiveScope?.ownerCode,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _overview = result;
        _selectedPeriodValue = result.selectedStartDate == null
            ? null
            : CommitmentPeriod(
                startDate: result.selectedStartDate!,
                endDate: result.selectedEndDate!,
              ).value;
        final selectedProfile = result.selectedScopeProfileSlug;
        final selectedCode = result.selectedScopeOwnerCode;
        _selectedScopeValue = selectedProfile == null || selectedCode == null
            ? null
            : '$selectedProfile|$selectedCode';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = _friendlyError(error);
      });
    }
  }

  CommitmentPeriod? get _selectedPeriod {
    final selected = _selectedPeriodValue;
    if (selected == null) {
      return null;
    }
    for (final period in _overview.availablePeriods) {
      if (period.value == selected) {
        return period;
      }
    }
    return null;
  }

  CommitmentScope? get _selectedScope {
    final selected = _selectedScopeValue;
    if (selected == null) {
      return null;
    }
    for (final scope in _overview.availableScopes) {
      if (scope.value == selected) {
        return scope;
      }
    }
    return null;
  }

  String _friendlyError(Object error) {
    final text = '$error';
    if (text.contains('SocketException') ||
        text.contains('Failed host lookup')) {
      return 'Sem conexão. Verifique a internet e tente novamente.';
    }
    return 'Não foi possível carregar os compromissos. Tente novamente.';
  }

  Future<void> _changePeriod(String? value) async {
    if (value == null || value == _selectedPeriodValue) {
      return;
    }
    final period = _overview.availablePeriods.firstWhere(
      (candidate) => candidate.value == value,
    );
    setState(() {
      _selectedPeriodValue = value;
      _selectedScopeValue = null;
    });
    await _loadOverview(period: period, preserveScope: false);
  }

  Future<void> _changeScope(String? value) async {
    if (value == _selectedScopeValue) {
      return;
    }
    final scope = value == null
        ? null
        : _overview.availableScopes.firstWhere(
            (candidate) => candidate.value == value,
          );
    setState(() => _selectedScopeValue = value);
    await _loadOverview(scope: scope, preserveScope: value != null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compromisso'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : _loadOverview,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading && _overview.availablePeriods.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadOverview,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
                  children: [
                    _buildIntroductionCard(),
                    const SizedBox(height: 12),
                    if (_errorMessage != null) ...[
                      _buildErrorCard(),
                      const SizedBox(height: 12),
                    ],
                    if (_overview.availablePeriods.isEmpty)
                      _buildEmptyCard(
                        icon: Icons.event_busy_outlined,
                        title: 'Nenhum compromisso disponível',
                        message:
                            'Quando uma meta de período for cadastrada, ela aparecerá aqui.',
                      )
                    else ...[
                      _buildFiltersCard(),
                      const SizedBox(height: 12),
                      _buildPeriodSummary(),
                      const SizedBox(height: 12),
                      if (_displayItems.isEmpty)
                        _buildEmptyCard(
                          icon: Icons.manage_search_outlined,
                          title: 'Nenhum usuário neste período',
                          message:
                              'Não há compromisso associado ao filtro selecionado.',
                        )
                      else
                        ..._displayItems.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildCommitmentCard(item),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildIntroductionCard() {
    return Card(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          gradient: LinearGradient(
            colors: [primaryColor, Color(0xFF263CAC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Row(
          children: [
            _HeaderIcon(),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Meta do período',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Acompanhe o realizado, a tendência e o ritmo necessário para cumprir seu compromisso.',
                    style: TextStyle(
                      color: Color(0xFFDDE3FF),
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.tune_rounded, size: 20, color: primaryColor),
                SizedBox(width: 8),
                Text(
                  'Filtros',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: ValueKey('period-$_selectedPeriodValue'),
              initialValue: _selectedPeriodValue,
              decoration: const InputDecoration(
                labelText: 'Período do compromisso',
                prefixIcon: Icon(Icons.date_range_outlined),
              ),
              items: _overview.availablePeriods
                  .map(
                    (period) => DropdownMenuItem<String>(
                      value: period.value,
                      child: Text(
                        '${_dateFormat.format(period.startDate)} a '
                        '${_dateFormat.format(period.endDate)}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _loading ? null : _changePeriod,
            ),
            if (_showsUserFilter) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: ValueKey('scope-$_selectedScopeValue'),
                initialValue: _selectedScopeValue,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Supervisor ou coordenador',
                  prefixIcon: Icon(Icons.manage_accounts_outlined),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todos'),
                  ),
                  ..._overview.availableScopes.map(
                    (scope) => DropdownMenuItem<String?>(
                      value: scope.value,
                      child: Text(scope.label, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: _loading ? null : _changeScope,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSummary() {
    final start = _overview.selectedStartDate!;
    final end = _overview.selectedEndDate!;
    final context = BusinessDayProjection.buildPeriodContext(
      startDate: start,
      endDate: end,
    );
    return Row(
      children: [
        const Icon(
          Icons.calendar_today_outlined,
          size: 17,
          color: primaryColor,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${_dateFormat.format(start)} a ${_dateFormat.format(end)}  •  '
            'Dias úteis: ${context.elapsedBusinessDays}/${context.totalBusinessDays}',
            style: const TextStyle(
              color: Color(0xFF64718A),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (_overview.lastUpdatedAt != null)
          Text(
            'Atualizado ${_updatedFormat.format(_overview.lastUpdatedAt!)}',
            style: const TextStyle(
              color: Color(0xFF8792A8),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  Widget _buildCommitmentCard(CommitmentItem item) {
    final isCompany = item.profileSlug == CommitmentItem.companyProfileSlug;
    final role = item.profileSlug == AppProfile.coordinatorSlug
        ? 'Coordenador'
        : 'Supervisor';
    final subtitle = isCompany
        ? 'Soma dos coordenadores'
        : '$role ${item.ownerCode}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFFE8ECFF),
                  foregroundColor: kpiPositivationColor,
                  child: Text(
                    _initials(item.displayName),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.displayName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF738098),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildMetric(
              title: 'Compromisso financeiro',
              icon: Icons.trending_up_rounded,
              color: kpiFinancialColor,
              background: kpiFinancialBackgroundColor,
              actual: item.financialActual,
              projectionActual: item.financialClosedActual,
              target: item.financialTarget,
              valueFormatter: _currencyFormat.format,
              dailyFormatter: (value) => '${_currencyFormat.format(value)}/dia',
            ),
            const SizedBox(height: 12),
            _buildMetric(
              title: 'Compromisso de positivação',
              icon: Icons.groups_2_outlined,
              color: kpiPositivationColor,
              background: kpiPositivationBackgroundColor,
              actual: item.positivationActual.toDouble(),
              projectionActual: item.positivationClosedActual.toDouble(),
              target: item.positivationTarget,
              valueFormatter: (value) => _integerFormat.format(value.round()),
              dailyFormatter: (value) =>
                  '${_integerFormat.format(value.ceil())}/dia',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric({
    required String title,
    required IconData icon,
    required Color color,
    required Color background,
    required double actual,
    required double projectionActual,
    required double target,
    required String Function(double) valueFormatter,
    required String Function(double) dailyFormatter,
  }) {
    final summary = BusinessDayProjection.summarizePeriod(
      actualValue: actual,
      projectionActualValue: projectionActual,
      targetValue: target > 0 ? target : null,
      startDate: _overview.selectedStartDate!,
      endDate: _overview.selectedEndDate!,
    );
    final progress = ((summary.actualProgressPct ?? 0) / 100).clamp(0.0, 1.0);
    final hasProjection = summary.periodContext.hasProjectionBasis;
    final averageLabel = summary.periodContext.hasCompletedBusinessDays
        ? 'Média fechada'
        : 'Média atual';
    final pace = summary.paceStatus;
    final paceColor = !hasProjection && actual < target
        ? const Color(0xFF738098)
        : pace == ProjectionPaceStatus.onTrack
        ? kpiFinancialColor
        : pace == ProjectionPaceStatus.belowTarget
        ? const Color(0xFFE77A00)
        : const Color(0xFF738098);
    final paceLabel = !hasProjection && actual < target
        ? 'Aguardando fechamento'
        : pace == ProjectionPaceStatus.onTrack
        ? 'No ritmo'
        : pace == ProjectionPaceStatus.belowTarget
        ? 'Abaixo da meta'
        : 'Sem meta';
    final required = summary.requiredPerBusinessDay;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1E7F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                summary.actualProgressPct == null
                    ? '--'
                    : '${_percentFormat.format(summary.actualProgressPct)}%',
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: progress,
              backgroundColor: background,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricValue(
                  label: 'Realizado',
                  value: valueFormatter(actual),
                ),
              ),
              Container(width: 1, height: 36, color: const Color(0xFFE1E7F2)),
              Expanded(
                child: _MetricValue(
                  label: 'Meta',
                  value: target > 0 ? valueFormatter(target) : 'Sem meta',
                  alignEnd: true,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoPill(
                label: 'Tendência',
                value: hasProjection
                    ? valueFormatter(summary.projectedValue)
                    : 'Aguardando',
              ),
              _InfoPill(
                label: averageLabel,
                value: hasProjection
                    ? dailyFormatter(summary.averagePerBusinessDay)
                    : 'Aguardando',
              ),
              _InfoPill(
                label: 'Necessidade',
                value: required == null
                    ? (target <= 0 ? 'Sem meta' : 'Sem dias úteis')
                    : dailyFormatter(required),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: paceColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  paceLabel,
                  style: TextStyle(
                    color: paceColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      color: const Color(0xFFFFF4F3),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFC7392F)),
            const SizedBox(width: 10),
            Expanded(child: Text(_errorMessage!)),
            TextButton(onPressed: _loadOverview, child: const Text('Tentar')),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCard({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 34),
        child: Column(
          children: [
            Icon(icon, size: 42, color: const Color(0xFF8792A8)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF738098), height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      return '--';
    }
    if (words.length == 1) {
      return words.first.substring(0, 1).toUpperCase();
    }
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(15),
      ),
      child: const Icon(Icons.flag_outlined, color: Colors.white, size: 30),
    );
  }
}

class _MetricValue extends StatelessWidget {
  const _MetricValue({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF738098),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F3F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: Color(0xFF738098),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}
