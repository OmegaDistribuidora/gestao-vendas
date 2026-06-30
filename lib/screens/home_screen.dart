import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../components/compact_metric_tile.dart';
import '../core/app_theme.dart';
import '../models/app_profile.dart';
import '../models/app_user.dart';
import '../models/kpi_metric_source.dart';
import '../models/seller_home_kpis.dart';
import '../services/app_repository.dart';
import 'admin_screen.dart';
import 'blocked_orders_screen.dart';
import 'change_password_screen.dart';
import 'customer_opportunities_map_screen.dart';
import 'customers_without_purchase_screen.dart';
import 'delinquency_screen.dart';
import 'performance_screen.dart';
import 'recovered_customers_screen.dart';
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

  bool _loading = true;
  String? _errorMessage;
  String _appVersionLabel = 'Versão 0.9.3+18';
  bool _customerOpportunitiesEnabled = false;
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
  bool get _showsCustomersWithoutPurchaseModule =>
      _isSeller || _isSupervisor || _isCoordinator;
  bool get _showsCustomerOpportunitiesModule =>
      (_isSeller || _isSupervisor || _isCoordinator) &&
      _customerOpportunitiesEnabled;
  bool get _showsRecoveredCustomersModule =>
      !_isSeller && !_isSupervisor && !_isCoordinator;

  double get _netAmount => _homeKpis.grossAmount + _homeKpis.returnAmount;
  double get _netVolume => _homeKpis.grossVolume + _homeKpis.returnVolume;
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
          ? 'Versão $version'
          : 'Versão $version+$buildNumber';
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
        _appVersionLabel = 'Versão 0.9.3+18';
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
      var customerOpportunitiesEnabled = _isSupervisor || _isCoordinator;
      if (_isSeller) {
        try {
          customerOpportunitiesEnabled = await _repository
              .canAccessCustomerOpportunities();
        } catch (_) {
          customerOpportunitiesEnabled = false;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _homeKpis = homeKpis;
        _customerOpportunitiesEnabled = customerOpportunitiesEnabled;
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

  Future<void> _openCustomersWithoutPurchase() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CustomersWithoutPurchaseScreen(),
      ),
    );
  }

  Future<void> _openCustomerOpportunities() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CustomerOpportunitiesMapScreen(),
      ),
    );
  }

  Future<void> _openRecoveredCustomers() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const RecoveredCustomersScreen()),
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

  Future<void> _openCustomersWithoutPurchaseFromDrawer() async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }
    await _openCustomersWithoutPurchase();
  }

  Future<void> _openCustomerOpportunitiesFromDrawer() async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }
    await _openCustomerOpportunities();
  }

  Future<void> _openRecoveredCustomersFromDrawer() async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }
    await _openRecoveredCustomers();
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

  String get _welcomeTitle {
    final displayName = widget.currentUser.displayName?.trim();
    if (_isAdmin) {
      return 'Painel da administração';
    }
    if (displayName != null && displayName.isNotEmpty) {
      return 'Olá, $displayName';
    }
    return 'Olá, ${widget.currentUser.label}';
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
        title: 'Devoluções',
        icon: Icons.assignment_return_outlined,
        accent: const Color(0xFFE45C5C),
        onTap: _openReturns,
      ),
      _HomeShortcutData(
        title: 'Inadimplência',
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
      if (_showsCustomersWithoutPurchaseModule)
        _HomeShortcutData(
          title: 'Clientes sem compra',
          icon: Icons.person_search_outlined,
          accent: const Color(0xFFD84315),
          onTap: _openCustomersWithoutPurchase,
        ),
      if (_showsCustomerOpportunitiesModule)
        _HomeShortcutData(
          title: 'Mapa de oportunidades',
          icon: Icons.map_outlined,
          accent: const Color(0xFF087B5A),
          onTap: _openCustomerOpportunities,
        ),
      if (_showsRecoveredCustomersModule)
        _HomeShortcutData(
          title: 'Clientes recuperados',
          icon: Icons.how_to_reg_outlined,
          accent: const Color(0xFF2E7D32),
          onTap: _openRecoveredCustomers,
        ),
      if (_isAdmin)
        _HomeShortcutData(
          title: 'Administração',
          icon: Icons.admin_panel_settings_outlined,
          accent: const Color(0xFF0B6E4F),
          onTap: _openAdministration,
        ),
      if (_isAdmin)
        _HomeShortcutData(
          title: 'Relatórios',
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
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [primaryColor, Color(0xFF0B1689)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: const Icon(
                  Icons.person_outline,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _welcomeTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.currentUser.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: Text(
                  roleLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKpiOverviewSection() {
    final metrics = [
      CompactMetricTile(
        title: 'Venda',
        value: _formatCurrency(_netAmount),
        icon: Icons.trending_up_rounded,
        accentColor: const Color(0xFF4864FF),
        accentBackgroundColor: const Color(0xFFE8ECFF),
      ),
      CompactMetricTile(
        title: 'Volume',
        value: _formatDecimal(_netVolume),
        icon: Icons.stacked_bar_chart_rounded,
        accentColor: const Color(0xFF00838F),
        accentBackgroundColor: const Color(0xFFE1F3F4),
      ),
      CompactMetricTile(
        title: 'Positivação',
        value: '${_clampPositiveCount(_netPositivation)}',
        icon: Icons.people_alt_outlined,
        accentColor: const Color(0xFF0B6E4F),
        accentBackgroundColor: const Color(0xFFE5F4ED),
      ),
      CompactMetricTile(
        title: 'Produtos distintos',
        value: '${_homeKpis.distinctProducts}',
        icon: Icons.inventory_2_outlined,
        accentColor: const Color(0xFF7C3AED),
        accentBackgroundColor: const Color(0xFFF0E8FF),
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isNamedKpiProfile ? 'Resumo de hoje' : 'Resumo de hoje',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (_homeKpis.lastSalesUpdatedAt != null)
                  Text(
                    'Atualizado ${DateFormat('HH:mm', 'pt_BR').format(_homeKpis.lastSalesUpdatedAt!)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF7A8597),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.builder(
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
              'Módulos',
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
                    ? 5
                    : width >= 360
                    ? 4
                    : 2;

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    mainAxisExtent: 86,
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

  Widget _buildBody() {
    return RefreshIndicator(
      color: primaryColor,
      onRefresh: _loadContent,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          _buildWelcomeCard(),
          if (_showsHomeKpis) ...[
            const SizedBox(height: 10),
            _buildKpiOverviewSection(),
          ],
          const SizedBox(height: 10),
          _buildModuleSection(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        backgroundColor: primaryColor,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 150,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primaryColor, Color(0xFF0A1484)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.trending_up_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Gestão de Vendas',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _appVersionLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      widget.currentUser.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.currentUser.profileName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(10, 18, 10, 12),
                    children: [
                      ListTile(
                        leading: const Icon(Icons.home_outlined),
                        title: const Text('Início'),
                        selected: true,
                        selectedTileColor: const Color(0xFFE7EBFF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      if (_showsPerformanceModule)
                        ListTile(
                          leading: const Icon(Icons.auto_graph_outlined),
                          title: const Text('Performance'),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          onTap: _openPerformanceFromDrawer,
                        ),
                      ListTile(
                        leading: const Icon(Icons.storefront_outlined),
                        title: const Text('Análise por Fornecedor'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onTap: _openSupplierAnalysisFromDrawer,
                      ),
                      ListTile(
                        leading: const Icon(Icons.assignment_return_outlined),
                        title: const Text('Devoluções'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onTap: _openReturnsFromDrawer,
                      ),
                      ListTile(
                        leading: const Icon(Icons.warning_amber_rounded),
                        title: const Text('Inadimplência'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onTap: _openDelinquencyFromDrawer,
                      ),
                      ListTile(
                        leading: const Icon(Icons.lock_clock_outlined),
                        title: const Text('Pedidos Bloqueados'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onTap: _openBlockedOrdersFromDrawer,
                      ),
                      if (_showsCustomersWithoutPurchaseModule)
                        ListTile(
                          leading: const Icon(Icons.person_search_outlined),
                          title: const Text('Clientes sem compra'),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          onTap: _openCustomersWithoutPurchaseFromDrawer,
                        ),
                      if (_showsCustomerOpportunitiesModule)
                        ListTile(
                          leading: const Icon(Icons.map_outlined),
                          title: const Text('Mapa de Oportunidades'),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          onTap: _openCustomerOpportunitiesFromDrawer,
                        ),
                      if (_showsRecoveredCustomersModule)
                        ListTile(
                          leading: const Icon(Icons.how_to_reg_outlined),
                          title: const Text('Clientes Recuperados'),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          onTap: _openRecoveredCustomersFromDrawer,
                        ),
                      if (_isAdmin) ...[
                        const SizedBox(height: 8),
                        ListTile(
                          leading: const Icon(Icons.settings_outlined),
                          title: const Text('Administração'),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          onTap: _openAdministrationFromDrawer,
                        ),
                        ListTile(
                          leading: const Icon(Icons.analytics_outlined),
                          title: const Text('Relatórios'),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          onTap: _openReportsFromDrawer,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Container(color: Colors.white, child: const Divider(height: 1)),
              Container(
                color: Colors.white,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    10,
                    10,
                    10,
                    MediaQuery.paddingOf(context).bottom + 6,
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.lock_outline),
                        title: const Text('Trocar senha'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onTap: _openChangePasswordFromDrawer,
                      ),
                      ListTile(
                        leading: const Icon(Icons.logout),
                        title: const Text('Sair'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onTap: () async {
                          Navigator.of(context).pop();
                          await widget.onLogout();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        title: Text('Gestão de Vendas', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            onPressed: _loadContent,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
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

class _HomeShortcutTile extends StatelessWidget {
  const _HomeShortcutTile({required this.data});

  final _HomeShortcutData data;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: data.onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE3E9F5)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: data.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(data.icon, color: data.accent, size: 19),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Center(
                  child: Text(
                    data.title,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
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
