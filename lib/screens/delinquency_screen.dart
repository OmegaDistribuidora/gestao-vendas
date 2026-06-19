import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_theme.dart';
import '../models/app_profile.dart';
import '../models/delinquency_overview.dart';
import '../services/app_repository.dart';

class DelinquencyScreen extends StatefulWidget {
  const DelinquencyScreen({super.key});

  @override
  State<DelinquencyScreen> createState() => _DelinquencyScreenState();
}

class _DelinquencyScreenState extends State<DelinquencyScreen> {
  final AppRepository _repository = AppRepository.instance;
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');
  final DateFormat _dateTimeFormat = DateFormat(
    "dd/MM/yyyy 'as' HH:mm",
    'pt_BR',
  );

  bool _loading = true;
  String? _errorMessage;
  DelinquencyOverview _overview = DelinquencyOverview.empty();
  String? _selectedScopeValue;
  String _searchTerm = '';

  bool get _showsScopeSelector => _scopeOptions.isNotEmpty;
  bool get _viewerIsSupervisor =>
      _overview.viewerProfileSlug == AppProfile.supervisorSlug;
  bool get _viewerIsCoordinator =>
      _overview.viewerProfileSlug == AppProfile.coordinatorSlug;

  List<DelinquencyScopeOption> get _scopeOptions {
    final seenValues = <String>{};
    final options = <DelinquencyScopeOption>[];
    for (final scope in _overview.availableScopes) {
      if (seenValues.add(scope.value)) {
        options.add(scope);
      }
    }
    return options;
  }

  List<DelinquencyGroup> get _filteredGroups {
    final term = _searchTerm.trim().toLowerCase();
    if (term.isEmpty) {
      return _overview.groups;
    }

    return _overview.groups
        .map((group) => _filterGroup(group, term))
        .whereType<DelinquencyGroup>()
        .toList();
  }

