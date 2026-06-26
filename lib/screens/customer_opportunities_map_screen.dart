import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_theme.dart';
import '../models/customer_route.dart';
import '../models/app_profile.dart';
import '../models/customer_opportunities.dart';
import '../services/app_repository.dart';
import '../services/mapbox_directions_service.dart';

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
  final MapboxDirectionsService _directionsService = MapboxDirectionsService();
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
  CustomerRoute? _activeRoute;
  CustomerOpportunity? _routeOpportunity;
  LatLng? _routeOrigin;
  Timer? _locationRefreshTimer;
  bool _locationRefreshInProgress = false;
  bool _routeLoading = false;
  bool _showRouteDirections = true;
  String? _routeErrorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _stopLocationTracking();
    _directionsService.close();
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
      _clearRouteState();
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
      _clearRouteState();
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
      _clearRouteState();
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
      _clearRouteState();
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
        onCalculateRoute: (opportunity) async {
          Navigator.of(context).pop();
          await _calculateRoute(opportunity);
        },
      ),
    );
  }

  void _clearRouteState() {
    _stopLocationTracking();
    _activeRoute = null;
    _routeOpportunity = null;
    _routeOrigin = null;
    _routeLoading = false;
    _routeErrorMessage = null;
    _showRouteDirections = true;
  }

  Future<LatLng> _getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const CustomerRouteException(
        'Ative a localizacao do aparelho para calcular a rota.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const CustomerRouteException(
        'Permissao de localizacao negada. Autorize para calcular a rota.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw const CustomerRouteException(
        'Permissao de localizacao bloqueada. Libere nas configuracoes do Android.',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 18),
      ),
    );
    return LatLng(position.latitude, position.longitude);
  }

  Future<void> _calculateRoute(CustomerOpportunity opportunity) async {
    if (_routeLoading) {
      return;
    }

    setState(() {
      _routeLoading = true;
      _routeErrorMessage = null;
      _activeRoute = null;
      _routeOrigin = null;
      _routeOpportunity = opportunity;
      _showRouteDirections = true;
    });

    try {
      final origin = await _getCurrentLocation();
      final destination = LatLng(opportunity.latitude, opportunity.longitude);
      final route = await _directionsService.getDrivingRoute(
        origin: origin,
        destination: destination,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _routeOrigin = origin;
        _activeRoute = route;
        _routeLoading = false;
      });
      _startLocationTracking();
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusRoute());
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _routeLoading = false;
        _routeErrorMessage = error is CustomerRouteException
            ? error.message
            : 'Nao foi possivel calcular a rota. Tente novamente.';
      });
    }
  }

  void _startLocationTracking() {
    _stopLocationTracking();
    _locationRefreshTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _refreshRouteOrigin(),
    );
  }

  void _stopLocationTracking() {
    _locationRefreshTimer?.cancel();
    _locationRefreshTimer = null;
    _locationRefreshInProgress = false;
  }

  Future<void> _refreshRouteOrigin() async {
    if (!mounted ||
        _locationRefreshInProgress ||
        _routeOpportunity == null ||
        _activeRoute == null) {
      return;
    }

    _locationRefreshInProgress = true;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted || _routeOpportunity == null || _activeRoute == null) {
        return;
      }
      setState(() {
        _routeOrigin = LatLng(position.latitude, position.longitude);
      });
    } catch (_) {
      // Mantem a ultima posicao conhecida se a leitura pontual falhar.
    } finally {
      _locationRefreshInProgress = false;
    }
  }

  void _focusRoute() {
    final route = _activeRoute;
    if (route == null || route.points.isEmpty) {
      return;
    }

    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: route.points,
        padding: const EdgeInsets.fromLTRB(34, 280, 34, 270),
        maxZoom: 16,
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

    final routeModeActive = _routeModeActive;

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
              if (_activeRoute != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _activeRoute!.points,
                      strokeWidth: 5,
                      color: primaryColor,
                    ),
                  ],
                ),
              MarkerClusterLayerWidget(
                key: ValueKey<String>(
                  '${_selectedSellerCode ?? ''}|'
                  '${_selectedNeighborhoodKey ?? ''}|'
                  '${_selectedActivityKey ?? ''}|'
                  '${_routeOpportunity?.taxId ?? ''}',
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
              if (_routeOrigin != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _routeOrigin!,
                      width: 36,
                      height: 36,
                      child: const Tooltip(
                        message: 'Sua localizacao',
                        child: Icon(
                          Icons.my_location_rounded,
                          color: Color(0xFF1E88E5),
                          size: 30,
                          shadows: [
                            Shadow(
                              color: Color(0x66000000),
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              const RichAttributionWidget(
                attributions: [TextSourceAttribution('OpenStreetMap')],
              ),
            ],
          ),
        ),
        if (_overview.opportunities.isEmpty && !routeModeActive)
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
        if (!routeModeActive)
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
          bottom: _hasRoutePanel
              ? MediaQuery.sizeOf(context).height * 0.5 + 12
              : 32,
          child: FloatingActionButton.small(
            heroTag: 'fit-customer-opportunities',
            tooltip: _activeRoute == null
                ? 'Mostrar todos os pontos'
                : 'Ver rota',
            onPressed: _activeRoute == null
                ? (_overview.opportunities.isEmpty ? null : _focusSelection)
                : _focusRoute,
            backgroundColor: Colors.white,
            foregroundColor: primaryColor,
            child: const Icon(Icons.center_focus_strong_rounded),
          ),
        ),
        if (_hasRoutePanel)
          Positioned.fill(
            child: DraggableScrollableSheet(
              initialChildSize: _showRouteDirections ? 0.32 : 0.18,
              minChildSize: 0.16,
              maxChildSize: 0.5,
              snap: true,
              snapSizes: const [0.18, 0.32, 0.5],
              builder: (context, scrollController) => Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  0,
                  12,
                  MediaQuery.paddingOf(context).bottom + 12,
                ),
                child: _RoutePanel(
                  route: _activeRoute,
                  opportunity: _routeOpportunity,
                  loading: _routeLoading,
                  errorMessage: _routeErrorMessage,
                  showDirections: _showRouteDirections,
                  scrollController: scrollController,
                  onToggleDirections: () {
                    setState(() {
                      _showRouteDirections = !_showRouteDirections;
                    });
                  },
                  onClose: () {
                    setState(_clearRouteState);
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _focusSelection(),
                    );
                  },
                  onRetry: _routeOpportunity == null
                      ? null
                      : () => _calculateRoute(_routeOpportunity!),
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool get _hasRoutePanel =>
      _routeLoading || _activeRoute != null || _routeErrorMessage != null;

  bool get _routeModeActive =>
      _routeOpportunity != null || _routeLoading || _activeRoute != null;

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
    final routeOpportunity = _routeOpportunity;
    final opportunities = routeOpportunity == null
        ? _overview.opportunities
        : [routeOpportunity];

    return opportunities
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

class _RoutePanel extends StatelessWidget {
  const _RoutePanel({
    required this.route,
    required this.opportunity,
    required this.loading,
    required this.errorMessage,
    required this.showDirections,
    required this.scrollController,
    required this.onToggleDirections,
    required this.onClose,
    required this.onRetry,
  });

  final CustomerRoute? route;
  final CustomerOpportunity? opportunity;
  final bool loading;
  final String? errorMessage;
  final bool showDirections;
  final ScrollController scrollController;
  final VoidCallback onToggleDirections;
  final VoidCallback onClose;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = opportunity?.displayName.trim().isNotEmpty == true
        ? opportunity!.displayName
        : 'Rota';

    return Material(
      color: Colors.white,
      elevation: 4,
      shadowColor: const Color(0x33000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFDDE3EC)),
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 12),
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFD4DAE5),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          if (loading)
            Row(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Calculando rota...',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar rota',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            )
          else ...[
            Row(
              children: [
                const Icon(Icons.alt_route_rounded, color: primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar rota',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                errorMessage!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFD84315),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ] else if (route != null) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  _RouteMetric(
                    icon: Icons.route_outlined,
                    label: _formatDistance(route!.distanceMeters),
                  ),
                  const SizedBox(width: 10),
                  _RouteMetric(
                    icon: Icons.schedule_outlined,
                    label: _formatDuration(route!.durationSeconds),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onToggleDirections,
                    icon: Icon(
                      showDirections
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    label: Text(showDirections ? 'Ocultar' : 'Mostrar'),
                  ),
                ],
              ),
              if (showDirections) ...[
                const SizedBox(height: 8),
                ...List.generate(route!.steps.length, (index) {
                  final step = route!.steps[index];
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (index > 0) const Divider(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: const Color(0xFFE7EBFF),
                            child: Text(
                              '${index + 1}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: primaryColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  step.instruction,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF263246),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_formatDistance(step.distanceMeters)} '
                                  '- ${_formatDuration(step.durationSeconds)}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: const Color(0xFF748094),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }),
              ],
            ],
          ],
        ],
      ),
    );
  }

  static String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
    }
    return '${meters.round()} m';
  }

  static String _formatDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) {
      return '$minutes min';
    }
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) {
      return '${hours}h';
    }
    return '${hours}h ${remainingMinutes}min';
  }
}

