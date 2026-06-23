import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_theme.dart';
import '../models/app_profile.dart';
import '../models/customer_opportunities.dart';
import '../services/app_repository.dart';

class CustomerOpportunitiesMapScreen extends StatefulWidget {
  const CustomerOpportunitiesMapScreen({super.key});

  @override
  State<CustomerOpportunitiesMapScreen> createState() =>
      _CustomerOpportunitiesMapScreenState();
}

class _CustomerOpportunitiesMapScreenState
    extends State<CustomerOpportunitiesMapScreen> {
  static const LatLng _brazilCenter = LatLng(-14.235, -51.9253);

  final AppRepository _repository = AppRepository.instance;
  final MapController _mapController = MapController();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  final DateFormat _dateTimeFormat = DateFormat(
    "dd/MM/yyyy 'as' HH:mm",
    'pt_BR',
  );

  CustomerOpportunitiesOverview _overview =
      CustomerOpportunitiesOverview.empty();
  bool _loading = true;
  String? _errorMessage;
  String? _selectedSupervisorCode;
  String? _selectedSellerCode;
  String? _selectedNeighborhoodKey;
  String? _selectedActivityKey;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final overview = await _repository.getCustomerOpportunities(
        targetSupervisorCode: _selectedSupervisorCode,
        targetSellerCode: _selectedSellerCode,
        targetNeighborhoodKey: _selectedNeighborhoodKey,
        targetActivityKey: _selectedActivityKey,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _overview = overview;
        _selectedSupervisorCode = overview.selectedSupervisorCode;
        _selectedSellerCode = overview.selectedSellerCode;
        _selectedNeighborhoodKey = overview.selectedNeighborhoodKey.isEmpty
            ? null
            : overview.selectedNeighborhoodKey;
        _selectedActivityKey = overview.selectedActivityKey.isEmpty
            ? null
            : overview.selectedActivityKey;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusSelection());
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = 'Nao foi possivel carregar as oportunidades.\n$error';
      });
    }
  }

  void _focusSelection() {
    if (!mounted) {
      return;
    }
    if (_overview.opportunities.isNotEmpty) {
      final points = _overview.opportunities
          .map((item) => LatLng(item.latitude, item.longitude))
          .toList(growable: false);
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.fromLTRB(44, 330, 44, 72),
          maxZoom: 15,
        ),
      );
      return;
    }

    for (final neighborhood in _overview.servedNeighborhoods) {
      if (neighborhood.key == _selectedNeighborhoodKey) {
        _mapController.move(
          LatLng(neighborhood.centerLatitude, neighborhood.centerLongitude),
          13,
        );
        return;
      }
    }
  }

  Future<void> _handleSupervisorChanged(String? value) async {
    if (value == _selectedSupervisorCode) {
      return;
    }
    setState(() {
      _selectedSupervisorCode = value;
      _selectedSellerCode = null;
      _selectedNeighborhoodKey = null;
      _selectedActivityKey = null;
    });
    await _loadData();
  }

  Future<void> _handleSellerChanged(String? value) async {
    if (value == _selectedSellerCode) {
      return;
    }
    setState(() {
      _selectedSellerCode = value;
      _selectedNeighborhoodKey = null;
      _selectedActivityKey = null;
    });
    await _loadData();
  }

  Future<void> _handleNeighborhoodChanged(String? value) async {
    if (value == null || value == _selectedNeighborhoodKey) {
      return;
    }
    setState(() {
      _selectedNeighborhoodKey = value;
      _selectedActivityKey = null;
    });
    await _loadData();
  }

  Future<void> _handleActivityChanged(String? value) async {
    final normalizedValue = value == null || value.isEmpty ? null : value;
    if (normalizedValue == _selectedActivityKey) {
      return;
    }
    setState(() {
      _selectedActivityKey = normalizedValue;
    });
    await _loadData();
  }

  Future<void> _showOpportunity(CustomerOpportunity opportunity) async {
    final details = _repository.getCustomerOpportunityDetails(
      opportunity.taxId,
      targetSellerCode: _overview.selectedSellerCode,
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _OpportunityDetailsLoader(
        details: details,
        currencyFormat: _currencyFormat,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de Oportunidades'),
        actions: [
          IconButton(
            tooltip: 'Atualizar oportunidades',
            onPressed: _loading ? null : _loadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return _ErrorState(message: _errorMessage!, onRetry: _loadData);
    }
    if (_overview.accessDenied) {
      return _EmptyState(
        icon: Icons.hide_source_outlined,
        title: 'Modulo indisponivel',
        message: _overview.accessDeniedReason,
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: _brazilCenter,
              initialZoom: 4,
              minZoom: 3,
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'br.com.omegadistribuidora.gestao_vendas',
                maxNativeZoom: 19,
              ),
              MarkerClusterLayerWidget(
                key: ValueKey<String>(
                  '${_selectedSellerCode ?? ''}|'
                  '${_selectedNeighborhoodKey ?? ''}|'
                  '${_selectedActivityKey ?? ''}',
                ),
                options: MarkerClusterLayerOptions(
                  markers: _buildMarkers(),
                  size: const Size(44, 44),
                  maxClusterRadius: 56,
                  disableClusteringAtZoom: 17,
                  markerChildBehavior: true,
                  padding: const EdgeInsets.all(48),
                  builder: (context, markers) => Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x44000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          '${markers.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const RichAttributionWidget(
                attributions: [TextSourceAttribution('OpenStreetMap')],
              ),
            ],
          ),
        ),
        if (_overview.opportunities.isEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(36, 250, 36, 80),
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.94),
                    elevation: 2,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      child: Text(
                        _emptyMapMessage(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF465267),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: _MapSummary(
            overview: _overview,
            dateTimeFormat: _dateTimeFormat,
            selectedSupervisorCode: _selectedSupervisorCode,
            selectedSellerCode: _selectedSellerCode,
            selectedNeighborhoodKey: _selectedNeighborhoodKey,
            selectedActivityKey: _selectedActivityKey,
            onSupervisorSelected: _handleSupervisorChanged,
            onSellerSelected: _handleSellerChanged,
            onNeighborhoodSelected: _handleNeighborhoodChanged,
            onActivitySelected: _handleActivityChanged,
          ),
        ),
        Positioned(
          right: 12,
          bottom: 32,
          child: FloatingActionButton.small(
            heroTag: 'fit-customer-opportunities',
            tooltip: 'Mostrar todos os pontos',
            onPressed: _overview.opportunities.isEmpty ? null : _focusSelection,
            backgroundColor: Colors.white,
            foregroundColor: primaryColor,
            child: const Icon(Icons.center_focus_strong_rounded),
          ),
        ),
      ],
    );
  }

  String _emptyMapMessage() {
    if (_overview.requiresSupervisor) {
      return 'Selecione um supervisor para continuar.';
    }
    if (_overview.requiresSeller) {
      return 'Selecione um vendedor para carregar as oportunidades.';
    }
    if (_overview.servedNeighborhoods.isEmpty) {
      return 'Nao ha oportunidades nos bairros atendidos por este vendedor.';
    }
    return 'Nao ha oportunidades para os filtros selecionados.';
  }

  List<Marker> _buildMarkers() {
    return _overview.opportunities
        .map(
          (opportunity) => Marker(
            point: LatLng(opportunity.latitude, opportunity.longitude),
            width: 44,
            height: 52,
            alignment: Alignment.topCenter,
            child: Tooltip(
              message: 'Abrir oportunidade',
              child: Semantics(
                button: true,
                label: 'Abrir oportunidade',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showOpportunity(opportunity),
                  child: const Icon(
                    Icons.location_on_rounded,
                    size: 42,
                    color: Color(0xFFE43D30),
                    shadows: [
                      Shadow(
                        color: Color(0x66000000),
                        blurRadius: 5,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        )
        .toList(growable: false);
  }
}

class _MapSummary extends StatelessWidget {
  const _MapSummary({
    required this.overview,
    required this.dateTimeFormat,
    required this.selectedSupervisorCode,
    required this.selectedSellerCode,
    required this.selectedNeighborhoodKey,
    required this.selectedActivityKey,
    required this.onSupervisorSelected,
    required this.onSellerSelected,
    required this.onNeighborhoodSelected,
    required this.onActivitySelected,
  });

  final CustomerOpportunitiesOverview overview;
  final DateFormat dateTimeFormat;
  final String? selectedSupervisorCode;
  final String? selectedSellerCode;
  final String? selectedNeighborhoodKey;
  final String? selectedActivityKey;
  final ValueChanged<String?> onSupervisorSelected;
  final ValueChanged<String?> onSellerSelected;
  final ValueChanged<String?> onNeighborhoodSelected;
  final ValueChanged<String?> onActivitySelected;

  bool get _isCoordinator =>
      overview.viewerProfileSlug == AppProfile.coordinatorSlug;
  bool get _selectsSeller =>
      overview.viewerProfileSlug == AppProfile.supervisorSlug || _isCoordinator;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: const Color(0x33000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFDDE3EC)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.place_outlined, color: primaryColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${overview.totalOpportunities} oportunidades',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF172033),
                    ),
                  ),
                ),
                Text(
                  '${overview.servedNeighborhoods.length} bairros',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF5E6A7C),
                  ),
                ),
              ],
            ),
            if (_isCoordinator)
              _FilterDropdown(
                icon: Icons.account_tree_outlined,
                hint: 'Selecione o supervisor',
                value: selectedSupervisorCode,
                items: overview.availableSupervisors
                    .map(
                      (option) => DropdownMenuItem<String>(
                        value: option.code,
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: onSupervisorSelected,
              ),
            if (_selectsSeller)
              _FilterDropdown(
                icon: Icons.person_search_outlined,
                hint: 'Selecione o vendedor',
                value: selectedSellerCode,
                items: overview.availableSellers
                    .map(
                      (option) => DropdownMenuItem<String>(
                        value: option.code,
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: overview.availableSellers.isEmpty
                    ? null
                    : onSellerSelected,
              ),
            if (overview.servedNeighborhoods.isNotEmpty)
              _FilterDropdown(
                icon: Icons.holiday_village_outlined,
                hint: 'Cidade - Bairro',
                value: selectedNeighborhoodKey,
                items: overview.servedNeighborhoods
                    .map(
                      (neighborhood) => DropdownMenuItem<String>(
                        value: neighborhood.key,
                        child: Text(
                          '${neighborhood.label} '
                          '(${neighborhood.opportunityCount})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: onNeighborhoodSelected,
              ),
            if (overview.availableActivities.isNotEmpty)
              _FilterDropdown(
                icon: Icons.category_outlined,
                hint: 'Ramo de atividade',
                value: selectedActivityKey ?? '',
                items: <DropdownMenuItem<String>>[
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('Todos os ramos'),
                  ),
                  ...overview.availableActivities.map(
                    (activity) => DropdownMenuItem<String>(
                      value: activity.key,
                      child: Text(
                        '${activity.label} (${activity.opportunityCount})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: onActivitySelected,
              ),
            if (overview.lastUpdatedAt != null) ...[
              const SizedBox(height: 3),
              Text(
                'Atualizado em ${dateTimeFormat.format(overview.lastUpdatedAt!)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF748094),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.icon,
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;
  final String hint;
  final String? value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final availableValues = items.map((item) => item.value).toSet();
    final safeValue = availableValues.contains(value) ? value : null;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF465267)),
          const SizedBox(width: 7),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: safeValue,
                hint: Text(hint),
                isExpanded: true,
                isDense: true,
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpportunityDetailsSheet extends StatelessWidget {
  const _OpportunityDetailsSheet({
    required this.opportunity,
    required this.currencyFormat,
  });

  final CustomerOpportunity opportunity;
  final NumberFormat currencyFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondaryName = opportunity.displayName == opportunity.clientName
        ? opportunity.fantasyName
        : opportunity.clientName;
    final potentialValue =
        opportunity.marketPotentialOrderCount == 0 ||
            opportunity.marketPotential == null
        ? 'Nunca comprou'
        : currencyFormat.format(opportunity.marketPotential);
    final potentialDetail = opportunity.marketPotentialOrderCount == 0
        ? null
        : 'Media de ${opportunity.marketPotentialOrderCount} '
              '${opportunity.marketPotentialOrderCount == 1 ? 'pedido' : 'pedidos'}';

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7F5EF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.storefront_outlined,
                      color: Color(0xFF087B5A),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          opportunity.displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF172033),
                          ),
                        ),
                        if (secondaryName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            secondaryName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF647084),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _InfoRow(
                icon: Icons.badge_outlined,
                label: opportunity.taxId.length == 11 ? 'CPF' : 'CNPJ',
                value: _formatTaxId(opportunity.taxId),
              ),
              if (opportunity.activityLabel.isNotEmpty)
                _InfoRow(
                  icon: Icons.category_outlined,
                  label: 'Atividade',
                  value: opportunity.activityLabel,
                ),
              _InfoRow(
                icon: Icons.location_city_outlined,
                label: 'Cidade',
                value: opportunity.cityLabel,
              ),
              if (opportunity.district.isNotEmpty)
                _InfoRow(
                  icon: Icons.holiday_village_outlined,
                  label: 'Bairro',
                  value: opportunity.district,
                ),
              if (opportunity.fullAddress.isNotEmpty)
                _InfoRow(
                  icon: Icons.signpost_outlined,
                  label: 'Endereco',
                  value: opportunity.fullAddress,
                ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _MetricTile(
                      icon: Icons.credit_score_outlined,
                      label: 'Sugestão de Lim. Crédito',
                      value: currencyFormat.format(opportunity.creditLimit),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricTile(
                      icon: Icons.trending_up_rounded,
                      label: 'Potencial de Mercado',
                      value: potentialValue,
                      detail: potentialDetail,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Fornecedores comprados',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF172033),
                ),
              ),
              const SizedBox(height: 8),
              if (opportunity.suppliers.isEmpty)
                Text(
                  'Nao ha fornecedores identificados no historico.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF647084),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: opportunity.suppliers
                      .map(
                        (supplier) => Chip(
                          avatar: const Icon(
                            Icons.inventory_2_outlined,
                            size: 16,
                          ),
                          label: Text(supplier.label),
                        ),
                      )
                      .toList(growable: false),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTaxId(String value) {
    if (value.length == 11) {
      return '${value.substring(0, 3)}.${value.substring(3, 6)}.'
          '${value.substring(6, 9)}-${value.substring(9)}';
    }
    if (value.length == 14) {
      return '${value.substring(0, 2)}.${value.substring(2, 5)}.'
          '${value.substring(5, 8)}/${value.substring(8, 12)}-'
          '${value.substring(12)}';
    }
    return value;
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 116),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE3EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: primaryColor),
          const SizedBox(height: 7),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: const Color(0xFF647084)),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF172033),
              fontWeight: FontWeight.w800,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 2),
            Text(
              detail!,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: const Color(0xFF748094)),
            ),
          ],
        ],
      ),
    );
  }
}

class _OpportunityDetailsLoader extends StatelessWidget {
  const _OpportunityDetailsLoader({
    required this.details,
    required this.currencyFormat,
  });

  final Future<CustomerOpportunity> details;
  final NumberFormat currencyFormat;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CustomerOpportunity>(
      future: details,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SafeArea(
            child: SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return SafeArea(
            child: SizedBox(
              height: 220,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFD84315),
                      size: 36,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Nao foi possivel carregar os detalhes.\n'
                      '${snapshot.error ?? ''}',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return _OpportunityDetailsSheet(
          opportunity: snapshot.data!,
          currencyFormat: currencyFormat,
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF748094),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF263246),
                    fontWeight: FontWeight.w600,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: const Color(0xFF7B8798)),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF647084)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 52,
              color: Color(0xFFD84315),
            ),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
