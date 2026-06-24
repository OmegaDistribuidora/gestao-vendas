import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_theme.dart';
import '../models/app_profile.dart';
import '../models/customers_without_purchase.dart';
import '../services/app_repository.dart';

class CustomersWithoutPurchaseScreen extends StatefulWidget {
  const CustomersWithoutPurchaseScreen({super.key});

  @override
  State<CustomersWithoutPurchaseScreen> createState() =>
      _CustomersWithoutPurchaseScreenState();
}

class _CustomersWithoutPurchaseScreenState
    extends State<CustomersWithoutPurchaseScreen> {
  final AppRepository _repository = AppRepository.instance;
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final NumberFormat _decimalFormat = NumberFormat.decimalPattern('pt_BR');
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');
  final DateFormat _dateTimeFormat = DateFormat(
    "dd/MM/yyyy 'as' HH:mm",
    'pt_BR',
  );

  bool _loading = true;
  String? _errorMessage;
  String? _selectedScopeValue;
  String? _selectedSupplierCode;
  String _selectedStatusFilter = 'all';
  String? _selectedDistrictKey;
  String? _selectedRegularityFilter;
  String _searchTerm = '';
  DateTime _selectedMonthStart = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );
  CustomersWithoutPurchaseOverview _overview =
      CustomersWithoutPurchaseOverview.empty();

  bool get _viewerIsSupervisor =>
      _overview.viewerProfileSlug == AppProfile.supervisorSlug;
  bool get _viewerIsCoordinator =>
      _overview.viewerProfileSlug == AppProfile.coordinatorSlug;
  bool get _showsScopeSelector => _scopeOptions.isNotEmpty;
  bool get _showsSupplierSelector => _supplierOptions.isNotEmpty;

  List<CustomerScopeOption> get _scopeOptions {
    final seenValues = <String>{};
    final options = <CustomerScopeOption>[];
    for (final scope in _overview.availableScopes) {
      if (seenValues.add(scope.value)) {
        options.add(scope);
      }
    }
    return options;
  }

  List<CustomerSupplierOption> get _supplierOptions {
    final seenValues = <String>{};
    final options = <CustomerSupplierOption>[];
    for (final supplier in _overview.availableSuppliers) {
      if (seenValues.add(supplier.code)) {
        options.add(supplier);
      }
    }
    return options;
  }

  List<_DistrictFilterOption> get _districtOptions {
    final labelsByKey = <String, String>{};
    for (final customer in _overview.customers) {
      final label = customer.district.trim();
      if (label.isEmpty) {
        continue;
      }
      labelsByKey.putIfAbsent(label.toLowerCase(), () => label);
    }
    final options = labelsByKey.entries
        .map(
          (entry) => _DistrictFilterOption(key: entry.key, label: entry.value),
        )
        .toList();
    options.sort((a, b) => a.label.compareTo(b.label));
    return options;
  }

  List<_MonthOption> get _monthOptions {
    final now = DateTime.now();
    final current = DateTime(now.year, now.month, 1);
    final first = DateTime(2026, 1, 1);
    final options = <_MonthOption>[];

    var cursor = current;
    while (!cursor.isBefore(first)) {
      options.add(
        _MonthOption(
          value: _monthValue(cursor),
          label: DateFormat("MMMM 'de' yyyy", 'pt_BR').format(cursor),
        ),
      );
      cursor = DateTime(cursor.year, cursor.month - 1, 1);
    }
    return options;
  }

  List<CustomerWithoutPurchase> get _filteredCustomers {
    final term = _searchTerm.trim().toLowerCase();
    return _overview.customers.where((customer) {
      final isBlocked = customer.status.toLowerCase() == 'bloqueado';
      if (_selectedStatusFilter == 'blocked' && !isBlocked) {
        return false;
      }
      if (_selectedStatusFilter == 'unblocked' && isBlocked) {
        return false;
      }
      if (_selectedDistrictKey != null &&
          customer.district.trim().toLowerCase() != _selectedDistrictKey) {
        return false;
      }
      if (_selectedRegularityFilter != null &&
          customer.regularityLabel != _selectedRegularityFilter) {
        return false;
      }
      if (term.isEmpty) {
        return true;
      }
      return customer.codcli.toLowerCase().contains(term) ||
          customer.clientName.toLowerCase().contains(term) ||
          customer.fantasia.toLowerCase().contains(term) ||
          customer.cnpj.toLowerCase().contains(term) ||
          customer.status.toLowerCase().contains(term) ||
          customer.blockReason.toLowerCase().contains(term) ||
          customer.address.toLowerCase().contains(term) ||
          customer.district.toLowerCase().contains(term) ||
          customer.cityName.toLowerCase().contains(term) ||
          customer.codusur.toLowerCase().contains(term) ||
          customer.sellerName.toLowerCase().contains(term) ||
          customer.supervisorName.toLowerCase().contains(term) ||
          customer.coordinatorName.toLowerCase().contains(term) ||
          customer.regularityLabel.toLowerCase().contains(term);
    }).toList();
  }

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

  DateTime get _periodStart => _selectedMonthStart;

  DateTime get _periodEnd => DateTime(
    _selectedMonthStart.year,
    _selectedMonthStart.month + 1,
    0,
    23,
    59,
    59,
  );

  String get _periodDescription =>
      DateFormat("MMMM 'de' yyyy", 'pt_BR').format(_selectedMonthStart);

  String _monthValue(DateTime value) =>
      DateTime(value.year, value.month, 1).toIso8601String().split('T').first;

  Future<void> _loadOverview({
    String? targetScopeProfileSlug,
    String? targetScopeOwnerCode,
  }) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final overview = await _repository.getCustomersWithoutPurchase(
        start: _periodStart,
        end: _periodEnd,
        targetScopeProfileSlug: targetScopeProfileSlug,
        targetScopeOwnerCode: targetScopeOwnerCode,
        targetSupplierCode: _selectedSupplierCode,
      );
      if (!mounted) {
        return;
      }
      final nextScopeValue = _scopeValue(
        profileSlug: overview.selectedScopeProfileSlug,
        ownerCode: overview.selectedScopeOwnerCode,
      );
      final availableDistrictKeys = overview.customers
          .map((customer) => customer.district.trim().toLowerCase())
          .where((district) => district.isNotEmpty)
          .toSet();
      setState(() {
        _overview = overview;
        _selectedScopeValue = _scopeValueExists(overview, nextScopeValue)
            ? nextScopeValue
            : null;
        _selectedSupplierCode =
            overview.availableSuppliers.any(
              (supplier) => supplier.code == _selectedSupplierCode,
            )
            ? _selectedSupplierCode
            : null;
        _selectedDistrictKey =
            availableDistrictKeys.contains(_selectedDistrictKey)
            ? _selectedDistrictKey
            : null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = 'Falha ao carregar clientes sem compra.\n$error';
      });
    }
  }

  Future<void> _handleMonthChanged(String? value) async {
    if (value == null || value == _monthValue(_selectedMonthStart)) {
      return;
    }

    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return;
    }

    setState(() {
      _selectedMonthStart = DateTime(parsed.year, parsed.month, 1);
    });
    await _reloadCurrentOverview();
  }

  String? _scopeValue({String? profileSlug, String? ownerCode}) {
    if (profileSlug == null || ownerCode == null) {
      return null;
    }
    return '$profileSlug|$ownerCode';
  }

  CustomerScopeOption? _scopeFromValue(String? value) {
    if (value == null) {
      return null;
    }

    for (final scope in _scopeOptions) {
      if (scope.value == value) {
        return scope;
      }
    }
    return null;
  }

  CustomerScopeOption? get _selectedScope =>
      _scopeFromValue(_selectedScopeValue);

  bool _scopeValueExists(
    CustomersWithoutPurchaseOverview overview,
    String? value,
  ) {
    if (value == null) {
      return true;
    }
    final seenValues = <String>{};
    for (final scope in overview.availableScopes) {
      if (seenValues.add(scope.value) && scope.value == value) {
        return true;
      }
    }
    return false;
  }

  bool _supplierValueExists(String? value) {
    if (value == null) {
      return true;
    }
    return _supplierOptions.any((supplier) => supplier.code == value);
  }

  Future<void> _handleScopeChanged(String? value) async {
    if (value == _selectedScopeValue) {
      return;
    }

    final selectedScope = _scopeFromValue(value);
    await _loadOverview(
      targetScopeProfileSlug: selectedScope?.profileSlug,
      targetScopeOwnerCode: selectedScope?.ownerCode,
    );
  }

  Future<void> _handleSupplierChanged(String? value) async {
    if (value == _selectedSupplierCode) {
      return;
    }

    setState(() {
      _selectedSupplierCode = value;
    });
    await _reloadCurrentOverview();
  }

  void _handleStatusFilterChanged(String? value) {
    if (value == null || value == _selectedStatusFilter) {
      return;
    }
    setState(() {
      _selectedStatusFilter = value;
    });
  }

  void _handleDistrictFilterChanged(String? value) {
    if (value == _selectedDistrictKey) {
      return;
    }
    setState(() {
      _selectedDistrictKey = value;
    });
  }

  void _handleRegularityFilterChanged(String? value) {
    setState(() {
      _selectedRegularityFilter = value == _selectedRegularityFilter
          ? null
          : value;
    });
  }

  Future<void> _reloadCurrentOverview() {
    return _loadOverview(
      targetScopeProfileSlug: _selectedScope?.profileSlug,
      targetScopeOwnerCode: _selectedScope?.ownerCode,
    );
  }

  String _scopeSelectorLabel() {
    if (_viewerIsSupervisor) {
      return 'Filtrar vendedor';
    }
    if (_viewerIsCoordinator) {
      return 'Filtrar supervisor ou vendedor';
    }
    return 'Visualizar como';
  }

  String _allScopesLabel() {
    if (_viewerIsSupervisor) {
      return 'Todos os vendedores';
    }
    if (_viewerIsCoordinator) {
      return 'Toda a coordenacao';
    }
    return 'Todos';
  }

  String _formatCurrency(double value) => _currencyFormat.format(value);

  String _formatVolume(double value) =>
      _decimalFormat.format(double.parse(value.toStringAsFixed(1)));

  String _formatDate(DateTime? value) {
    if (value == null) {
      return 'Nunca comprou';
    }
    return _dateFormat.format(value);
  }

  Color _stalenessColor(int daysWithoutPurchase) {
    final ratio = (daysWithoutPurchase.clamp(1, 30) - 1) / 29;
    return Color.lerp(const Color(0xFFF2C94C), const Color(0xFFE53935), ratio)!;
  }

  Color _regularityColor(String label) {
    switch (label) {
      case 'Regular':
        return const Color(0xFF0B6E4F);
      case 'Semi-Regular':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF5E6A7C);
    }
  }

  void _showRecentOrders(CustomerWithoutPurchase customer) {
    showModalBottomSheet<void>(
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
                  '${customer.codcli} - ${customer.displayName}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Vendedor: ${customer.codusur} - ${customer.sellerName}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5E6A7C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: customer.recentOrders.isEmpty
                      ? const Center(
                          child: Text('Este cliente ainda nao tem pedidos.'),
                        )
                      : ListView.separated(
                          itemCount: customer.recentOrders.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final order = customer.recentOrders[index];
                            return Card(
                              margin: EdgeInsets.zero,
                              child: ExpansionTile(
                                tilePadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 4,
                                ),
                                childrenPadding: const EdgeInsets.fromLTRB(
                                  14,
                                  0,
                                  14,
                                  14,
                                ),
                                title: Text(
                                  'Pedido #${order.numped}',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _InfoChip(
                                        icon: Icons.event_outlined,
                                        label: _formatDate(order.salesDate),
                                      ),
                                      _InfoChip(
                                        icon: Icons.attach_money_outlined,
                                        label: _formatCurrency(
                                          order.totalAmount,
                                        ),
                                      ),
                                      _InfoChip(
                                        icon: Icons.widgets_outlined,
                                        label:
                                            'Vol. ${_formatVolume(order.totalVolume)}',
                                      ),
                                      _InfoChip(
                                        icon: Icons.inventory_2_outlined,
                                        label: '${order.itemCount} item(ns)',
                                      ),
                                    ],
                                  ),
                                ),
                                children: [
                                  if (order.items.isEmpty)
                                    const Align(
                                      alignment: Alignment.centerLeft,
                                      child: Padding(
                                        padding: EdgeInsets.only(top: 8),
                                        child: Text(
                                          'Detalhes do pedido ainda nao carregados.',
                                        ),
                                      ),
                                    )
                                  else
                                    ...order.items.map(
                                      (item) => _OrderItemRow(
                                        item: item,
                                        formatCurrency: _formatCurrency,
                                        formatVolume: _formatVolume,
                                      ),
                                    ),
                                ],
                              ),
                            );
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

  Widget _buildFiltersCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Clientes sem compra',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Clientes da base selecionada que nao compraram no mes.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF5E6A7C)),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _monthValue(_selectedMonthStart),
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Mes',
                prefixIcon: Icon(Icons.calendar_month_outlined),
              ),
              items: _monthOptions
                  .map(
                    (month) => DropdownMenuItem<String>(
                      value: month.value,
                      child: Text(month.label),
                    ),
                  )
                  .toList(),
              onChanged: _handleMonthChanged,
            ),
            if (_showsScopeSelector) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _scopeValueExists(_overview, _selectedScopeValue)
                    ? _selectedScopeValue
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _scopeSelectorLabel(),
                  prefixIcon: const Icon(Icons.account_tree_outlined),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(_allScopesLabel()),
                  ),
                  ..._scopeOptions.map(
                    (scope) => DropdownMenuItem<String?>(
                      value: scope.value,
                      child: Text(scope.label),
                    ),
                  ),
                ],
                onChanged: _handleScopeChanged,
              ),
            ],
            if (_showsSupplierSelector) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _supplierValueExists(_selectedSupplierCode)
                    ? _selectedSupplierCode
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Fornecedor',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todos os fornecedores'),
                  ),
                  ..._supplierOptions.map(
                    (supplier) => DropdownMenuItem<String?>(
                      value: supplier.code,
                      child: Text(
                        supplier.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: _handleSupplierChanged,
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey<String>('customer-status-$_selectedStatusFilter'),
              initialValue: _selectedStatusFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Status do cliente',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
              items: const [
                DropdownMenuItem<String>(
                  value: 'all',
                  child: Text('Bloqueados e desbloqueados'),
                ),
                DropdownMenuItem<String>(
                  value: 'blocked',
                  child: Text('Somente bloqueados'),
                ),
                DropdownMenuItem<String>(
                  value: 'unblocked',
                  child: Text('Somente desbloqueados'),
                ),
              ],
              onChanged: _handleStatusFilterChanged,
            ),
            if (_districtOptions.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: ValueKey<String>(
                  'customer-district-${_selectedDistrictKey ?? 'all'}',
                ),
                initialValue: _selectedDistrictKey,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Bairro',
                  prefixIcon: Icon(Icons.holiday_village_outlined),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todos os bairros'),
                  ),
                  ..._districtOptions.map(
                    (district) => DropdownMenuItem<String?>(
                      value: district.key,
                      child: Text(
                        district.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: _handleDistrictFilterChanged,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final filteredCustomers = _filteredCustomers;
    final regularClients = filteredCustomers
        .where((customer) => customer.regularityLabel == 'Regular')
        .length;
    final semiRegularClients = filteredCustomers
        .where((customer) => customer.regularityLabel == 'Semi-Regular')
        .length;
    final normalClients = filteredCustomers
        .where((customer) => customer.regularityLabel == 'Normal')
        .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.people_alt_outlined, color: primaryColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _periodDescription,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _SummaryPill(
                  label: 'Total',
                  value: '${filteredCustomers.length}',
                  color: primaryColor,
                  selected: _selectedRegularityFilter == null,
                  onTap: () => _handleRegularityFilterChanged(null),
                ),
                _SummaryPill(
                  label: 'Regular',
                  value: '$regularClients',
                  color: const Color(0xFF0B6E4F),
                  selected: _selectedRegularityFilter == 'Regular',
                  onTap: () => _handleRegularityFilterChanged('Regular'),
                ),
                _SummaryPill(
                  label: 'Semi-Regular',
                  value: '$semiRegularClients',
                  color: const Color(0xFFFF9800),
                  selected: _selectedRegularityFilter == 'Semi-Regular',
                  onTap: () => _handleRegularityFilterChanged('Semi-Regular'),
                ),
                _SummaryPill(
                  label: 'Normal',
                  value: '$normalClients',
                  color: const Color(0xFF5E6A7C),
                  selected: _selectedRegularityFilter == 'Normal',
                  onTap: () => _handleRegularityFilterChanged('Normal'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastUpdateCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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

  Widget _buildCustomerCard(CustomerWithoutPurchase customer) {
    final borderColor = _stalenessColor(customer.daysWithoutPurchase);
    final regularityColor = _regularityColor(customer.regularityLabel);
    final isBlocked = customer.status.toLowerCase() == 'bloqueado';
    final cityLabel = [
      customer.cityName,
      customer.uf,
    ].where((part) => part.trim().isNotEmpty).join(' - ');

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: borderColor.withValues(alpha: 0.72),
          width: 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _showRecentOrders(customer),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: borderColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.storefront_outlined, color: borderColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${customer.codcli} - ${customer.displayName}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (isBlocked) ...[
                          const SizedBox(height: 6),
                          const _BlockedBadge(),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          customer.fantasia.isNotEmpty
                              ? customer.fantasia
                              : customer.cnpj,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF5E6A7C)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF8A94A6),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    icon: Icons.person_outline,
                    label: '${customer.codusur} - ${customer.sellerName}',
                  ),
                  _InfoChip(
                    icon: Icons.local_fire_department_outlined,
                    label: customer.daysWithoutPurchase >= 9999
                        ? 'Nunca comprou'
                        : '${customer.daysWithoutPurchase} dia(s) sem compra',
                    color: borderColor,
                  ),
                  _InfoChip(
                    icon: Icons.verified_outlined,
                    label: customer.regularityLabel,
                    color: regularityColor,
                  ),
                ],
              ),
              if (isBlocked && customer.blockReason.isNotEmpty) ...[
                const SizedBox(height: 10),
                _InfoChip(
                  icon: Icons.report_problem_outlined,
                  label: customer.blockReason,
                  color: const Color(0xFFFFB300),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _MiniValue(
                      label: 'Últ. Compra',
                      value: _formatDate(customer.lastPurchaseDate),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniValue(
                      label: 'Valor',
                      value: customer.lastPurchaseDate == null
                          ? '--'
                          : _formatCurrency(customer.lastPurchaseAmount),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniValue(
                      label: 'Limite',
                      value: _formatCurrency(customer.creditLimit),
                    ),
                  ),
                ],
              ),
              if (customer.address.isNotEmpty ||
                  customer.district.isNotEmpty ||
                  cityLabel.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (customer.address.isNotEmpty)
                      _InfoChip(
                        icon: Icons.signpost_outlined,
                        label: customer.address,
                      ),
                    if (customer.district.isNotEmpty)
                      _InfoChip(
                        icon: Icons.location_city_outlined,
                        label: customer.district,
                      ),
                    if (cityLabel.isNotEmpty)
                      _InfoChip(icon: Icons.map_outlined, label: cityLabel),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes sem compra'),
        actions: [
          IconButton(
            onPressed: _reloadCurrentOverview,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: primaryColor,
          onRefresh: _reloadCurrentOverview,
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
                      onRetry: _reloadCurrentOverview,
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                  children: [
                    _buildFiltersCard(),
                    const SizedBox(height: 12),
                    _buildSummaryCard(),
                    const SizedBox(height: 12),
                    _buildLastUpdateCard(),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        labelText:
                            'Buscar por cliente, fantasia, CNPJ ou vendedor',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchTerm = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Clientes',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          '${_filteredCustomers.length} cliente(s)',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF5E6A7C)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_filteredCustomers.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('Nenhum cliente sem compra encontrado.'),
                        ),
                      )
                    else
                      ..._filteredCustomers.map(
                        (customer) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildCustomerCard(customer),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.label,
    required this.value,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? color.withValues(alpha: 0.18)
          : color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: color.withValues(alpha: selected ? 0.72 : 0.18),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: selected ? color : const Color(0xFF5E6A7C),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniValue extends StatelessWidget {
  const _MiniValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E6F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF5E6A7C),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: double.infinity,
            height: 22,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                softWrap: false,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockedBadge extends StatelessWidget {
  const _BlockedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB300).withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFFFB300).withValues(alpha: 0.28),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFB87500)),
          SizedBox(width: 5),
          Text(
            'Bloqueado',
            style: TextStyle(
              color: Color(0xFFB87500),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderItemRow extends StatelessWidget {
  const _OrderItemRow({
    required this.item,
    required this.formatCurrency,
    required this.formatVolume,
  });

  final CustomerRecentOrderItem item;
  final String Function(double value) formatCurrency;
  final String Function(double value) formatVolume;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1E6F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${item.codprod} - ${item.productName}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '${item.codfornec} - ${item.supplierName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF5E6A7C),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.attach_money_outlined,
                label: formatCurrency(item.itemValue),
              ),
              _InfoChip(
                icon: Icons.format_list_numbered_outlined,
                label: 'Qtd. ${formatVolume(item.quantity)}',
              ),
              _InfoChip(
                icon: Icons.widgets_outlined,
                label: 'Vol. ${formatVolume(item.volume)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DistrictFilterOption {
  const _DistrictFilterOption({required this.key, required this.label});

  final String key;
  final String label;
}

class _MonthOption {
  const _MonthOption({required this.value, required this.label});

  final String value;
  final String label;
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