class _RouteMetric extends StatelessWidget {
  const _RouteMetric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: primaryColor),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: const Color(0xFF465267),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _OpportunityDetailsSheet extends StatelessWidget {
  const _OpportunityDetailsSheet({
    required this.opportunity,
    required this.currencyFormat,
    required this.onCalculateRoute,
  });

  final CustomerOpportunity opportunity;
  final NumberFormat currencyFormat;
  final Future<void> Function(CustomerOpportunity opportunity) onCalculateRoute;

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
                _AddressRouteRow(
                  address: opportunity.fullAddress,
                  onCalculateRoute: () => onCalculateRoute(opportunity),
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

class _AddressRouteRow extends StatelessWidget {
  const _AddressRouteRow({
    required this.address,
    required this.onCalculateRoute,
  });

  final String address;
  final VoidCallback onCalculateRoute;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.signpost_outlined, size: 20, color: primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Endereco',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF748094),
                  ),
                ),
                const SizedBox(height: 2),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final addressText = Text(
                      address,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF263246),
                        fontWeight: FontWeight.w600,
                      ),
                    );
                    final routeButton = FilledButton.tonalIcon(
                      onPressed: onCalculateRoute,
                      icon: const Icon(Icons.alt_route_rounded),
                      label: const Text('Calcular Rota'),
                    );

                    if (constraints.maxWidth < 330) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          addressText,
                          const SizedBox(height: 8),
                          routeButton,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: addressText),
                        const SizedBox(width: 10),
                        routeButton,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OpportunityDetailsLoader extends StatelessWidget {
  const _OpportunityDetailsLoader({
    required this.details,
    required this.currencyFormat,
    required this.onCalculateRoute,
  });

  final Future<CustomerOpportunity> details;
  final NumberFormat currencyFormat;
  final Future<void> Function(CustomerOpportunity opportunity) onCalculateRoute;

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
          onCalculateRoute: onCalculateRoute,
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
