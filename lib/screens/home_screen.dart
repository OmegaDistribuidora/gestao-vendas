import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/app_theme.dart';
import '../models/app_profile.dart';
import '../models/app_user.dart';
import '../models/bi_module.dart';
import '../models/kpi_metric_source.dart';
import '../models/seller_home_kpis.dart';
import '../models/user_module_access.dart';
import '../services/app_repository.dart';
import '../utils/power_bi_url_builder.dart';
import 'admin_screen.dart';
import 'change_password_screen.dart';
import 'panel_view_screen.dart';
import 'performance_screen.dart';
import 'reports_screen.dart';
import 'returns_screen.dart';
import 'supplier_analysis_screen.dart';

enum _HomePeriodPreset {
  today,
  yesterday,
  currentMonth,
  previousMonth,
  currentYear,
  custom,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.currentUser,
    required this.onLogout,
  });

  final AppUser currentUser;
  final Future<void> Function() onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AppRepository _repository = AppRepository.instance;
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
  String _appVersionLabel = 'Versao 0.4.1+5';
  List<BiModule> _visibleModules = const <BiModule>[];
  SellerHomeKpis _homeKpis = SellerHomeKpis.empty();
  _HomePeriodPreset _selectedPeriod = _HomePeriodPreset.today;
  KpiMetricSource _selectedMetricSource = KpiMetricSource.venda;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  bool get _isAdmin => widget.currentUser.isAdmin;
  bool get _isSeller => widget.currentUser.profileSlug == AppProfile.sellerSlug;
  bool get _isSupervisor =>
      widget.currentUser.profileSlug == AppProfile.supervisorSlug;
  bool get _isCoordinator =>
      widget.currentUser.profileSlug == AppProfile.coordinatorSlug;
  bool get _showsHomeKpis => !_isAdmin;
  bool get _isNamedKpiProfile => _isSeller || _isSupervisor || _isCoordinator;
  bool get _showsPerformanceModule => true;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _loadContent();
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version.trim();
      final buildNumber = packageInfo.buildNumber.trim();
      final versionLabel = buildNumber.isEmpty
          ? 'Versao $version'
          : 'Versao $version+$buildNumber';
      if (!mounted) {
        return;
      }
      setState(() {
        _appVersionLabel = versionLabel;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _appVersionLabel = 'Versao 0.4.1+5';
      });
    }
  }

  DateTime get _periodStart {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case _HomePeriodPreset.today:
        return DateTime(now.year, now.month, now.day);
      case _HomePeriodPreset.yesterday:
        final yesterday = now.subtract(const Duration(days: 1));
        return DateTime(yesterday.year, yesterday.month, yesterday.day);
      case _HomePeriodPreset.currentMonth:
        return DateTime(now.year, now.month, 1);
      case _HomePeriodPreset.previousMonth:
        return DateTime(now.year, now.month - 1, 1);
      case _HomePeriodPreset.currentYear:
        return DateTime(now.year, 1, 1);
      case _HomePeriodPreset.custom:
        final customStart = _customStartDate ?? now;
        return DateTime(customStart.year, customStart.month, customStart.day);
    }
  }

  DateTime get _periodEnd {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case _HomePeriodPreset.today:
        return DateTime(now.year, now.month, now.day, 23, 59, 59);
      case _HomePeriodPreset.yesterday:
        final yesterday = now.subtract(const Duration(days: 1));
        return DateTime(
          yesterday.year,
          yesterday.month,
          yesterday.day,
          23,
          59,
          59,
        );
      case _HomePeriodPreset.currentMonth:
        return DateTime(now.year, now.month, now.day, 23, 59, 59);
      case _HomePeriodPreset.previousMonth:
        return DateTime(now.year, now.month, 0, 23, 59, 59);
      case _HomePeriodPreset.currentYear:
        return DateTime(now.year, now.month, now.day, 23, 59, 59);
      case _HomePeriodPreset.custom:
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
      case _HomePeriodPreset.today:
        return 'Hoje';
      case _HomePeriodPreset.yesterday:
        return 'Ontem';
      case _HomePeriodPreset.currentMonth:
        return 'Mês atual';
      case _HomePeriodPreset.previousMonth:
        return 'Mês anterior';
      case _HomePeriodPreset.currentYear:
        return 'Ano atual';
      case _HomePeriodPreset.custom:
        return '${_dateFormat.format(_periodStart)} até ${_dateFormat.format(_periodEnd)}';
    }
  }

  Future<void> _loadContent() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait<dynamic>([
        _repository.getModulesForUser(widget.currentUser),
        _repository.getHomeKpis(
          start: _periodStart,
          end: _periodEnd,
          metricSource: _selectedMetricSource,
        ),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _visibleModules = results[0] as List<BiModule>;
        _homeKpis = results[1] as SellerHomeKpis;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage = 'Falha ao carregar os módulos.\n$error';
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

    await _loadContent();
  }

  Future<void> _handlePeriodChanged(_HomePeriodPreset? preset) async {
    if (preset == null) {
      return;
    }

    setState(() {
      _selectedPeriod = preset;
      if (preset == _HomePeriodPreset.custom) {
        final today = DateTime.now();
        _customStartDate ??= DateTime(today.year, today.month, today.day);
        _customEndDate ??= _customStartDate;
      }
    });

    await _loadContent();
  }

  Future<void> _handleMetricSourceChanged(KpiMetricSource? source) async {
    if (source == null || source == _selectedMetricSource) {
      return;
    }

    setState(() {
      _selectedMetricSource = source;
    });

    await _loadContent();
  }

  Future<void> _openAdministration() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminScreen(currentUser: widget.currentUser),
      ),
    );
    await _loadContent();
  }

  Future<void> _openAdministrationFromDrawer() async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }
    await _openAdministration();
  }

  Future<void> _openReportsFromDrawer() async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportsScreen(currentUser: widget.currentUser),
      ),
    );
  }

  Future<void> _openSupplierAnalysisFromDrawer() async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SupplierAnalysisScreen()),
    );
  }

  Future<void> _openPerformanceFromDrawer() async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PerformanceScreen()));
  }

  Future<void> _openReturnsFromDrawer() async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ReturnsScreen()));
  }

  Future<void> _openChangePasswordFromDrawer() async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangePasswordScreen(currentUser: widget.currentUser),
      ),
    );
  }

  Future<void> _openModule(BiModule module) async {
    if (module.panelUrl.trim().isEmpty) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este módulo ainda não possui link de painel configurado.',
          ),
        ),
      );
      return;
    }

    var url = module.panelUrl;
    String? filterDescription;

    if (!_isAdmin) {
      final access = await _repository.getAccessForUserModule(
        widget.currentUser.id,
        module.id,
      );
      final filterValues = access?.filterValues ?? const [];
      final activeDescriptions = filterValues
          .where((item) => item.filterValue.trim().isNotEmpty)
          .map(
            (item) =>
                '${item.moduleFilter?.displayLabel ?? 'Filtro'}: ${item.filterValue}',
          )
          .toList();

      if (filterValues.isNotEmpty) {
        url = PowerBiUrlBuilder.build(module, filterValues);
      }
      filterDescription = activeDescriptions.isEmpty
          ? 'Sem filtros específicos.'
          : activeDescriptions.join(' | ');
    }

    final startedAt = DateTime.now();
    final usageEventId = await _repository.startModuleUsage(
      userId: widget.currentUser.id,
      moduleId: module.id,
    );

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PanelViewScreen(
          title: module.name,
          initialUrl: url,
          filterDescription: filterDescription,
          isAdminView: _isAdmin,
        ),
      ),
    );

    if (usageEventId != null) {
      await _repository.finishModuleUsage(
        usageEventId: usageEventId,
        duration: DateTime.now().difference(startedAt),
      );
    }
  }

  String _formatCurrency(double value) => _currencyFormat.format(value);

  String _formatDecimal(double value) =>
      _decimalFormat.format(double.parse(value.toStringAsFixed(1)));

  String _formatDateTime(DateTime value) => _dateTimeFormat.format(value);

  Widget _buildLastUpdatesCard() {
    final lines = <String>[
      _homeKpis.lastSalesUpdatedAt != null
          ? 'Última atualização das vendas: ${_formatDateTime(_homeKpis.lastSalesUpdatedAt!)}'
          : 'Última atualização das vendas: ainda não disponível',
    ];

    if (_homeKpis.lastFinancialUpdatedAt != null) {
      lines.add(
        'Última atualização de faturamento/devolução: ${_formatDateTime(_homeKpis.lastFinancialUpdatedAt!)}',
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.schedule_outlined, color: primaryColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: lines
                    .map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(line),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCarousel({
    required String title,
    required String subtitle,
    required List<_HomeKpiCardData> cards,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF5E6A7C)),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 138,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: cards
                    .map(
                      (card) => _HomeKpiCard(
                        title: card.title,
                        value: card.value,
                        color: card.color,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final displayName = widget.currentUser.displayName?.trim();

    return RefreshIndicator(
      color: primaryColor,
      onRefresh: _loadContent,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isAdmin
                        ? 'Bem-vindo, Administração'
                        : 'Bem-vindo, ${displayName?.isNotEmpty == true ? displayName : widget.currentUser.label}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isAdmin
                        ? 'Acesse a área administrativa para gerenciar usuários, perfis, módulos e relatórios.'
                        : 'Por favor, selecione um módulo no menu à esquerda para acessar.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF5E6A7C),
                    ),
                  ),
                  if (_isAdmin)
                    Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: FilledButton.icon(
                        onPressed: _openAdministration,
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('Abrir administração'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_showsHomeKpis) ...[
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isNamedKpiProfile
                          ? 'Seu desempenho no período'
                          : 'Indicadores do período',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _periodDescription,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF5E6A7C),
                      ),
                    ),
                    const SizedBox(height: 16),
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
                    DropdownButtonFormField<_HomePeriodPreset>(
                      key: ValueKey<_HomePeriodPreset>(_selectedPeriod),
                      initialValue: _selectedPeriod,
                      decoration: const InputDecoration(
                        labelText: 'Período',
                        prefixIcon: Icon(Icons.date_range_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: _HomePeriodPreset.today,
                          child: Text('Hoje'),
                        ),
                        DropdownMenuItem(
                          value: _HomePeriodPreset.yesterday,
                          child: Text('Ontem'),
                        ),
                        DropdownMenuItem(
                          value: _HomePeriodPreset.currentMonth,
                          child: Text('Mês atual'),
                        ),
                        DropdownMenuItem(
                          value: _HomePeriodPreset.previousMonth,
                          child: Text('Mês anterior'),
                        ),
                        DropdownMenuItem(
                          value: _HomePeriodPreset.currentYear,
                          child: Text('Ano atual'),
                        ),
                        DropdownMenuItem(
                          value: _HomePeriodPreset.custom,
                          child: Text('Personalizado'),
                        ),
                      ],
                      onChanged: _handlePeriodChanged,
                    ),
                    if (_selectedPeriod == _HomePeriodPreset.custom) ...[
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
            _buildKpiCarousel(
              title: _selectedMetricSource == KpiMetricSource.venda
                  ? 'Indicadores brutos de venda'
                  : 'Indicadores brutos de faturamento',
              subtitle: _periodDescription,
              cards: [
                _HomeKpiCardData(
                  title: 'Financeiro Bruto',
                  value: _formatCurrency(_homeKpis.grossAmount),
                ),
                _HomeKpiCardData(
                  title: 'Volume Bruto',
                  value: _formatDecimal(_homeKpis.grossVolume),
                ),
                _HomeKpiCardData(
                  title: 'Pedidos Brutos',
                  value: '${_homeKpis.grossOrders}',
                ),
                _HomeKpiCardData(
                  title: 'Positivação Bruta',
                  value: '${_homeKpis.grossPositivation}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildKpiCarousel(
              title: 'Devoluções no período',
              subtitle:
                  'Dados de devolução para o mesmo intervalo selecionado.',
              cards: [
                _HomeKpiCardData(
                  title: 'Financeiro Devolvido',
                  value: _formatCurrency(_homeKpis.returnAmount),
                  color: const Color(0xFFFDECEC),
                ),
                _HomeKpiCardData(
                  title: 'Volume Devolvido',
                  value: _formatDecimal(_homeKpis.returnVolume),
                  color: const Color(0xFFFDECEC),
                ),
                _HomeKpiCardData(
                  title: 'Pedidos Devolvidos',
                  value: '${_homeKpis.returnOrders}',
                  color: const Color(0xFFFDECEC),
                ),
                _HomeKpiCardData(
                  title: 'Positivação Devolvida',
                  value: '${_homeKpis.returnPositivation}',
                  color: const Color(0xFFFDECEC),
                ),
              ],
            ),
          ],
          if (_isAdmin) ...[
            const SizedBox(height: 20),
            Text(
              'Módulos cadastrados',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (_visibleModules.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Nenhum módulo disponível no momento.'),
                ),
              )
            else
              ..._visibleModules.map(
                (module) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ModuleCard(
                    module: module,
                    onOpen: () => _openModule(module),
                    currentUser: widget.currentUser,
                    repository: _repository,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          _buildLastUpdatesCard(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gestão de Vendas',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _appVersionLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF7A8597),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.currentUser.label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF5E6A7C),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.home_outlined),
                      title: const Text('Home'),
                      selected: true,
                      selectedTileColor: const Color(0xFFE7EBFF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    if (_showsPerformanceModule)
                      ListTile(
                        leading: const Icon(Icons.auto_graph_outlined),
                        title: const Text('Performance'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        onTap: _openPerformanceFromDrawer,
                      ),
                    ListTile(
                      leading: const Icon(Icons.storefront_outlined),
                      title: const Text('Análise por Fornecedor'),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      onTap: _openSupplierAnalysisFromDrawer,
                    ),
                    ListTile(
                      leading: const Icon(Icons.assignment_return_outlined),
                      title: const Text('Devoluções'),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      onTap: _openReturnsFromDrawer,
                    ),
                    if (_isAdmin) ...[
                      const SizedBox(height: 8),
                      ListTile(
                        leading: const Icon(Icons.settings_outlined),
                        title: const Text('Administração'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        onTap: _openAdministrationFromDrawer,
                      ),
                      ListTile(
                        leading: const Icon(Icons.analytics_outlined),
                        title: const Text('Relatórios'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        onTap: _openReportsFromDrawer,
                      ),
                    ],
                    if (_visibleModules.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(12, 18, 12, 8),
                        child: Text(
                          'Painéis BI',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF5E6A7C),
                          ),
                        ),
                      ),
                      ..._visibleModules.map(
                        (module) => ListTile(
                          leading: const Icon(Icons.bar_chart_outlined),
                          title: Text(module.name),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          onTap: () async {
                            Navigator.of(context).pop();
                            await Future<void>.delayed(
                              const Duration(milliseconds: 120),
                            );
                            if (!mounted) {
                              return;
                            }
                            await _openModule(module);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('Trocar Senha'),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      onTap: _openChangePasswordFromDrawer,
                    ),
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text('Sair'),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      onTap: () async {
                        Navigator.of(context).pop();
                        await widget.onLogout();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        title: Text(
          _isAdmin ? 'Bem-vindo, Administração' : 'Bem-vindo',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            onPressed: _loadContent,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
          IconButton(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: primaryColor),
              )
            : _errorMessage != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: primaryColor,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            Text(_errorMessage!, textAlign: TextAlign.center),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: _loadContent,
                              style: FilledButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Tentar novamente'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : _buildBody(),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.module,
    required this.onOpen,
    required this.currentUser,
    required this.repository,
  });

  final BiModule module;
  final Future<void> Function() onOpen;
  final AppUser currentUser;
  final AppRepository repository;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 10,
        ),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE7EBFF),
          foregroundColor: primaryColor,
          child: const Icon(Icons.bar_chart_outlined),
        ),
        title: Text(
          module.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: FutureBuilder<UserModuleAccess?>(
          future: currentUser.isAdmin
              ? Future<UserModuleAccess?>.value(null)
              : repository.getAccessForUserModule(currentUser.id, module.id),
          builder: (context, snapshot) {
            final lines = <String>[
              'Tipo: Acompanhamento BI',
              'Campos filtráveis: ${module.filters.isEmpty ? 'Nenhum' : module.filters.map((item) => item.displayLabel).join(' | ')}',
              'Status: ${module.isActive ? 'Ativo' : 'Inativo'}',
            ];

            if (currentUser.isAdmin) {
              lines.add('Visão administrativa sem filtro automático.');
            } else if (snapshot.data != null) {
              final values = snapshot.data!.filterValues
                  .where((item) => item.filterValue.trim().isNotEmpty)
                  .map(
                    (item) =>
                        '${item.moduleFilter?.displayLabel ?? 'Filtro'}: ${item.filterValue}',
                  )
                  .join(' | ');
              if (values.isNotEmpty) {
                lines.add('Filtros: $values');
              }
            }

            return Text(lines.join('\n'));
          },
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onOpen,
      ),
    );
  }
}

class _HomeKpiCardData {
  const _HomeKpiCardData({
    required this.title,
    required this.value,
    this.color = const Color(0xFFF7F9FF),
  });

  final String title;
  final String value;
  final Color color;
}

class _HomeKpiCard extends StatelessWidget {
  const _HomeKpiCard({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 154,
      margin: const EdgeInsets.only(right: 12),
      child: Card(
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(22),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF5E6A7C),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 34,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
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
