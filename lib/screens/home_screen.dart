import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/app_theme.dart';
import '../models/app_profile.dart';
import '../models/app_user.dart';
import '../models/kpi_metric_source.dart';
import '../models/performance_overview.dart';
import '../models/seller_home_kpis.dart';
import '../services/app_repository.dart';
import '../services/push_notification_service.dart';
import '../utils/business_day_projection.dart';
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
  static const Duration _saoPauloUtcOffset = Duration(hours: -3);

  final AppRepository _repository = AppRepository.instance;
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final NumberFormat _decimalFormat = NumberFormat.decimalPattern('pt_BR');
  final NumberFormat _percentFormat = NumberFormat.decimalPattern('pt_BR');

  bool _loading = true;
  String? _errorMessage;
  String _appVersionLabel = 'Vers\u00E3o 0.9.10+25';
  bool _customerOpportunitiesEnabled = false;
  SellerHomeKpis _homeKpis = SellerHomeKpis.empty();
  PerformanceOverview _performanceOverview = PerformanceOverview.empty();
  StreamSubscription<PushNavigationIntent>? _pushNavigationSubscription;

  bool get _isAdmin => widget.currentUser.isAdmin;
  bool get _isSeller => widget.currentUser.profileSlug == AppProfile.sellerSlug;
  bool get _isSupervisor =>
      widget.currentUser.profileSlug == AppProfile.supervisorSlug;
  bool get _isCoordinator =>
      widget.currentUser.profileSlug == AppProfile.coordinatorSlug;
  bool get _showsHomeKpis => !_isAdmin;
  bool get _isNamedKpiProfile =>
      _isSeller ||
      _isSupervisor ||
      _isCoordinator ||
      widget.currentUser.profileSlug == AppProfile.boardSlug ||
      widget.currentUser.profileSlug == AppProfile.othersSlug;
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
    _pushNavigationSubscription = PushNotificationService
        .instance
        .navigationIntents
        .listen(_handlePushNavigationIntent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingIntent = PushNotificationService.instance
          .takePendingNavigationIntent();
      if (pendingIntent != null) {
        _handlePushNavigationIntent(pendingIntent);
      }
    });
    _recordModuleAccess('home', 'In\u00EDcio');
    _loadAppVersion();
    _loadContent();
  }

  @override
  void dispose() {
    _pushNavigationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version.trim();
      final buildNumber = packageInfo.buildNumber.trim();
      final versionLabel = buildNumber.isEmpty
          ? 'Vers\u00E3o $version'
          : 'Vers\u00E3o $version+$buildNumber';
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
        _appVersionLabel = 'Vers\u00E3o 0.9.10+25';
      });
    }
  }

  Future<void> _loadContent() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final today = _nowInSaoPaulo();
    final start = _saoPauloDayStartUtc(today);
    final end = _saoPauloDayEndUtc(today);

    try {
      final homeKpis = await _repository.getHomeKpis(
        start: start,
        end: end,
        metricSource: KpiMetricSource.venda,
      );
      var performanceOverview = PerformanceOverview.empty();
      if (_isNamedKpiProfile) {
        try {
          performanceOverview = await _repository.getPerformanceOverview();
        } catch (_) {
          performanceOverview = PerformanceOverview.empty();
        }
      }
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
        _performanceOverview = performanceOverview;
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
    await _recordModuleAccess('administracao', 'Administra\u00E7\u00E3o');
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminScreen(currentUser: widget.currentUser),
      ),
    );
    await _loadContent();
  }

  Future<void> _openReports() async {
    await _recordModuleAccess('relatorios', 'Relat\u00F3rios');
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportsScreen(currentUser: widget.currentUser),
      ),
    );
  }

  Future<void> _openSupplierAnalysis() async {
    await _recordModuleAccess('fornecedor', 'An\u00E1lise por Fornecedor');
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SupplierAnalysisScreen()),
    );
  }

  Future<void> _openPerformance() async {
    await _recordModuleAccess('performance', 'Performance');
    if (!mounted) {
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PerformanceScreen()));
  }

  Future<void> _handlePushNavigationIntent(PushNavigationIntent intent) async {
    if (!mounted) {
      return;
    }

    switch (intent.module) {
      case 'performance':
        await _openPerformance();
        break;
      case 'returns':
        await _openReturns();
        break;
      case 'home_daily':
        await _recordModuleAccess('home_daily_notification', 'Resumo de hoje');
        await _loadContent();
        break;
    }
  }

  Future<void> _openReturns() async {
    await _recordModuleAccess('devolucoes', 'Devolu\u00E7\u00F5es');
    if (!mounted) {
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ReturnsScreen()));
  }

  Future<void> _openDelinquency() async {
    await _recordModuleAccess('inadimplencia', 'Inadimpl\u00EAncia');
    if (!mounted) {
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DelinquencyScreen()));
  }

  Future<void> _openBlockedOrders() async {
    await _recordModuleAccess('pedidos_bloqueados', 'Pedidos Bloqueados');
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BlockedOrdersScreen()),
    );
  }

  Future<void> _openCustomersWithoutPurchase() async {
    await _recordModuleAccess('clientes_sem_compra', 'Clientes sem compra');
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CustomersWithoutPurchaseScreen(),
      ),
    );
  }

  Future<void> _openCustomerOpportunities() async {
    await _recordModuleAccess('mapa_oportunidades', 'Mapa de Oportunidades');
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CustomerOpportunitiesMapScreen(),
      ),
    );
  }

  Future<void> _openRecoveredCustomers() async {
    await _recordModuleAccess('clientes_recuperados', 'Clientes Recuperados');
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const RecoveredCustomersScreen()),
    );
  }

  Future<void> _openChangePassword() async {
    await _recordModuleAccess('trocar_senha', 'Trocar senha');
    if (!mounted) {
      return;
    }
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

  String _formatPercent(double? value) {
    if (value == null) {
      return 'Sem meta';
    }
    final fixed = double.parse(value.toStringAsFixed(1));
    return '${_percentFormat.format(fixed)}%';
  }

  Future<void> _recordModuleAccess(String moduleKey, String moduleName) {
    return _repository.recordModuleAccessSafely(
      moduleKey: moduleKey,
      moduleName: moduleName,
    );
  }

  DateTime get _projectionMonthStart {
    final now = _nowInSaoPaulo();
    return DateTime(now.year, now.month, 1);
  }

  DateTime _nowInSaoPaulo() {
    return DateTime.now().toUtc().add(_saoPauloUtcOffset);
  }

  DateTime _saoPauloDayStartUtc(DateTime saoPauloDate) {
    return DateTime.utc(
      saoPauloDate.year,
      saoPauloDate.month,
      saoPauloDate.day,
    ).subtract(_saoPauloUtcOffset);
  }

  DateTime _saoPauloDayEndUtc(DateTime saoPauloDate) {
    return _saoPauloDayStartUtc(
      saoPauloDate,
    ).add(const Duration(days: 1)).subtract(const Duration(seconds: 1));
  }

  DateTime _toSaoPauloTime(DateTime dateTime) {
    return dateTime.toUtc().add(_saoPauloUtcOffset);
  }

  String _formatSaoPauloTime(DateTime dateTime) {
    return DateFormat('HH:mm', 'pt_BR').format(_toSaoPauloTime(dateTime));
  }

  PerformanceOverviewItem? get _overallPerformanceItem =>
      _performanceOverview.overallItem;

  String _formatRequiredCurrency(BusinessDayProjectionSummary summary) {
    final targetValue = summary.targetValue;
    if (targetValue == null || targetValue <= 0) {
      return 'Sem meta';
    }
    final requiredValue = summary.requiredPerBusinessDay;
    if (requiredValue == null) {
      return 'Sem dias \u00FAteis';
    }
    return _formatCurrency(requiredValue);
  }

  String _formatRequiredInteger(BusinessDayProjectionSummary summary) {
    final targetValue = summary.targetValue;
    if (targetValue == null || targetValue <= 0) {
      return 'Sem meta';
    }
    final requiredValue = summary.requiredPerBusinessDay;
    if (requiredValue == null) {
      return 'Sem dias \u00FAteis';
    }
    return _decimalFormat.format(requiredValue.ceil());
  }

  double? _dailyProgressPct({
    required double actualToday,
    required double? dailyTarget,
  }) {
    if (dailyTarget == null || dailyTarget <= 0) {
      return null;
    }
    return (actualToday / dailyTarget) * 100;
  }

  String get _welcomeTitle {
    final displayName = widget.currentUser.displayName?.trim();
    if (_isAdmin) {
      return 'Painel da administra\u00E7\u00E3o';
    }
    if (displayName != null && displayName.isNotEmpty) {
      return 'Ol\u00E1, $displayName';
    }
    return 'Ol\u00E1, ${widget.currentUser.label}';
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
        title: 'Devolu\u00E7\u00F5es',
        icon: Icons.assignment_return_outlined,
        accent: const Color(0xFFE45C5C),
        onTap: _openReturns,
      ),
      _HomeShortcutData(
        title: 'Inadimpl\u00EAncia',
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
          title: 'Administra\u00E7\u00E3o',
          icon: Icons.admin_panel_settings_outlined,
          accent: const Color(0xFF0B6E4F),
          onTap: _openAdministration,
        ),
      if (_isAdmin)
        _HomeShortcutData(
          title: 'Relat\u00F3rios',
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
    final overallItem = _overallPerformanceItem;
    final financialSummary = overallItem == null
        ? null
        : BusinessDayProjection.summarize(
            actualValue: overallItem.actualFin,
            targetValue: overallItem.targetFin,
            monthStart: _projectionMonthStart,
          );
    final secondarySummary = overallItem == null
        ? null
        : BusinessDayProjection.summarize(
            actualValue: overallItem.secondaryActual.toDouble(),
            targetValue: overallItem.secondaryTarget?.toDouble(),
            monthStart: _projectionMonthStart,
          );
    final usesSkuMetric = overallItem?.usesSkuMetric == true;
    final secondaryActualToday = usesSkuMetric
        ? _homeKpis.distinctProducts.toDouble()
        : _clampPositiveCount(_netPositivation).toDouble();
    final secondaryMetricTitle = usesSkuMetric
        ? 'SKU'
        : 'Positiva\u00E7\u00E3o';
    final secondaryMetricValue = usesSkuMetric
        ? '${_homeKpis.distinctProducts}'
        : '${_clampPositiveCount(_netPositivation)}';
    final secondaryMetricIcon = usesSkuMetric
        ? Icons.inventory_2_outlined
        : Icons.people_alt_outlined;
    final secondaryMetricAccent = usesSkuMetric
        ? kpiSkuColor
        : kpiPositivationColor;
    final secondaryMetricBackground = usesSkuMetric
        ? kpiSkuBackgroundColor
        : kpiPositivationBackgroundColor;
    final otherMetricTitle = usesSkuMetric
        ? 'Positiva\u00E7\u00E3o'
        : 'Produtos distintos';
    final otherMetricValue = usesSkuMetric
        ? '${_clampPositiveCount(_netPositivation)}'
        : '${_homeKpis.distinctProducts}';
    final otherMetricIcon = usesSkuMetric
        ? Icons.people_alt_outlined
        : Icons.inventory_2_outlined;
    final otherMetricAccent = usesSkuMetric
        ? kpiPositivationColor
        : kpiSkuColor;
    final otherMetricBackground = usesSkuMetric
        ? kpiPositivationBackgroundColor
        : kpiSkuBackgroundColor;

    final financialProgress = _dailyProgressPct(
      actualToday: _netAmount,
      dailyTarget: financialSummary?.requiredPerBusinessDay,
    );
    final secondaryProgress = _dailyProgressPct(
      actualToday: secondaryActualToday,
      dailyTarget: secondarySummary?.requiredPerBusinessDay,
    );

    final financialActual = _TodayMetricData(
      title: 'Venda',
      value: _formatCurrency(_netAmount),
      icon: Icons.trending_up_rounded,
      accentColor: kpiFinancialColor,
      accentBackgroundColor: kpiFinancialBackgroundColor,
    );
    final financialTarget = _TodayMetricData(
      title: 'Meta Financeira de hoje',
      value: financialSummary == null
          ? 'Sem meta'
          : _formatRequiredCurrency(financialSummary),
      icon: Icons.flag_outlined,
      accentColor: kpiFinancialColor,
      accentBackgroundColor: kpiFinancialBackgroundColor,
    );
    final secondaryActual = _TodayMetricData(
      title: secondaryMetricTitle,
      value: secondaryMetricValue,
      icon: secondaryMetricIcon,
      accentColor: secondaryMetricAccent,
      accentBackgroundColor: secondaryMetricBackground,
    );
    final secondaryTarget = _TodayMetricData(
      title: usesSkuMetric
          ? 'Meta SKU de hoje'
          : 'Meta Positiva\u00E7\u00E3o de hoje',
      value: secondarySummary == null
          ? 'Sem meta'
          : _formatRequiredInteger(secondarySummary),
      icon: usesSkuMetric ? Icons.inventory_2_outlined : Icons.groups_outlined,
      accentColor: secondaryMetricAccent,
      accentBackgroundColor: secondaryMetricBackground,
    );
    final volumeMetric = _TodayMetricData(
      title: 'Volume',
      value: _formatDecimal(_netVolume),
      icon: Icons.stacked_bar_chart_rounded,
      accentColor: kpiVolumeColor,
      accentBackgroundColor: kpiVolumeBackgroundColor,
    );
    final otherMetric = _TodayMetricData(
      title: otherMetricTitle,
      value: otherMetricValue,
      icon: otherMetricIcon,
      accentColor: otherMetricAccent,
      accentBackgroundColor: otherMetricBackground,
    );

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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 14,
                        color: Color(0xFF6B7DB6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Atualizado ${_formatSaoPauloTime(_homeKpis.lastSalesUpdatedAt!)}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF7A8597),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _GroupedTodayKpiCard(
              left: financialActual,
              right: financialTarget,
              progressPercent: financialProgress,
              progressColor: kpiFinancialColor,
              progressBackgroundColor: kpiFinancialBackgroundColor,
              percentFormatter: _formatPercent,
            ),
            const SizedBox(height: 10),
            _GroupedTodayKpiCard(
              left: secondaryActual,
              right: secondaryTarget,
              progressPercent: secondaryProgress,
              progressColor: secondaryMetricAccent,
              progressBackgroundColor: secondaryMetricBackground,
              percentFormatter: _formatPercent,
            ),
            const SizedBox(height: 10),
            _GroupedTodayKpiCard(
              left: volumeMetric,
              right: otherMetric,
              showProgress: false,
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
              'M\u00F3dulos',
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
                            'Gest\u00E3o de Vendas',
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
                        title: const Text('In\u00EDcio'),
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
                        title: const Text('An\u00E1lise por Fornecedor'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onTap: _openSupplierAnalysisFromDrawer,
                      ),
                      ListTile(
                        leading: const Icon(Icons.assignment_return_outlined),
                        title: const Text('Devolu\u00E7\u00F5es'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onTap: _openReturnsFromDrawer,
                      ),
                      ListTile(
                        leading: const Icon(Icons.warning_amber_rounded),
                        title: const Text('Inadimpl\u00EAncia'),
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
                          title: const Text('Administra\u00E7\u00E3o'),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          onTap: _openAdministrationFromDrawer,
                        ),
                        ListTile(
                          leading: const Icon(Icons.analytics_outlined),
                          title: const Text('Relat\u00F3rios'),
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
        title: Text('Gest\u00E3o de Vendas', overflow: TextOverflow.ellipsis),
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

class _TodayMetricData {
  const _TodayMetricData({
    required this.title,
    required this.value,
    required this.icon,
    required this.accentColor,
    required this.accentBackgroundColor,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accentColor;
  final Color accentBackgroundColor;
}

class _GroupedTodayKpiCard extends StatelessWidget {
  const _GroupedTodayKpiCard({
    required this.left,
    required this.right,
    this.showProgress = true,
    this.progressPercent,
    this.progressColor,
    this.progressBackgroundColor,
    this.percentFormatter,
  });

  final _TodayMetricData left;
  final _TodayMetricData right;
  final bool showProgress;
  final double? progressPercent;
  final Color? progressColor;
  final Color? progressBackgroundColor;
  final String Function(double? value)? percentFormatter;

  @override
  Widget build(BuildContext context) {
    final progress = progressPercent;
    final progressValue = progress == null
        ? 0.0
        : (progress / 100).clamp(0.0, 1.0).toDouble();
    final formattedProgress = progress == null
        ? null
        : percentFormatter?.call(progress) ?? '${progress.toStringAsFixed(0)}%';
    final progressPill = progress == null ? '--' : formattedProgress!;
    final effectiveProgressColor = progressColor ?? right.accentColor;
    final effectiveProgressBackground =
        progressBackgroundColor ?? const Color(0xFFE5EAF5);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE4F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22345A).withValues(alpha: 0.035),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final useHorizontalLayout = constraints.maxWidth >= 300;
              if (!useHorizontalLayout) {
                return Column(
                  children: [
                    _TodayMetricPane(data: left),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Divider(height: 1, color: const Color(0xFFE3E8F4)),
                    ),
                    _TodayMetricPane(data: right),
                  ],
                );
              }

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _TodayMetricPane(data: left)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: const Color(0xFFE3E8F4),
                      ),
                    ),
                    Expanded(child: _TodayMetricPane(data: right)),
                  ],
                ),
              );
            },
          ),
          if (showProgress) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: progressValue,
                      minHeight: 7,
                      backgroundColor: effectiveProgressBackground,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        effectiveProgressColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: right.accentBackgroundColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    progressPill,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: right.accentColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TodayMetricPane extends StatelessWidget {
  const _TodayMetricPane({required this.data});

  final _TodayMetricData data;

  @override
  Widget build(BuildContext context) {
    final isStatusValue = data.value.startsWith('Sem ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: data.accentBackgroundColor,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(data.icon, color: data.accentColor, size: 23),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                data.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF23376D),
                  fontWeight: FontWeight.w800,
                  height: 1.12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 35,
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              data.value,
              maxLines: 1,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: data.accentColor,
                fontWeight: FontWeight.w900,
                height: 1,
                fontSize: isStatusValue ? 19 : null,
                letterSpacing: isStatusValue ? -0.2 : -0.6,
              ),
            ),
          ),
        ),
      ],
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
