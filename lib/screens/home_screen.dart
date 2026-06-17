import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/app_theme.dart';
import '../models/app_profile.dart';
import '../models/app_user.dart';
import '../models/kpi_metric_source.dart';
import '../models/seller_home_kpis.dart';
import '../services/app_repository.dart';
import 'admin_screen.dart';
import 'blocked_orders_screen.dart';
import 'change_password_screen.dart';
import 'delinquency_screen.dart';
import 'performance_screen.dart';
import 'reports_screen.dart';
import 'returns_screen.dart';
import 'supplier_analysis_screen.dart';

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
  final DateFormat _dateTimeFormat = DateFormat(
    "dd/MM/yyyy 'as' HH:mm",
    'pt_BR',
  );

  bool _loading = true;
  String? _errorMessage;
  String _appVersionLabel = 'Versao 0.4.5+9';
  SellerHomeKpis _homeKpis = SellerHomeKpis.empty();

  bool get _isAdmin => widget.currentUser.isAdmin;
  bool get _isSeller => widget.currentUser.profileSlug == AppProfile.sellerSlug;
  bool get _isSupervisor =>
      widget.currentUser.profileSlug == AppProfile.supervisorSlug;
  bool get _isCoordinator =>
      widget.currentUser.profileSlug == AppProfile.coordinatorSlug;
  bool get _showsHomeKpis => !_isAdmin;
  bool get _isNamedKpiProfile => _isSeller || _isSupervisor || _isCoordinator;
  bool get _showsPerformanceModule => true;

  double get _netAmount => _homeKpis.grossAmount + _homeKpis.returnAmount;
  double get _netVolume => _homeKpis.grossVolume + _homeKpis.returnVolume;
  int get _netOrders => _homeKpis.grossOrders - _homeKpis.returnOrders;
  int get _netPositivation =>
      _homeKpis.grossPositivation - _homeKpis.returnPositivation;

  int _clampPositiveCount(int value) => value < 0 ? 0 : value;

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
        _appVersionLabel = 'Versao 0.4.5+9';
      });
    }
  }

  Future<void> _loadContent() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    try {
      final homeKpis = await _repository.getHomeKpis(
        start: start,
        end: end,
        metricSource: KpiMetricSource.venda,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _homeKpis = homeKpis;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage = 'Falha ao carregar os modulos.\n$error';
      });
    }
  }

  Future<void> _openAdministration() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminScreen(currentUser: widget.currentUser),
      ),
    );
    await _loadContent();
  }

  Future<void> _openReports() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportsScreen(currentUser: widget.currentUser),
      ),
    );
  }

  Future<void> _openSupplierAnalysis() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SupplierAnalysisScreen()),
    );
  }

  Future<void> _openPerformance() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PerformanceScreen()));
  }

  Future<void> _openReturns() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ReturnsScreen()));
  }

  Future<void> _openDelinquency() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DelinquencyScreen()));
  }

  Future<void> _openBlockedOrders() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BlockedOrdersScreen()),
    );
  }

  Future<void> _openChangePassword() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangePasswordScreen(currentUser: widget.currentUser),
      ),
    );
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
    await _openReports();
  }

  Future<void> _openSupplierAnalysisFromDrawer() async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }
    await _openSupplierAnalysis();
  }

  Future<void> _openPerformanceFromDrawer() async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }
    await _openPerformance();
  }

  Future<void> _openReturnsFromDrawer() async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }
    await _openReturns();
  }

  Future<void> _openDelinquencyFromDrawer() async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }
    await _openDelinquency();
  }

  Future<void> _openBlockedOrdersFromDrawer() async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }
    await _openBlockedOrders();
  }

  Future<void> _openChangePasswordFromDrawer() async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }
    await _openChangePassword();
  }

  String _formatCurrency(double value) => _currencyFormat.format(value);

  String _formatDecimal(double value) =>
      _decimalFormat.format(double.parse(value.toStringAsFixed(1)));

  String _formatDateTime(DateTime value) => _dateTimeFormat.format(value);

  String get _welcomeTitle {
    final displayName = widget.currentUser.displayName?.trim();
    if (_isAdmin) {
      return 'Painel da administracao';
    }
    if (displayName != null && displayName.isNotEmpty) {
      return 'Ola, $displayName';
    }
    return 'Ola, ${widget.currentUser.label}';
  }

  List<_HomeShortcutData> get _shortcutItems {
    final items = <_HomeShortcutData>[
      if (_showsPerformanceModule)
        _HomeShortcutData(
          title: 'Performance',
          icon: Icons.auto_graph_rounded,
          accent: const Color(0xFF4B61FF),
          onTap: _openPerformance,
        ),
      _HomeShortcutData(
        title: 'Fornecedor',
        icon: Icons.inventory_2_outlined,
        accent: const Color(0xFF00838F),
        onTap: _openSupplierAnalysis,
      ),
      _HomeShortcutData(
        title: 'Devolucoes',
        icon: Icons.assignment_return_outlined,
        accent: const Color(0xFFE45C5C),
        onTap: _openReturns,
      ),
      _HomeShortcutData(
        title: 'Inadimplencia',
        icon: Icons.account_balance_wallet_outlined,
        accent: const Color(0xFFFF9800),
        onTap: _openDelinquency,
      ),
      _HomeShortcutData(
        title: 'Bloqueados',
        icon: Icons.lock_clock_outlined,
        accent: const Color(0xFF7E57C2),
        onTap: _openBlockedOrders,
      ),
      if (_isAdmin)
        _HomeShortcutData(
          title: 'Administracao',
          icon: Icons.admin_panel_settings_outlined,
          accent: const Color(0xFF0B6E4F),
          onTap: _openAdministration,
        ),
      if (_isAdmin)
        _HomeShortcutData(
          title: 'Relatorios',
          icon: Icons.insights_outlined,
          accent: const Color(0xFF1E88E5),
          onTap: _openReports,
        ),
    ];

    return items;
  }

  Widget _buildWelcomeCard() {
    final roleLabel = widget.currentUser.profileName.trim().isNotEmpty
        ? widget.currentUser.profileName.trim()
        : widget.currentUser.label;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: Color(0xFFE7EBFF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_outline,
                color: primaryColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                _welcomeTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F3FF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                roleLabel,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: primaryColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiOverviewSection() {
    final compactMetrics = [
      _HomeCompactMetricData(
        label: 'Volume liquido',
        value: _formatDecimal(_netVolume),
        icon: Icons.stacked_bar_chart_rounded,
        accent: const Color(0xFF00838F),
      ),
      _HomeCompactMetricData(
        label: 'Positivacao liquida',
        value: '${_clampPositiveCount(_netPositivation)}',
        icon: Icons.people_alt_outlined,
        accent: const Color(0xFF0B6E4F),
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isNamedKpiProfile ? 'Seu resumo de hoje' : 'Resumo de hoje',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Indicadores liquidos de venda, ja considerando as devolucoes.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF5E6A7C)),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF4F7FF),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE3E9F5)),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Venda liquida',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.trending_up_rounded,
                          color: Color(0xFF4864FF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 40,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _formatCurrency(_netAmount),
                        maxLines: 1,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF4864FF),
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hoje • ${_clampPositiveCount(_netOrders)} pedidos liquidos',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF5E6A7C),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final pillWidth = constraints.maxWidth >= 320
                          ? (constraints.maxWidth - 10) / 2
                          : constraints.maxWidth;

                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: compactMetrics
                            .map(
                              (item) => SizedBox(
                                width: pillWidth,
                                child: _HomeCompactMetricPill(data: item),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleSection() {
    final shortcuts = _shortcutItems;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Modulos',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Acessos diretos aos principais fluxos do aplicativo.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF5E6A7C)),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final crossAxisCount = width >= 620
                    ? 4
                    : width >= 360
                    ? 3
                    : 2;

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 104,
                  ),
                  itemCount: shortcuts.length,
                  itemBuilder: (context, index) {
                    return _HomeShortcutTile(data: shortcuts[index]);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastUpdatesCard() {
    final items = <_HomeUpdateRowData>[
      _HomeUpdateRowData(
        label: 'Vendas',
        value: _homeKpis.lastSalesUpdatedAt != null
            ? _formatDateTime(_homeKpis.lastSalesUpdatedAt!)
            : 'Aguardando sincronizacao',
        icon: Icons.query_stats_outlined,
        accent: const Color(0xFF4864FF),
      ),
    ];

    if (_homeKpis.lastFinancialUpdatedAt != null) {
      items.add(
        _HomeUpdateRowData(
          label: 'Financeiro',
          value: _formatDateTime(_homeKpis.lastFinancialUpdatedAt!),
          icon: Icons.account_balance_wallet_outlined,
          accent: const Color(0xFF0B6E4F),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Atualizacoes',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Ultimas referencias de carga para os dados exibidos na home.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF5E6A7C)),
            ),
            const SizedBox(height: 14),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _HomeUpdateRow(data: item),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return RefreshIndicator(
      color: primaryColor,
      onRefresh: _loadContent,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          _buildWelcomeCard(),
          if (_showsHomeKpis) ...[
            const SizedBox(height: 14),
            _buildKpiOverviewSection(),
          ],
          const SizedBox(height: 14),
          _buildModuleSection(),
          if (_showsHomeKpis || _homeKpis.lastSalesUpdatedAt != null) ...[
            const SizedBox(height: 14),
            _buildLastUpdatesCard(),
          ],
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
                      'Gestao de Vendas',
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
                      title: const Text('Analise por Fornecedor'),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      onTap: _openSupplierAnalysisFromDrawer,
                    ),
                    ListTile(
                      leading: const Icon(Icons.assignment_return_outlined),
                      title: const Text('Devolucoes'),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      onTap: _openReturnsFromDrawer,
                    ),
                    ListTile(
                      leading: const Icon(Icons.warning_amber_rounded),
                      title: const Text('Inadimplencia'),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      onTap: _openDelinquencyFromDrawer,
                    ),
                    ListTile(
                      leading: const Icon(Icons.lock_clock_outlined),
                      title: const Text('Pedidos Bloqueados'),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      onTap: _openBlockedOrdersFromDrawer,
                    ),
                    if (_isAdmin) ...[
                      const SizedBox(height: 8),
                      ListTile(
                        leading: const Icon(Icons.settings_outlined),
                        title: const Text('Administracao'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        onTap: _openAdministrationFromDrawer,
                      ),
                      ListTile(
                        leading: const Icon(Icons.analytics_outlined),
                        title: const Text('Relatorios'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        onTap: _openReportsFromDrawer,
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
          _isAdmin ? 'Bem-vindo, Administracao' : 'Bem-vindo',
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

class _HomeCompactMetricData {
  const _HomeCompactMetricData({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
}

class _HomeShortcutData {
  const _HomeShortcutData({
    required this.title,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final Future<void> Function() onTap;
}

class _HomeUpdateRowData {
  const _HomeUpdateRowData({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
}

class _HomeCompactMetricPill extends StatelessWidget {
  const _HomeCompactMetricPill({required this.data});

  final _HomeCompactMetricData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE4F4)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: data.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(data.icon, color: data.accent, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6C7787),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 24,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      data.value,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeShortcutTile extends StatelessWidget {
  const _HomeShortcutTile({required this.data});

  final _HomeShortcutData data;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: data.onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE3E9F5)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: data.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(data.icon, color: data.accent, size: 20),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: Text(
                    data.title,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.1,
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

class _HomeUpdateRow extends StatelessWidget {
  const _HomeUpdateRow({required this.data});

  final _HomeUpdateRowData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3E9F5)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: data.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(data.icon, color: data.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6C7787),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data.value,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