  List<DelinquencyClientSummary> get _filteredClients {
    final term = _searchTerm.trim().toLowerCase();
    if (term.isEmpty) {
      return _overview.clients;
    }

    return _overview.clients
        .map((client) => _filterClient(client, term))
        .whereType<DelinquencyClientSummary>()
        .toList();
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

  Future<void> _loadOverview({
    String? targetScopeProfileSlug,
    String? targetScopeOwnerCode,
  }) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final overview = await _repository.getDelinquencyOverview(
        targetScopeProfileSlug: targetScopeProfileSlug,
        targetScopeOwnerCode: targetScopeOwnerCode,
      );
      if (!mounted) {
        return;
      }

      final nextScopeValue = _scopeValue(
        profileSlug: overview.selectedScopeProfileSlug,
        ownerCode: overview.selectedScopeOwnerCode,
      );
      setState(() {
        _overview = overview;
        _selectedScopeValue = _scopeValueExists(overview, nextScopeValue)
            ? nextScopeValue
            : null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage = 'Falha ao carregar a inadimplencia.\n$error';
      });
    }
  }

  String? _scopeValue({String? profileSlug, String? ownerCode}) {
    if (profileSlug == null || ownerCode == null) {
      return null;
    }
    return '$profileSlug|$ownerCode';
  }

  DelinquencyScopeOption? _scopeFromValue(String? value) {
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

  DelinquencyScopeOption? get _selectedScope =>
      _scopeFromValue(_selectedScopeValue);

  bool _scopeValueExists(DelinquencyOverview overview, String? value) {
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
      return 'Filtrar supervisor';
    }
    return 'Visualizar como';
  }

  String _allScopesLabel() {
    if (_viewerIsSupervisor) {
      return 'Todos os vendedores';
    }
    if (_viewerIsCoordinator) {
      return 'Todos os supervisores';
    }
    return 'Todos';
  }

  String _profileLabel(String? slug) {
    switch (slug) {
      case AppProfile.sellerSlug:
        return 'Vendedor';
      case AppProfile.supervisorSlug:
        return 'Supervisor';
      case AppProfile.coordinatorSlug:
        return 'Coordenador';
      case AppProfile.adminSlug:
        return 'Administracao';
      case AppProfile.boardSlug:
        return 'Diretoria';
      case AppProfile.othersSlug:
        return 'Usuario';
      default:
        return 'Perfil';
    }
  }

  String _screenDescription() {
    switch (_overview.profileSlug) {
      case AppProfile.sellerSlug:
        return 'Titulos em aberto dos seus clientes, agrupados por cliente e pedido.';
      case AppProfile.supervisorSlug:
        return 'Consolidado da inadimplencia dos seus vendedores.';
      case AppProfile.coordinatorSlug:
        return 'Consolidado da inadimplencia dos seus supervisores.';
      default:
        return 'Consolidado geral de inadimplencia com filtro hierarquico.';
    }
  }

  bool _matchesText(String source, String term) {
    return source.toLowerCase().contains(term);
  }

  bool _orderMatches(DelinquencyOrderEntry order, String term) {
    return _matchesText(order.numped, term) ||
        _matchesText(order.prestacao, term) ||
        _matchesText(order.duplicata, term) ||
        _matchesText(order.tipo, term);
  }

  DelinquencyClientSummary? _filterClient(
    DelinquencyClientSummary client,
    String term,
  ) {
    final clientMatches =
        _matchesText(client.codcli, term) ||
        _matchesText(client.clientName, term);
    final filteredOrders = clientMatches
        ? client.orders
        : client.orders.where((order) => _orderMatches(order, term)).toList();

    if (!clientMatches && filteredOrders.isEmpty) {
      return null;
    }

    if (clientMatches) {
      return client;
    }

    final totalAmount = filteredOrders.fold<double>(
      0,
      (sum, order) => sum + order.valor,
    );
    final totalOrders = filteredOrders
        .map((order) => order.numped)
        .toSet()
        .length;

    return client.copyWith(
      totalAmount: totalAmount,
      totalOrders: totalOrders,
      orders: filteredOrders,
    );
  }

  DelinquencyGroup? _filterGroup(DelinquencyGroup group, String term) {
    final groupMatches =
        _matchesText(group.code, term) ||
        _matchesText(group.displayName, term) ||
        _matchesText(group.label, term) ||
        _matchesText(_profileLabel(group.profileSlug), term);

    final filteredClients = groupMatches
        ? group.clients
        : group.clients
              .map((client) => _filterClient(client, term))
              .whereType<DelinquencyClientSummary>()
              .toList();

    if (!groupMatches && filteredClients.isEmpty) {
      return null;
    }

    if (groupMatches) {
      return group;
    }

    final totalAmount = filteredClients.fold<double>(
      0,
      (sum, client) => sum + client.totalAmount,
    );
    final totalOrders = filteredClients.fold<int>(
      0,
      (sum, client) => sum + client.totalOrders,
    );

    return group.copyWith(
      totalAmount: totalAmount,
      totalOrders: totalOrders,
      totalClients: filteredClients.length,
      clients: filteredClients,
    );
  }

  String _formatCurrency(double value) => _currencyFormat.format(value);

  String _formatMetricCurrency(double value) {
    return _formatCurrency(value);
  }

  Widget _dropdownLabel(String text) {
    return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
  }

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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF5E6A7C),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 40,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: accentBackgroundColor,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: accentColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Inadimplencia',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _screenDescription(),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF5E6A7C)),
            ),
            if (_showsScopeSelector) ...[
              const SizedBox(height: 18),
              DropdownButtonFormField<String?>(
                key: ValueKey<String?>(_selectedScopeValue),
                initialValue: _scopeValueExists(_overview, _selectedScopeValue)
                    ? _selectedScopeValue
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _scopeSelectorLabel(),
                  prefixIcon: const Icon(Icons.account_tree_outlined),
                ),
                items: <DropdownMenuItem<String?>>[
                  DropdownMenuItem<String?>(
                    value: null,
                    child: _dropdownLabel(_allScopesLabel()),
                  ),
                  ..._scopeOptions.map(
                    (scope) => DropdownMenuItem<String?>(
                      value: scope.value,
                      child: _dropdownLabel(
                        '${_profileLabel(scope.profileSlug)} - ${scope.label}',
                      ),
                    ),
                  ),
                ],
                onChanged: _handleScopeChanged,
              ),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                labelText: 'Buscar',
                hintText: 'Codigo, nome, pedido, prestacao ou duplicata',
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
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumo atual',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            _buildMetricCard(
              title: 'Valor em aberto',
              value: _formatMetricCurrency(_overview.totalAmount),
              icon: Icons.attach_money_outlined,
              accentColor: const Color(0xFFB42318),
              accentBackgroundColor: const Color(0xFFFDECEC),
            ),
            const SizedBox(height: 12),
            _buildMetricCard(
              title: 'Pedidos',
              value: '${_overview.totalOrders}',
              icon: Icons.receipt_long_outlined,
              accentColor: const Color(0xFF1D4ED8),
              accentBackgroundColor: const Color(0xFFE8EEFF),
            ),
            const SizedBox(height: 12),
            _buildMetricCard(
              title: 'Clientes',
              value: '${_overview.totalClients}',
              icon: Icons.people_outline,
              accentColor: const Color(0xFF7C3AED),
              accentBackgroundColor: const Color(0xFFF2EAFE),
            ),
          ],
        ),
      ),
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

  Widget _buildOrderTile(DelinquencyOrderEntry order) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1E6F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pedido ${order.numped}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                _formatCurrency(order.valor),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoPill(label: 'Emissao: ${_formatDate(order.dtemissao)}'),
              _InfoPill(label: 'Vencimento: ${_formatDate(order.dtvenc)}'),
              if (order.prestacao.trim().isNotEmpty)
                _InfoPill(label: 'Prestacao: ${order.prestacao}'),
              if (order.duplicata.trim().isNotEmpty)
                _InfoPill(label: 'Duplicata: ${order.duplicata}'),
              if (order.tipo.trim().isNotEmpty) _InfoPill(label: order.tipo),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClientTile(
    DelinquencyClientSummary client, {
    required String storageKeyPrefix,
    Color backgroundColor = Colors.white,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E6F5)),
      ),
      child: ExpansionTile(
        key: PageStorageKey<String>('$storageKeyPrefix-${client.codcli}'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(
          '${client.codcli} - ${client.clientName}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Valor: ${_formatCurrency(client.totalAmount)} - Pedidos: ${client.totalOrders}',
          ),
        ),
        children: client.orders.map(_buildOrderTile).toList(),
      ),
    );
  }

  Widget _buildGroupCard(DelinquencyGroup group) {
    return Card(
      child: ExpansionTile(
        key: PageStorageKey<String>('group-${group.profileSlug}-${group.code}'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFE7EBFF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.groups_outlined, color: primaryColor),
        ),
        title: Text(
          '${_profileLabel(group.profileSlug)} - ${group.label}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Valor: ${_formatCurrency(group.totalAmount)} - Pedidos: ${group.totalOrders} - Clientes: ${group.totalClients}',
          ),
        ),
        children: group.clients
            .map(
              (client) => _buildClientTile(
                client,
                storageKeyPrefix: 'group-${group.code}',
                backgroundColor: const Color(0xFFFDFEFF),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildContent() {
    final groups = _filteredGroups;
    final clients = _filteredClients;
    final hasGroups = groups.isNotEmpty;
    final hasClients = clients.isNotEmpty;

    return RefreshIndicator(
      color: primaryColor,
      onRefresh: _reloadCurrentOverview,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          _buildHeaderCard(),
          const SizedBox(height: 12),
          _buildSummaryCard(),
          const SizedBox(height: 16),
          if (!hasGroups && !hasClients)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhuma inadimplencia encontrada para o filtro informado.',
                ),
              ),
            )
          else if (hasGroups)
            ...groups.map(
              (group) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildGroupCard(group),
              ),
            )
          else
            ...clients.map(
              (client) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: _buildClientTile(
                      client,
                      storageKeyPrefix: 'client',
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          _buildLastUpdateCard(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inadimplencia')),
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
                  _ErrorCard(
                    message: _errorMessage!,
                    onRetry: _reloadCurrentOverview,
                  ),
                ],
              )
            : _buildContent(),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE1E6F5)),
      ),
      child: Text(label),
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
