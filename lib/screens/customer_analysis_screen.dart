import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../core/supabase_config.dart';
import '../models/customer_analysis.dart';
import '../services/customer_analysis_service.dart';

enum _AnalysisMetric { financial, volume, skus }

extension on _AnalysisMetric {
  String get label => switch (this) {
    _AnalysisMetric.financial => 'Financeiro',
    _AnalysisMetric.volume => 'Volume',
    _AnalysisMetric.skus => 'SKUs',
  };

  IconData get icon => switch (this) {
    _AnalysisMetric.financial => Icons.payments_outlined,
    _AnalysisMetric.volume => Icons.inventory_2_outlined,
    _AnalysisMetric.skus => Icons.category_outlined,
  };
}

class CustomerAnalysisScreen extends StatefulWidget {
  const CustomerAnalysisScreen({super.key});

  @override
  State<CustomerAnalysisScreen> createState() => _CustomerAnalysisScreenState();
}

class _CustomerAnalysisScreenState extends State<CustomerAnalysisScreen> {
  final CustomerAnalysisService _service = CustomerAnalysisService.instance;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<CustomerAnalysisSearchResult> _customers = const [];
  bool _loading = true;
  bool _showingNearby = true;
  String? _message;
  LatLng? _userLocation;
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNearby());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadNearby({bool clearSearch = false}) async {
    if (!mounted) return;
    final requestSerial = ++_requestSerial;
    if (clearSearch) {
      _searchController.clear();
      _searchFocus.unfocus();
    }
    setState(() {
      _loading = true;
      _showingNearby = true;
      _message = null;
    });
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        throw const _LocationUnavailable(
          'Ative a localização para ver os clientes próximos. Você ainda pode pesquisar normalmente.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const _LocationUnavailable(
          'A localização não foi autorizada. Você ainda pode pesquisar por código, nome ou CPF/CNPJ.',
        );
      }
      final locationSettings = defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 12),
              forceLocationManager: false,
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 12),
            );
      Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: locationSettings,
        );
      } on TimeoutException {
        final cachedPosition = await Geolocator.getLastKnownPosition(
          forceAndroidLocationManager: false,
        );
        if (cachedPosition == null ||
            DateTime.now().difference(cachedPosition.timestamp).abs() >
                const Duration(minutes: 30)) {
          rethrow;
        }
        position = cachedPosition;
      }
      final customers = await _service.nearby(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted || requestSerial != _requestSerial) return;
      setState(() {
        _customers = customers;
        _userLocation = LatLng(position.latitude, position.longitude);
        _loading = false;
        _message = customers.isEmpty
            ? 'Nenhum cliente com localização foi encontrado para o seu acesso.'
            : null;
      });
    } on _LocationUnavailable catch (error) {
      if (!mounted || requestSerial != _requestSerial) return;
      setState(() {
        _customers = const [];
        _userLocation = null;
        _loading = false;
        _message = error.message;
      });
    } on TimeoutException {
      if (!mounted || requestSerial != _requestSerial) return;
      setState(() {
        _customers = const [];
        _userLocation = null;
        _loading = false;
        _message =
            'Não foi possível obter a localização agora. Você ainda pode pesquisar normalmente.';
      });
    } catch (error) {
      if (!mounted || requestSerial != _requestSerial) return;
      setState(() {
        _customers = const [];
        _userLocation = null;
        _loading = false;
        _message = 'Não foi possível carregar os clientes próximos. $error';
      });
    }
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      await _loadNearby();
      return;
    }
    if (query.length < 2 && int.tryParse(query) == null) {
      _requestSerial++;
      setState(() {
        _message = 'Digite ao menos dois caracteres para pesquisar.';
        _customers = const [];
        _showingNearby = false;
      });
      return;
    }
    final requestSerial = ++_requestSerial;
    _searchFocus.unfocus();
    setState(() {
      _loading = true;
      _showingNearby = false;
      _message = null;
    });
    try {
      final customers = await _service.search(query);
      if (!mounted || requestSerial != _requestSerial) return;
      setState(() {
        _customers = customers;
        _loading = false;
        _message = customers.isEmpty
            ? 'Nenhum cliente encontrado para essa pesquisa.'
            : null;
      });
    } catch (error) {
      if (!mounted || requestSerial != _requestSerial) return;
      setState(() {
        _customers = const [];
        _loading = false;
        _message = 'Não foi possível pesquisar os clientes. $error';
      });
    }
  }

  Future<void> _openCustomer(CustomerAnalysisSearchResult customer) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerAnalysisDetailScreen(
          customerCode: customer.code,
          initialCustomer: customer,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Análise por Cliente')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _showingNearby ? _loadNearby : _search,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _SearchCard(
                controller: _searchController,
                focusNode: _searchFocus,
                loading: _loading,
                onSearch: _search,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(
                    _showingNearby
                        ? Icons.near_me_outlined
                        : Icons.manage_search_outlined,
                    color: const Color(0xFF243A96),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _showingNearby
                          ? 'Clientes mais próximos'
                          : 'Resultados da pesquisa',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (!_showingNearby)
                    TextButton.icon(
                      onPressed: _loading
                          ? null
                          : () => _loadNearby(clearSearch: true),
                      icon: const Icon(Icons.my_location, size: 18),
                      label: const Text('Próximos'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (_loading)
                const _LoadingCard(label: 'Consultando clientes...')
              else if (_message != null)
                _MessageCard(
                  message: _message!,
                  actionLabel: _showingNearby ? 'Tentar novamente' : null,
                  onAction: _showingNearby ? _loadNearby : null,
                )
              else if (_showingNearby && _userLocation != null)
                _NearbyCustomersSection(
                  userLocation: _userLocation!,
                  customers: _customers,
                  onCustomerTap: _openCustomer,
                )
              else
                ..._customers.map(
                  (customer) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _CustomerResultCard(
                      customer: customer,
                      onTap: () => _openCustomer(customer),
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

class _NearbyCustomersSection extends StatelessWidget {
  const _NearbyCustomersSection({
    required this.userLocation,
    required this.customers,
    required this.onCustomerTap,
  });

  final LatLng userLocation;
  final List<CustomerAnalysisSearchResult> customers;
  final ValueChanged<CustomerAnalysisSearchResult> onCustomerTap;

  @override
  Widget build(BuildContext context) {
    final sortedCustomers = List<CustomerAnalysisSearchResult>.of(customers)
      ..sort((first, second) {
        final firstDistance = first.distanceKm ?? double.infinity;
        final secondDistance = second.distanceKm ?? double.infinity;
        final distanceComparison = firstDistance.compareTo(secondDistance);
        return distanceComparison != 0
            ? distanceComparison
            : first.code.compareTo(second.code);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NearbyCustomersMap(
          userLocation: userLocation,
          customers: sortedCustomers,
          onCustomerTap: onCustomerTap,
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Icon(
              Icons.format_list_numbered_outlined,
              color: Color(0xFF243A96),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Lista por distância',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              '${sortedCustomers.length} clientes',
              style: const TextStyle(
                color: Color(0xFF71809D),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < sortedCustomers.length; index++)
          Padding(
            padding: EdgeInsets.only(
              bottom: index == sortedCustomers.length - 1 ? 0 : 10,
            ),
            child: _CustomerResultCard(
              customer: sortedCustomers[index],
              onTap: () => onCustomerTap(sortedCustomers[index]),
            ),
          ),
      ],
    );
  }
}

class _NearbyCustomersMap extends StatelessWidget {
  const _NearbyCustomersMap({
    required this.userLocation,
    required this.customers,
    required this.onCustomerTap,
  });

  final LatLng userLocation;
  final List<CustomerAnalysisSearchResult> customers;
  final ValueChanged<CustomerAnalysisSearchResult> onCustomerTap;

  @override
  Widget build(BuildContext context) {
    final locatedCustomers = customers
        .where((item) => item.latitude != null && item.longitude != null)
        .toList(growable: false);
    final points = <LatLng>[
      userLocation,
      for (final customer in locatedCustomers)
        LatLng(customer.latitude!, customer.longitude!),
    ];
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 430,
        child: FlutterMap(
          key: ValueKey(
            '${userLocation.latitude},${userLocation.longitude}|'
            '${locatedCustomers.map((item) => item.code).join(',')}',
          ),
          options: MapOptions(
            initialCenter: userLocation,
            initialZoom: 15,
            minZoom: 3,
            maxZoom: 19,
            initialCameraFit: CameraFit.coordinates(
              coordinates: points,
              padding: const EdgeInsets.all(42),
              maxZoom: 16,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'br.com.omegadistribuidora.gestao_vendas',
              maxNativeZoom: 19,
            ),
            MarkerClusterLayerWidget(
              options: MarkerClusterLayerOptions(
                size: const Size(46, 46),
                maxClusterRadius: 52,
                disableClusteringAtZoom: 18,
                markerChildBehavior: true,
                padding: const EdgeInsets.all(36),
                markers: [
                  for (final customer in locatedCustomers)
                    Marker(
                      point: LatLng(customer.latitude!, customer.longitude!),
                      width: 46,
                      height: 46,
                      child: Tooltip(
                        message: customer.tradeName ?? customer.name,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => onCustomerTap(customer),
                          child: Container(
                            decoration: BoxDecoration(
                              color: customer.blocked
                                  ? const Color(0xFFB3261E)
                                  : const Color(0xFF243A96),
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
                            child: const Icon(
                              Icons.storefront_outlined,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
                builder: (context, markers) => Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF243A96),
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
                  child: Text(
                    '${markers.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: userLocation,
                  width: 38,
                  height: 38,
                  alignment: Alignment.bottomLeft,
                  child: const IgnorePointer(
                    child: Tooltip(
                      message: 'Sua localização',
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFF1E88E5),
                            shape: BoxShape.circle,
                            border: Border.fromBorderSide(
                              BorderSide(color: Colors.white, width: 3),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x44000000),
                                blurRadius: 7,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: SizedBox(width: 24, height: 24),
                        ),
                      ),
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
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.onSearch,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final Future<void> Function() onSearch;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Encontre um cliente',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'Pesquise por código, razão social, nome fantasia ou CPF/CNPJ.',
              style: TextStyle(color: Color(0xFF66738C)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSearch(),
              decoration: InputDecoration(
                hintText: 'Digite os dados do cliente',
                prefixIcon: const Icon(Icons.person_search_outlined),
                suffixIcon: IconButton(
                  tooltip: 'Pesquisar',
                  onPressed: loading ? null : onSearch,
                  icon: loading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerResultCard extends StatelessWidget {
  const _CustomerResultCard({required this.customer, required this.onTap});

  final CustomerAnalysisSearchResult customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = customer.tradeName ?? customer.name;
    final subtitleName = customer.tradeName == null ? null : customer.name;
    final place = [
      customer.neighborhood,
      customer.city,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7EBFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.storefront_outlined,
                  color: Color(0xFF243A96),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (customer.blocked)
                          const _StatusBadge(blocked: true, compact: true),
                      ],
                    ),
                    if (subtitleName != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitleName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF66738C)),
                      ),
                    ],
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 10,
                      runSpacing: 5,
                      children: [
                        _InlineInfo(
                          icon: Icons.tag_outlined,
                          text: '${customer.code}',
                        ),
                        if (customer.distanceKm != null)
                          _InlineInfo(
                            icon: Icons.near_me_outlined,
                            text: _distanceLabel(customer.distanceKm!),
                          ),
                      ],
                    ),
                    if (place.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: Color(0xFF71809D),
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              place,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF71809D),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: Color(0xFF71809D)),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomerAnalysisDetailScreen extends StatefulWidget {
  const CustomerAnalysisDetailScreen({
    super.key,
    required this.customerCode,
    this.initialCustomer,
  });

  final int customerCode;
  final CustomerAnalysisSearchResult? initialCustomer;

  @override
  State<CustomerAnalysisDetailScreen> createState() =>
      _CustomerAnalysisDetailScreenState();
}

class _CustomerAnalysisDetailScreenState
    extends State<CustomerAnalysisDetailScreen> {
  final CustomerAnalysisService _service = CustomerAnalysisService.instance;
  final Map<int, CustomerOrderDetail> _orderDetails = {};
  final Set<int> _loadingOrders = {};
  final Map<int, String> _orderErrors = {};

  CustomerAnalysisDetail? _detail;
  bool _loading = true;
  String? _error;
  _AnalysisMetric _metric = _AnalysisMetric.financial;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _service.getDetail(widget.customerCode);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar o cliente. $error';
      });
    }
  }

  Future<void> _loadOrder(int orderNumber) async {
    if (_orderDetails.containsKey(orderNumber) ||
        _loadingOrders.contains(orderNumber)) {
      return;
    }
    setState(() {
      _loadingOrders.add(orderNumber);
      _orderErrors.remove(orderNumber);
    });
    try {
      final detail = await _service.getOrderDetail(
        customerCode: widget.customerCode,
        orderNumber: orderNumber,
      );
      if (!mounted) return;
      setState(() => _orderDetails[orderNumber] = detail);
    } catch (error) {
      if (!mounted) return;
      setState(() => _orderErrors[orderNumber] = '$error');
    } finally {
      if (mounted) setState(() => _loadingOrders.remove(orderNumber));
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialTitle =
        widget.initialCustomer?.tradeName ??
        widget.initialCustomer?.name ??
        'Cliente ${widget.customerCode}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Análise por Cliente'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: _MetricSelector(
            selected: _metric,
            onSelected: (metric) => setState(() => _metric = metric),
          ),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _FullPageError(message: _error!, onRetry: _load)
            : RefreshIndicator(
                onRefresh: _load,
                child: _buildContent(_detail!, initialTitle),
              ),
      ),
    );
  }

  Widget _buildContent(CustomerAnalysisDetail detail, String initialTitle) {
    final customer = detail.customer;
    final title =
        customer.tradeName ??
        (customer.name.isNotEmpty ? customer.name : initialTitle);
    final semesterMonths = detail.periods.semesterMonths;
    final averages = _metricAverages(detail.metricAverages, _metric);
    final products = [...detail.topProducts]
      ..sort(
        (left, right) => _productMetricValue(
          right,
          _metric,
        ).compareTo(_productMetricValue(left, _metric)),
      );
    final suppliers = [...detail.topSuppliers]
      ..sort(
        (left, right) => _supplierMetricValue(
          right,
          _metric,
        ).compareTo(_supplierMetricValue(left, _metric)),
      );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _CustomerHeader(
          customer: customer,
          title: title,
          daysWithoutPurchase: detail.purchaseInsights.daysWithoutPurchase,
        ),
        const SizedBox(height: 12),
        _CustomerIdentityCard(customer: customer),
        const SizedBox(height: 12),
        _PurchaseInsightsSection(
          insights: detail.purchaseInsights,
          metric: _metric,
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Histórico de compras',
          subtitle: 'Média dos meses em que houve compra',
          icon: Icons.insights_outlined,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _MetricBox(
                      label: 'Média trimestral',
                      value: _formatMetric(averages.quarterly, _metric),
                      accent: const Color(0xFF087B5A),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricBox(
                      label: 'Média semestral',
                      value: _formatMetric(averages.semester, _metric),
                      accent: const Color(0xFF243A96),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Última compra',
          subtitle: detail.lastPurchase == null
              ? 'Nenhuma compra faturada encontrada'
              : 'Toque para consultar os produtos',
          icon: Icons.receipt_long_outlined,
          child: detail.lastPurchase == null
              ? const _EmptySection(
                  icon: Icons.shopping_cart_outlined,
                  label: 'Este cliente ainda não possui compra faturada.',
                )
              : _OrderExpansion(
                  key: ValueKey('last-${detail.lastPurchase!.orderNumber}'),
                  order: detail.lastPurchase!,
                  detail: _orderDetails[detail.lastPurchase!.orderNumber],
                  loading: _loadingOrders.contains(
                    detail.lastPurchase!.orderNumber,
                  ),
                  error: _orderErrors[detail.lastPurchase!.orderNumber],
                  metric: _metric,
                  highlighted: true,
                  onExpand: () => _loadOrder(detail.lastPurchase!.orderNumber),
                ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Produtos mais comprados',
          subtitle: _activeMonthsSubtitle(
            'Top 5 por ${_metric.label.toLowerCase()}',
            semesterMonths,
          ),
          icon: Icons.inventory_2_outlined,
          child: products.isEmpty
              ? const _EmptySection(
                  icon: Icons.inventory_2_outlined,
                  label: 'Sem compras registradas.',
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < math.min(5, products.length);
                      index++
                    ) ...[
                      _ProductMetricRow(
                        rank: index + 1,
                        product: products[index],
                        metric: _metric,
                      ),
                      if (index < math.min(5, products.length) - 1)
                        const Divider(height: 22),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Fornecedores mais comprados',
          subtitle: _activeMonthsSubtitle(
            'Ranking por ${_metric.label.toLowerCase()}',
            semesterMonths,
          ),
          icon: Icons.emoji_events_outlined,
          child: suppliers.isEmpty
              ? const _EmptySection(
                  icon: Icons.store_mall_directory_outlined,
                  label: 'Sem compras registradas.',
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < math.min(10, suppliers.length);
                      index++
                    ) ...[
                      _SupplierMetricRow(
                        rank: index + 1,
                        supplier: suppliers[index],
                        metric: _metric,
                      ),
                      if (index < math.min(10, suppliers.length) - 1)
                        const Divider(height: 18),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _LostProductsSection(products: detail.lostProducts, metric: _metric),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Últimos 5 pedidos',
          subtitle:
              'Ticket médio: ${_formatMetric(_metricValue(detail.purchaseInsights.averageTickets, _metric), _metric)} · toque para expandir',
          icon: Icons.history_outlined,
          child: detail.recentOrders.isEmpty
              ? const _EmptySection(
                  icon: Icons.receipt_outlined,
                  label: 'Nenhum pedido faturado encontrado.',
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < detail.recentOrders.length;
                      index++
                    ) ...[
                      _OrderExpansion(
                        key: ValueKey(
                          'recent-${detail.recentOrders[index].orderNumber}',
                        ),
                        order: detail.recentOrders[index],
                        detail:
                            _orderDetails[detail
                                .recentOrders[index]
                                .orderNumber],
                        loading: _loadingOrders.contains(
                          detail.recentOrders[index].orderNumber,
                        ),
                        error:
                            _orderErrors[detail
                                .recentOrders[index]
                                .orderNumber],
                        metric: _metric,
                        onExpand: () =>
                            _loadOrder(detail.recentOrders[index].orderNumber),
                      ),
                      if (index < detail.recentOrders.length - 1)
                        const Divider(height: 10),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _DelinquencySection(summary: detail.delinquency),
        const SizedBox(height: 12),
        _ReturnsSection(summary: detail.returnsSummary, metric: _metric),
      ],
    );
  }
}

class _MetricSelector extends StatelessWidget {
  const _MetricSelector({required this.selected, required this.onSelected});

  final _AnalysisMetric selected;
  final ValueChanged<_AnalysisMetric> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF07005C),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<_AnalysisMetric>(
          showSelectedIcon: false,
          segments: [
            for (final metric in _AnalysisMetric.values)
              ButtonSegment(
                value: metric,
                icon: Icon(metric.icon, size: 17),
                label: Text(metric.label),
              ),
          ],
          selected: {selected},
          onSelectionChanged: (selection) => onSelected(selection.first),
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? Colors.white
                  : const Color(0xFF07005C),
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? const Color(0xFF07005C)
                  : Colors.white,
            ),
            side: const WidgetStatePropertyAll(
              BorderSide(color: Color(0x88FFFFFF)),
            ),
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerHeader extends StatelessWidget {
  const _CustomerHeader({
    required this.customer,
    required this.title,
    required this.daysWithoutPurchase,
  });

  final CustomerAnalysisCustomer customer;
  final String title;
  final int? daysWithoutPurchase;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xFF07005C),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.storefront_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Cliente ${customer.code}',
                        style: const TextStyle(color: Color(0xFFC9D0FF)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _StatusBadge(blocked: customer.blocked),
                const Spacer(),
                if (customer.lastPurchaseDate != null)
                  Flexible(
                    child: Text(
                      'Última compra: ${_date(customer.lastPurchaseDate!)}'
                      '${daysWithoutPurchase == null ? '' : ' · $daysWithoutPurchase ${daysWithoutPurchase == 1 ? 'dia' : 'dias'} sem compra'}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerIdentityCard extends StatelessWidget {
  const _CustomerIdentityCard({required this.customer});

  final CustomerAnalysisCustomer customer;

  @override
  Widget build(BuildContext context) {
    final address = [
      customer.address,
      customer.neighborhood,
      [customer.city, customer.state].whereType<String>().join(' - '),
      customer.zipCode == null ? null : 'CEP ${customer.zipCode}',
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(', ');
    return _SectionCard(
      title: 'Dados do cliente',
      icon: Icons.badge_outlined,
      child: Column(
        children: [
          _DataLine(
            icon: Icons.business_outlined,
            label: 'Razão social',
            value: customer.name,
          ),
          if (customer.tradeName != null)
            _DataLine(
              icon: Icons.store_outlined,
              label: 'Nome fantasia',
              value: customer.tradeName!,
            ),
          if (customer.document != null)
            _DataLine(
              icon: Icons.description_outlined,
              label: 'CPF/CNPJ',
              value: _document(customer.document!),
            ),
          if (customer.commercialActivity != null)
            _DataLine(
              icon: Icons.work_outline,
              label: 'Atividade comercial',
              value: customer.commercialActivity!,
            ),
          if (address.isNotEmpty)
            _DataLine(
              icon: Icons.location_on_outlined,
              label: 'Endereço',
              value: address,
            ),
          _DataLine(
            icon: Icons.credit_card_outlined,
            label: 'Limite de crédito',
            value: _currency(customer.creditLimit),
          ),
          if (customer.blocked && customer.blockReason != null)
            _DataLine(
              icon: Icons.lock_outline,
              label: 'Motivo do bloqueio',
              value: customer.blockReason!,
              valueColor: const Color(0xFFB3261E),
            ),
          for (final assignment in customer.sellerAssignments)
            _DataLine(
              icon: Icons.people_alt_outlined,
              label: 'Equipe comercial',
              value:
                  '${assignment.sellerCode} · ${assignment.sellerName}'
                  '${assignment.supervisorName == null ? '' : '\nSupervisor: ${assignment.supervisorName}'}',
            ),
        ],
      ),
    );
  }
}

class _PurchaseInsightsSection extends StatelessWidget {
  const _PurchaseInsightsSection({
    required this.insights,
    required this.metric,
  });

  final CustomerPurchaseInsights insights;
  final _AnalysisMetric metric;

  @override
  Widget build(BuildContext context) {
    final previousValue = _metricValue(insights.previousMonthMetrics, metric);
    final currentValue = _metricValue(insights.currentMonthMetrics, metric);
    final hasComparison = previousValue != 0;
    final variation = hasComparison
        ? _metricValue(insights.monthVariations, metric)
        : null;
    final isPositive = variation != null && variation > 0;
    final isNegative = variation != null && variation < 0;
    final variationColor = isPositive
        ? const Color(0xFF087B5A)
        : isNegative
        ? const Color(0xFFB3261E)
        : const Color(0xFF71809D);
    final variationIcon = isPositive
        ? Icons.trending_up
        : isNegative
        ? Icons.trending_down
        : Icons.trending_flat;
    final previousLabel = insights.previousMonth == null
        ? 'mês anterior'
        : _monthName(insights.previousMonth!);
    final comparison = !hasComparison
        ? 'Sem base de comparação em $previousLabel '
              '(${_formatMetric(previousValue, metric)})'
        : '${isNegative
                  ? 'Queda'
                  : isPositive
                  ? 'Alta'
                  : 'Estável'} de '
              '${variation!.abs().toStringAsFixed(1).replaceAll('.', ',')}% em relação a '
              '$previousLabel (${_formatMetric(previousValue, metric)})';
    final largest = _largestOrder(insights.largestOrders, metric);

    return _SectionCard(
      title: 'Comportamento de compra',
      subtitle: 'Ritmo, evolução e valores do cliente',
      icon: Icons.insights_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F6FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDDE3FF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Compra em ${insights.currentMonth == null ? 'mês atual' : _monthName(insights.currentMonth!)}',
                  style: const TextStyle(
                    color: Color(0xFF71809D),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _formatMetric(currentValue, metric),
                  style: const TextStyle(
                    color: Color(0xFF07005C),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(variationIcon, color: variationColor, size: 20),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        comparison,
                        style: TextStyle(
                          color: variationColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricBox(
                  label: 'Frequência média',
                  value: insights.averageFrequencyDays == null
                      ? 'Sem histórico'
                      : 'A cada ${insights.averageFrequencyDays} dias',
                  accent: const Color(0xFF6750A4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricBox(
                  label: 'Maior compra',
                  value: largest == null
                      ? 'Sem compra'
                      : _formatMetric(
                          _orderMetricValue(largest, metric),
                          metric,
                        ),
                  accent: const Color(0xFFD07A00),
                ),
              ),
            ],
          ),
          if (largest != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Pedido ${largest.orderNumber} · ${_date(largest.date)}',
                style: const TextStyle(
                  color: Color(0xFF71809D),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'Evolução das vendas · últimos 12 meses',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          _MonthlyEvolutionChart(
            values: insights.monthlyEvolution,
            metric: metric,
          ),
        ],
      ),
    );
  }
}

class _LostProductsSection extends StatelessWidget {
  const _LostProductsSection({required this.products, required this.metric});

  final List<CustomerLostProduct> products;
  final _AnalysisMetric metric;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Produtos perdidos',
      subtitle: 'Comprados antes, mas ausentes nos últimos 5 pedidos',
      icon: Icons.remove_shopping_cart_outlined,
      iconColor: const Color(0xFF9A6500),
      iconBackground: const Color(0xFFFFF1CF),
      child: products.isEmpty
          ? const _EmptySection(
              icon: Icons.check_circle_outline,
              label: 'Nenhum produto perdido foi identificado.',
            )
          : Column(
              children: [
                for (var index = 0; index < products.length; index++) ...[
                  _LostProductRow(product: products[index], metric: metric),
                  if (index < products.length - 1) const Divider(height: 20),
                ],
              ],
            ),
    );
  }
}

class _LostProductRow extends StatelessWidget {
  const _LostProductRow({required this.product, required this.metric});

  final CustomerLostProduct product;
  final _AnalysisMetric metric;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.history_toggle_off, color: Color(0xFFD07A00)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${product.productCode} · ${product.productName}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (product.package != null)
                Text(
                  product.package!,
                  style: const TextStyle(color: Color(0xFF71809D)),
                ),
              const SizedBox(height: 4),
              Text(
                'Última compra: ${_date(product.lastPurchaseDate)} · '
                '${product.previousOrderCount} ${product.previousOrderCount == 1 ? 'pedido anterior' : 'pedidos anteriores'}',
                style: const TextStyle(color: Color(0xFF71809D), fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _formatMetric(_lostProductMetricValue(product, metric), metric),
          style: const TextStyle(
            color: Color(0xFF9A6500),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _DelinquencySection extends StatelessWidget {
  const _DelinquencySection({required this.summary});

  final CustomerDelinquencySummary summary;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Inadimplência',
      subtitle: summary.hasOpenTitles
          ? '${summary.titleCount} ${summary.titleCount == 1 ? 'título vencido' : 'títulos vencidos'} · ${_currency(summary.totalAmount)}'
          : 'Nenhum título vencido em aberto',
      icon: summary.hasOpenTitles
          ? Icons.warning_amber_rounded
          : Icons.verified_outlined,
      iconColor: summary.hasOpenTitles
          ? const Color(0xFFB3261E)
          : const Color(0xFF087B5A),
      iconBackground: summary.hasOpenTitles
          ? const Color(0xFFFFE9E7)
          : const Color(0xFFE6F6EF),
      child: summary.titles.isEmpty
          ? const _EmptySection(
              icon: Icons.check_circle_outline,
              label: 'Cliente sem inadimplência no período considerado.',
            )
          : Column(
              children: [
                for (var index = 0; index < summary.titles.length; index++) ...[
                  _DelinquencyTitleRow(title: summary.titles[index]),
                  if (index < summary.titles.length - 1)
                    const Divider(height: 18),
                ],
              ],
            ),
    );
  }
}

class _DelinquencyTitleRow extends StatelessWidget {
  const _DelinquencyTitleRow({required this.title});

  final CustomerDelinquencyTitle title;

  @override
  Widget build(BuildContext context) {
    final reference =
        title.document ??
        (title.orderNumber == null
            ? 'Título em aberto'
            : 'Pedido ${title.orderNumber}');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.event_busy_outlined, color: Color(0xFFB3261E)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reference,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                'Venceu em ${_date(title.dueDate)} · ${title.daysOverdue} dias em atraso'
                '${title.installment == null ? '' : ' · Parcela ${title.installment}'}',
                style: const TextStyle(color: Color(0xFF71809D), fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _currency(title.amount),
          style: const TextStyle(
            color: Color(0xFFB3261E),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _ReturnsSection extends StatelessWidget {
  const _ReturnsSection({required this.summary, required this.metric});

  final CustomerReturnsSummary summary;
  final _AnalysisMetric metric;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Devoluções',
      subtitle: summary.hasReturns
          ? '${summary.returnCount} ${summary.returnCount == 1 ? 'devolução registrada' : 'devoluções registradas'} · ${_formatMetric(_returnSummaryMetricValue(summary, metric), metric)}'
          : 'Nenhuma devolução registrada',
      icon: Icons.assignment_return_outlined,
      iconColor: const Color(0xFFD05B00),
      iconBackground: const Color(0xFFFFEEE2),
      child: summary.latest.isEmpty
          ? const _EmptySection(
              icon: Icons.check_circle_outline,
              label: 'Cliente sem devoluções registradas.',
            )
          : Column(
              children: [
                for (var index = 0; index < summary.latest.length; index++) ...[
                  _ReturnRow(item: summary.latest[index], metric: metric),
                  if (index < summary.latest.length - 1)
                    const Divider(height: 18),
                ],
              ],
            ),
    );
  }
}

class _ReturnRow extends StatelessWidget {
  const _ReturnRow({required this.item, required this.metric});

  final CustomerReturnSummary item;
  final _AnalysisMetric metric;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.keyboard_return, color: Color(0xFFD05B00)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.orderNumber == null
                    ? 'Devolução de ${_date(item.date)}'
                    : 'Pedido ${item.orderNumber}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                '${_date(item.date)} · ${item.itemCount} ${item.itemCount == 1 ? 'produto' : 'produtos'}'
                '${item.invoiceNumber == null ? '' : ' · NF ${item.invoiceNumber}'}',
                style: const TextStyle(color: Color(0xFF71809D), fontSize: 12),
              ),
              if (item.reason != null) ...[
                const SizedBox(height: 3),
                Text(item.reason!, style: const TextStyle(fontSize: 12)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _formatMetric(_returnMetricValue(item, metric), metric),
          style: const TextStyle(
            color: Color(0xFFD05B00),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _MonthlyEvolutionChart extends StatefulWidget {
  const _MonthlyEvolutionChart({required this.values, required this.metric});

  final List<CustomerMonthlySale> values;
  final _AnalysisMetric metric;

  @override
  State<_MonthlyEvolutionChart> createState() => _MonthlyEvolutionChartState();
}

class _MonthlyEvolutionChartState extends State<_MonthlyEvolutionChart> {
  int? _selectedIndex;

  List<CustomerMonthlySale> get values => widget.values;

  void _selectNearest(double horizontalPosition, double width) {
    if (values.isEmpty || width <= 0) return;
    final index = values.length == 1
        ? 0
        : ((horizontalPosition.clamp(0.0, width) / width) * (values.length - 1))
              .round()
              .clamp(0, values.length - 1);
    if (_selectedIndex != index) {
      setState(() => _selectedIndex = index);
    }
  }

  @override
  void didUpdateWidget(covariant _MonthlyEvolutionChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.values != widget.values ||
        oldWidget.metric != widget.metric) {
      _selectedIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const _EmptySection(
        icon: Icons.show_chart,
        label: 'Ainda não há histórico para montar a evolução.',
      );
    }
    final total = values.fold<double>(
      0,
      (sum, value) => sum + _monthlyMetricValue(value, widget.metric),
    );
    final maximum = values.fold<double>(
      0,
      (value, item) =>
          math.max(value, _monthlyMetricValue(item, widget.metric)),
    );
    final selected = _selectedIndex == null ? null : values[_selectedIndex!];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: selected == null
              ? const Text(
                  'Toque ou arraste sobre o gráfico para ver os valores.',
                  key: ValueKey('chart-instruction'),
                  style: TextStyle(
                    color: Color(0xFF71809D),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : Container(
                  key: ValueKey('chart-${_selectedIndex!}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7EBFF),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '${_monthName(selected.month)} · ${_formatMetric(_monthlyMetricValue(selected, widget.metric), widget.metric)}',
                    style: const TextStyle(
                      color: Color(0xFF243A96),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 124,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 68,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _compactMetric(maximum, widget.metric),
                      style: const TextStyle(
                        color: Color(0xFF71809D),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _compactMetric(maximum / 2, widget.metric),
                      style: const TextStyle(
                        color: Color(0xFF71809D),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _formatMetric(0, widget.metric),
                      style: const TextStyle(
                        color: Color(0xFF71809D),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) => _selectNearest(
                      details.localPosition.dx,
                      constraints.maxWidth,
                    ),
                    onHorizontalDragStart: (details) => _selectNearest(
                      details.localPosition.dx,
                      constraints.maxWidth,
                    ),
                    onHorizontalDragUpdate: (details) => _selectNearest(
                      details.localPosition.dx,
                      constraints.maxWidth,
                    ),
                    child: CustomPaint(
                      painter: _EvolutionPainter(
                        values,
                        metric: widget.metric,
                        selectedIndex: _selectedIndex,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              _shortMonth(values.first.month),
              style: const TextStyle(color: Color(0xFF71809D), fontSize: 11),
            ),
            const Spacer(),
            Text(
              'Total: ${_formatMetric(total, widget.metric)}',
              style: const TextStyle(
                color: Color(0xFF243A96),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text(
              _shortMonth(values.last.month),
              style: const TextStyle(color: Color(0xFF71809D), fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

class _EvolutionPainter extends CustomPainter {
  const _EvolutionPainter(
    this.values, {
    required this.metric,
    this.selectedIndex,
  });

  final List<CustomerMonthlySale> values;
  final _AnalysisMetric metric;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE6E9F3)
      ..strokeWidth = 1;
    for (var line = 0; line < 3; line++) {
      final y = size.height * line / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final maximum = values.fold<double>(
      0,
      (value, item) => math.max(value, _monthlyMetricValue(item, metric)),
    );
    final denominator = maximum <= 0 ? 1.0 : maximum;
    final horizontalStep = values.length == 1
        ? 0.0
        : size.width / (values.length - 1);
    final points = <Offset>[
      for (var index = 0; index < values.length; index++)
        Offset(
          values.length == 1 ? size.width / 2 : index * horizontalStep,
          size.height -
              (_monthlyMetricValue(values[index], metric) / denominator) *
                  (size.height - 8),
        ),
    ];

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }
    final fillPath = Path.from(linePath)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x553C57E8), Color(0x083C57E8)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = const Color(0xFF3C57E8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    final pointPaint = Paint()..color = const Color(0xFF3C57E8);
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      canvas.drawCircle(point, 3, pointPaint);
      if (index == selectedIndex) {
        canvas.drawCircle(
          point,
          7,
          Paint()
            ..color = const Color(0xFF3C57E8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        canvas.drawLine(
          Offset(point.dx, 0),
          Offset(point.dx, size.height),
          Paint()
            ..color = const Color(0x663C57E8)
            ..strokeWidth = 1,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EvolutionPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.metric != metric ||
      oldDelegate.selectedIndex != selectedIndex;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.icon,
    this.iconColor = const Color(0xFF243A96),
    this.iconBackground = const Color(0xFFE7EBFF),
    required this.child,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 21),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: Color(0xFF71809D),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _MetricBox extends StatelessWidget {
  const _MetricBox({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF71809D),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderExpansion extends StatelessWidget {
  const _OrderExpansion({
    super.key,
    required this.order,
    required this.detail,
    required this.loading,
    required this.error,
    required this.onExpand,
    required this.metric,
    this.highlighted = false,
  });

  final CustomerOrderSummary order;
  final CustomerOrderDetail? detail;
  final bool loading;
  final String? error;
  final VoidCallback onExpand;
  final _AnalysisMetric metric;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFF6F8FF) : null,
        borderRadius: BorderRadius.circular(10),
        border: highlighted ? Border.all(color: const Color(0xFFD9DFFF)) : null,
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        onExpansionChanged: (expanded) {
          if (expanded) onExpand();
        },
        title: Text(
          'Pedido ${order.orderNumber}',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              Text(_date(order.date)),
              Text(
                _formatMetric(_orderMetricValue(order, metric), metric),
                style: const TextStyle(
                  color: Color(0xFF087B5A),
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (metric != _AnalysisMetric.skus)
                Text('${order.productCount} produtos'),
            ],
          ),
        ),
        children: [
          if (loading)
            const Padding(
              padding: EdgeInsets.all(18),
              child: CircularProgressIndicator(),
            )
          else if (error != null)
            _MessageCard(
              message: error!,
              actionLabel: 'Tentar',
              onAction: onExpand,
            )
          else if (detail != null)
            _OrderDetailBody(detail: detail!)
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _OrderDetailBody extends StatelessWidget {
  const _OrderDetailBody({required this.detail});

  final CustomerOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Pill(text: _currency(detail.amount)),
            _Pill(text: '${_decimal(detail.volume)} vol.'),
            _Pill(text: '${_decimal(detail.quantity)} un.'),
          ],
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < detail.items.length; index++) ...[
          _OrderItemRow(item: detail.items[index]),
          if (index < detail.items.length - 1) const Divider(height: 18),
        ],
        if (detail.truncated)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'A lista foi limitada aos primeiros 250 itens.',
              style: TextStyle(color: Color(0xFFB26A00), fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _OrderItemRow extends StatelessWidget {
  const _OrderItemRow({required this.item});

  final CustomerOrderItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${item.productCode} · ${item.productName}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          item.supplierName,
          style: const TextStyle(color: Color(0xFF71809D), fontSize: 12),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 10,
          runSpacing: 5,
          children: [
            Text('${_decimal(item.volume)} vol.'),
            Text('${_decimal(item.quantity)} un.'),
            Text(
              _currency(item.amount),
              style: const TextStyle(
                color: Color(0xFF087B5A),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProductMetricRow extends StatelessWidget {
  const _ProductMetricRow({
    required this.rank,
    required this.product,
    required this.metric,
  });

  final int rank;
  final CustomerProductMetric product;
  final _AnalysisMetric metric;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RankBadge(rank: rank),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${product.productCode} · ${product.productName}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (product.package != null)
                Text(
                  product.package!,
                  style: const TextStyle(
                    color: Color(0xFF71809D),
                    fontSize: 12,
                  ),
                ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 5,
                children: [
                  Text('${_decimal(product.volume)} vol.'),
                  Text('${_decimal(product.quantity)} un.'),
                  Text(
                    _formatMetric(_productMetricValue(product, metric), metric),
                    style: const TextStyle(
                      color: Color(0xFF087B5A),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SupplierMetricRow extends StatelessWidget {
  const _SupplierMetricRow({
    required this.rank,
    required this.supplier,
    required this.metric,
  });

  final int rank;
  final CustomerSupplierMetric supplier;
  final _AnalysisMetric metric;

  @override
  Widget build(BuildContext context) {
    final logoUrl =
        '${SupabaseConfig.url}/storage/v1/object/public/fornecedores-logos/${supplier.supplierCode}.png';
    return Row(
      children: [
        _RankBadge(rank: rank),
        const SizedBox(width: 10),
        Container(
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE1E6F0)),
          ),
          child: Image.network(
            logoUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(
              Icons.inventory_2_outlined,
              color: Color(0xFF71809D),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                supplier.supplierName,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                'Fornecedor ${supplier.supplierCode} · ${supplier.skuCount} SKUs',
                style: const TextStyle(color: Color(0xFF71809D), fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _formatMetric(_supplierMetricValue(supplier, metric), metric),
          style: const TextStyle(
            color: Color(0xFF087B5A),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFFFFF2C7),
        shape: BoxShape.circle,
      ),
      child: Text(
        '$rank',
        style: const TextStyle(
          color: Color(0xFF9A6500),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DataLine extends StatelessWidget {
  const _DataLine({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF63708A)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF71809D),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor ?? const Color(0xFF1F2A44),
                    fontWeight: FontWeight.w700,
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.blocked, this.compact = false});

  final bool blocked;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = blocked ? const Color(0xFFB3261E) : const Color(0xFF087B5A);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 10,
        vertical: compact ? 3 : 6,
      ),
      decoration: BoxDecoration(
        color: compact ? color.withValues(alpha: 0.1) : Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            blocked ? Icons.lock_outline : Icons.check_circle_outline,
            color: color,
            size: compact ? 13 : 16,
          ),
          SizedBox(width: compact ? 3 : 5),
          Text(
            blocked ? 'Bloqueado' : 'Desbloqueado',
            style: TextStyle(
              color: color,
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineInfo extends StatelessWidget {
  const _InlineInfo({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF71809D)),
        const SizedBox(width: 3),
        Text(
          text,
          style: const TextStyle(color: Color(0xFF71809D), fontSize: 12),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F3FA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF8B96AB)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF71809D)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1D7A6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF9A6500)),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class _FullPageError extends StatelessWidget {
  const _FullPageError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFFB3261E)),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationUnavailable implements Exception {
  const _LocationUnavailable(this.message);

  final String message;
}

final NumberFormat _currencyFormat = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
);
final NumberFormat _decimalFormat = NumberFormat.decimalPatternDigits(
  locale: 'pt_BR',
  decimalDigits: 2,
);

String _currency(double value) => _currencyFormat.format(value);
String _decimal(double value) => _decimalFormat.format(value);
String _date(DateTime value) => DateFormat('dd/MM/yyyy').format(value);

String _monthName(DateTime value) {
  final formatted = DateFormat('MMMM/yyyy', 'pt_BR').format(value);
  return '${formatted[0].toUpperCase()}${formatted.substring(1)}';
}

String _shortMonth(DateTime value) =>
    DateFormat('MMM/yy', 'pt_BR').format(value).replaceAll('.', '');

double _metricValue(CustomerMetricValues values, _AnalysisMetric metric) =>
    switch (metric) {
      _AnalysisMetric.financial => values.financial,
      _AnalysisMetric.volume => values.volume,
      _AnalysisMetric.skus => values.skus,
    };

CustomerMetricAveragePair _metricAverages(
  CustomerMetricAverages values,
  _AnalysisMetric metric,
) => switch (metric) {
  _AnalysisMetric.financial => values.financial,
  _AnalysisMetric.volume => values.volume,
  _AnalysisMetric.skus => values.skus,
};

CustomerOrderSummary? _largestOrder(
  CustomerMetricOrders values,
  _AnalysisMetric metric,
) => switch (metric) {
  _AnalysisMetric.financial => values.financial,
  _AnalysisMetric.volume => values.volume,
  _AnalysisMetric.skus => values.skus,
};

double _orderMetricValue(CustomerOrderSummary value, _AnalysisMetric metric) =>
    switch (metric) {
      _AnalysisMetric.financial => value.amount,
      _AnalysisMetric.volume => value.volume,
      _AnalysisMetric.skus => value.productCount.toDouble(),
    };

double _monthlyMetricValue(CustomerMonthlySale value, _AnalysisMetric metric) =>
    switch (metric) {
      _AnalysisMetric.financial => value.amount,
      _AnalysisMetric.volume => value.volume,
      _AnalysisMetric.skus => value.skus,
    };

double _productMetricValue(
  CustomerProductMetric value,
  _AnalysisMetric metric,
) => switch (metric) {
  _AnalysisMetric.financial => value.amount,
  _AnalysisMetric.volume => value.volume,
  _AnalysisMetric.skus => 1,
};

double _supplierMetricValue(
  CustomerSupplierMetric value,
  _AnalysisMetric metric,
) => switch (metric) {
  _AnalysisMetric.financial => value.amount,
  _AnalysisMetric.volume => value.volume,
  _AnalysisMetric.skus => value.skuCount.toDouble(),
};

double _lostProductMetricValue(
  CustomerLostProduct value,
  _AnalysisMetric metric,
) => switch (metric) {
  _AnalysisMetric.financial => value.amount,
  _AnalysisMetric.volume => value.volume,
  _AnalysisMetric.skus => 1,
};

double _returnSummaryMetricValue(
  CustomerReturnsSummary value,
  _AnalysisMetric metric,
) => switch (metric) {
  _AnalysisMetric.financial => value.totalAmount,
  _AnalysisMetric.volume => value.totalVolume,
  _AnalysisMetric.skus => value.totalSkus.toDouble(),
};

double _returnMetricValue(
  CustomerReturnSummary value,
  _AnalysisMetric metric,
) => switch (metric) {
  _AnalysisMetric.financial => value.amount,
  _AnalysisMetric.volume => value.volume,
  _AnalysisMetric.skus => value.itemCount.toDouble(),
};

String _formatMetric(double value, _AnalysisMetric metric) => switch (metric) {
  _AnalysisMetric.financial => _currency(value),
  _AnalysisMetric.volume => '${_decimal(value)} vol.',
  _AnalysisMetric.skus =>
    value == 1
        ? '1 SKU'
        : '${value == value.roundToDouble() ? value.toInt() : value.toStringAsFixed(1).replaceAll('.', ',')} SKUs',
};

String _compactMetric(double value, _AnalysisMetric metric) {
  if (metric != _AnalysisMetric.financial) return _formatMetric(value, metric);
  final absolute = value.abs();
  if (absolute >= 1000000) {
    return 'R\$ ${(value / 1000000).toStringAsFixed(1).replaceAll('.', ',')} mi';
  }
  if (absolute >= 1000) {
    return 'R\$ ${(value / 1000).toStringAsFixed(1).replaceAll('.', ',')} mil';
  }
  return 'R\$ ${value.round()}';
}

String _activeMonthsSubtitle(String prefix, List<DateTime> months) {
  if (months.isEmpty) return '$prefix · sem compras registradas';
  final count = months.length;
  final period = count == 1
      ? 'último mês com compra'
      : 'últimos $count meses com compra';
  return '$prefix · $period';
}

String _distanceLabel(double distanceKm) {
  if (distanceKm < 1) return '${(distanceKm * 1000).round()} m';
  return '${distanceKm.toStringAsFixed(distanceKm < 10 ? 1 : 0)} km';
}

String _document(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 11) {
    return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.'
        '${digits.substring(6, 9)}-${digits.substring(9)}';
  }
  if (digits.length == 14) {
    return '${digits.substring(0, 2)}.${digits.substring(2, 5)}.'
        '${digits.substring(5, 8)}/${digits.substring(8, 12)}-'
        '${digits.substring(12)}';
  }
  return value;
}
