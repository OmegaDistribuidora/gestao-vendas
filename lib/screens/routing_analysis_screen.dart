import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_theme.dart';
import '../models/routing_analysis.dart';
import '../services/routing_analysis_service.dart';

class RoutingAnalysisScreen extends StatefulWidget {
  const RoutingAnalysisScreen({super.key});

  @override
  State<RoutingAnalysisScreen> createState() => _RoutingAnalysisScreenState();
}

class _RoutingAnalysisScreenState extends State<RoutingAnalysisScreen> {
  final RoutingAnalysisService _service = RoutingAnalysisService();
  final MapController _mapController = MapController();
  final DateFormat _dateFormat = DateFormat("EEEE, dd 'de' MMMM", 'pt_BR');
  final DateFormat _shortDateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');
  final DateFormat _timeFormat = DateFormat('HH:mm');
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  DateTime _selectedStartDate = _day(DateTime.now());
  DateTime _selectedEndDate = _day(DateTime.now());
  _RoutingDateMode _dateMode = _RoutingDateMode.day;
  RoutingAnalysis? _analysis;
  String? _selectedScopeValue;
  bool _loading = true;
  bool _silentLoading = false;
  String? _errorMessage;
  _RoutingView _view = _RoutingView.list;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => unawaited(_load(silent: true)),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  RoutingScopeOption? get _selectedScope {
    final value = _selectedScopeValue;
    if (value == null) {
      return null;
    }
    for (final option in _analysis?.availableScopes ?? const []) {
      if (option.value == value) {
        return option;
      }
    }
    return null;
  }

  bool get _analysisMatchesSelection {
    final analysis = _analysis;
    if (analysis == null ||
        _day(analysis.startDate) != _selectedStartDate ||
        _day(analysis.endDate) != _selectedEndDate) {
      return false;
    }
    final scope = _selectedScope;
    return analysis.selectedScopeProfileSlug == scope?.profileSlug &&
        analysis.selectedScopeOwnerCode == scope?.ownerCode;
  }

  Future<void> _load({bool silent = false}) async {
    if (silent && (_loading || _silentLoading)) {
      return;
    }
    if (silent) {
      _silentLoading = true;
    } else {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    final scope = _selectedScope;
    try {
      final result = await _service.load(
        startDate: _selectedStartDate,
        endDate: _selectedEndDate,
        targetScopeProfileSlug: scope?.profileSlug,
        targetScopeOwnerCode: scope?.ownerCode,
      );
      if (!mounted) {
        return;
      }
      final availableValues = result.availableScopes
          .map((option) => option.value)
          .toSet();
      setState(() {
        _analysis = result;
        if (_selectedScopeValue != null &&
            !availableValues.contains(_selectedScopeValue)) {
          _selectedScopeValue = null;
        }
        if (!result.mapAvailable) {
          _view = _RoutingView.list;
        }
        _loading = false;
        _errorMessage = null;
      });
      if (_view == _RoutingView.map) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _focusMap());
      }
    } catch (error) {
      if (!mounted || silent) {
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = error is RoutingAnalysisException
            ? error.message
            : 'Não foi possível carregar a roteirização. Tente novamente.';
      });
    } finally {
      _silentLoading = false;
    }
  }

  Future<void> _selectDate() async {
    if (_dateMode == _RoutingDateMode.period) {
      final selected = await showDateRangePicker(
        context: context,
        initialDateRange: DateTimeRange(
          start: _selectedStartDate,
          end: _selectedEndDate,
        ),
        firstDate: DateTime(2026, 6),
        lastDate: DateTime(2030, 12, 31),
        helpText: 'Selecione o período do roteiro',
        cancelText: 'Cancelar',
        confirmText: 'Selecionar',
        saveText: 'Selecionar',
      );
      if (selected == null) {
        return;
      }
      final start = _day(selected.start);
      final end = _day(selected.end);
      if (end.difference(start).inDays >= 31) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Selecione um período de no máximo 31 dias.'),
            ),
          );
        }
        return;
      }
      if (start == _selectedStartDate && end == _selectedEndDate) {
        return;
      }
      setState(() {
        _selectedStartDate = start;
        _selectedEndDate = end;
        _view = _RoutingView.list;
      });
      await _load();
      return;
    }

    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedStartDate,
      firstDate: DateTime(2026, 6),
      lastDate: DateTime(2030, 12, 31),
      helpText: 'Selecione o dia do roteiro',
      cancelText: 'Cancelar',
      confirmText: 'Selecionar',
    );
    if (selected == null || _day(selected) == _selectedStartDate) {
      return;
    }
    setState(() {
      _selectedStartDate = _day(selected);
      _selectedEndDate = _selectedStartDate;
      _view = _RoutingView.list;
    });
    await _load();
  }

  Future<void> _moveDate(int days) async {
    final rangeDays =
        _selectedEndDate.difference(_selectedStartDate).inDays + 1;
    final offset = _dateMode == _RoutingDateMode.period
        ? days * rangeDays
        : days;
    setState(() {
      _selectedStartDate = _day(_selectedStartDate.add(Duration(days: offset)));
      _selectedEndDate = _day(_selectedEndDate.add(Duration(days: offset)));
      _view = _RoutingView.list;
    });
    await _load();
  }

  Future<void> _changeDateMode(_RoutingDateMode mode) async {
    if (mode == _dateMode) {
      return;
    }
    setState(() {
      _dateMode = mode;
      if (mode == _RoutingDateMode.day) {
        _selectedStartDate = _selectedEndDate;
      } else {
        _selectedStartDate = _day(
          _selectedEndDate.subtract(const Duration(days: 6)),
        );
      }
      _selectedEndDate = mode == _RoutingDateMode.day
          ? _selectedStartDate
          : _selectedEndDate;
      _view = _RoutingView.list;
    });
    await _load();
  }

  Future<void> _openScopePicker() async {
    final analysis = _analysis;
    if (analysis == null || analysis.availableScopes.isEmpty) {
      return;
    }
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RoutingScopePicker(
        options: analysis.availableScopes,
        selectedValue: _selectedScopeValue,
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    final nextValue = result.isEmpty ? null : result;
    if (nextValue == _selectedScopeValue) {
      return;
    }
    setState(() {
      _selectedScopeValue = nextValue;
      _view = _RoutingView.list;
    });
    await _load();
  }

  Future<void> _openSeller(RoutingSellerSummary seller) async {
    final option = _analysis?.availableScopes
        .cast<RoutingScopeOption?>()
        .firstWhere(
          (item) =>
              item?.profileSlug == 'vendedor' &&
              item?.ownerCode == seller.sellerCode,
          orElse: () => null,
        );
    if (option == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este vendedor não está disponível no filtro.'),
          ),
        );
      }
      return;
    }
    setState(() {
      _selectedScopeValue = option.value;
      _view = _RoutingView.list;
    });
    await _load();
  }

  void _changeView(_RoutingView view) {
    setState(() => _view = view);
    if (view == _RoutingView.map) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusMap());
    }
  }

  List<RoutingCustomer> get _mappedCustomers => (_analysis?.items ?? const [])
      .where((customer) => customer.hasCoordinates)
      .toList(growable: false);

  void _focusMap() {
    if (!mounted || _view != _RoutingView.map) {
      return;
    }
    final points = _mappedCustomers
        .map((customer) => LatLng(customer.latitude!, customer.longitude!))
        .toList(growable: false);
    if (points.isEmpty) {
      return;
    }
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.all(52),
        maxZoom: 16,
      ),
    );
  }

  void _showCustomer(RoutingCustomer customer) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _RoutingCustomerSheet(
        customer: customer,
        currencyFormat: _currencyFormat,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Roteirização'),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _load(),
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && !_analysisMatchesSelection) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null && !_analysisMatchesSelection) {
      return _RoutingError(message: _errorMessage!, onRetry: _load);
    }

    final analysis = _analysis!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildFilters(analysis),
          const SizedBox(height: 14),
          if (!analysis.available)
            _RoutingEmpty(
              icon: Icons.event_busy_outlined,
              title: 'Dados ainda não disponíveis',
              message: analysis.isPeriod
                  ? 'Ainda não há capturas do roteiro para este período.'
                  : 'Ainda não há uma captura do roteiro para esta data.',
            )
          else if (!analysis.applicable || analysis.planned == 0)
            _RoutingEmpty(
              icon: Icons.route_outlined,
              title: analysis.isPeriod
                  ? 'Sem roteiro para este período'
                  : 'Sem roteiro para esta data',
              message: analysis.isSellerView
                  ? analysis.isPeriod
                        ? 'O vendedor selecionado não possui clientes programados neste período.'
                        : 'O vendedor selecionado não possui clientes programados neste dia.'
                  : analysis.isPeriod
                  ? 'Não existem clientes roteirizados neste escopo para o período selecionado.'
                  : 'Não existem clientes roteirizados neste escopo para o dia selecionado.',
            )
          else ...[
            _buildSummary(analysis),
            const SizedBox(height: 14),
            if (analysis.isSellerView)
              _buildSellerContent(analysis)
            else
              _buildTeam(analysis),
          ],
        ],
      ),
    );
  }

  Widget _buildFilters(RoutingAnalysis analysis) {
    final dateLabel = _dateMode == _RoutingDateMode.day
        ? _capitalize(_dateFormat.format(_selectedStartDate))
        : '${_shortDateFormat.format(_selectedStartDate)} a '
              '${_shortDateFormat.format(_selectedEndDate)}';
    final scope = _selectedScope;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune_rounded, color: primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Filtros do roteiro',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (_silentLoading)
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const SizedBox(width: 48),
                const SizedBox(width: 8),
                Expanded(
                  child: SegmentedButton<_RoutingDateMode>(
                    segments: const [
                      ButtonSegment<_RoutingDateMode>(
                        value: _RoutingDateMode.day,
                        icon: Icon(Icons.today_outlined),
                        label: Text('Dia'),
                      ),
                      ButtonSegment<_RoutingDateMode>(
                        value: _RoutingDateMode.period,
                        icon: Icon(Icons.date_range_outlined),
                        label: Text('Período'),
                      ),
                    ],
                    selected: {_dateMode},
                    showSelectedIcon: false,
                    onSelectionChanged: _loading
                        ? null
                        : (selection) => _changeDateMode(selection.first),
                  ),
                ),
                const SizedBox(width: 8),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton.outlined(
                  onPressed: () => _moveDate(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: _dateMode == _RoutingDateMode.day
                      ? 'Dia anterior'
                      : 'Período anterior',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selectDate,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(dateLabel, textAlign: TextAlign.center),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: () => _moveDate(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: _dateMode == _RoutingDateMode.day
                      ? 'Próximo dia'
                      : 'Próximo período',
                ),
              ],
            ),
            if (analysis.availableScopes.isNotEmpty) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: _openScopePicker,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Filtrar visualização',
                    prefixIcon: Icon(Icons.groups_2_outlined),
                    suffixIcon: Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  child: Text(
                    scope?.label ?? 'Minha visão geral',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(RoutingAnalysis analysis) {
    final updatedAt = analysis.updatedAt?.toLocal();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8ECFF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.route_rounded, color: primaryColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        analysis.isSellerView
                            ? '${analysis.effectiveOwnerCode} - ${analysis.effectiveDisplayName}'
                            : 'Resumo da equipe',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (updatedAt != null)
                        Text(
                          'Atualizado ${_timeFormat.format(updatedAt)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF71809A)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'A atender',
                    value: '${analysis.planned}',
                    color: primaryColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Metric(
                    label: 'Com venda',
                    value: '${analysis.purchased}',
                    color: kpiFinancialColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Metric(
                    label: 'Efetividade',
                    value: _formatPercent(analysis.percent),
                    color: kpiPositivationColor,
                  ),
                ),
              ],
            ),
            if (analysis.isPeriod && analysis.hasIncompletePeriod) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5E5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFFE77A00),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dados disponíveis em ${analysis.availableDays} de '
                        '${analysis.requestedDays} dias do período.',
                        style: const TextStyle(
                          color: Color(0xFF915000),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFE5F4ED),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined, color: kpiFinancialColor),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Venda nos clientes do roteiro',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    _currencyFormat.format(analysis.saleAmount),
                    style: const TextStyle(
                      color: kpiFinancialColor,
                      fontWeight: FontWeight.w900,
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

  Widget _buildTeam(RoutingAnalysis analysis) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Roteiro por vendedor',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Selecione um vendedor para abrir os clientes e o mapa.',
              style: TextStyle(color: Color(0xFF71809A)),
            ),
            const SizedBox(height: 10),
            for (final seller in analysis.sellerSummaries)
              _SellerSummaryTile(
                seller: seller,
                currencyFormat: _currencyFormat,
                onTap: () => _openSeller(seller),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSellerContent(RoutingAnalysis analysis) {
    return Column(
      children: [
        SegmentedButton<_RoutingView>(
          segments: const [
            ButtonSegment(
              value: _RoutingView.list,
              icon: Icon(Icons.list_alt_outlined),
              label: Text('Clientes'),
            ),
            ButtonSegment(
              value: _RoutingView.map,
              icon: Icon(Icons.map_outlined),
              label: Text('Mapa'),
            ),
          ],
          selected: {_view},
          onSelectionChanged: (selection) => _changeView(selection.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 14),
        if (_view == _RoutingView.map)
          _buildMap(analysis)
        else
          _buildCustomerList(analysis),
      ],
    );
  }

  Widget _buildCustomerList(RoutingAnalysis analysis) {
    return Column(
      children: [
        for (final customer in analysis.items) ...[
          _RoutingCustomerCard(
            customer: customer,
            currencyFormat: _currencyFormat,
            showDate: analysis.isPeriod,
            onTap: () => _showCustomer(customer),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildMap(RoutingAnalysis analysis) {
    final customers = _mappedCustomers;
    if (customers.isEmpty) {
      return const _RoutingEmpty(
        icon: Icons.location_off_outlined,
        title: 'Clientes sem localização',
        message:
            'Os clientes deste roteiro não possuem coordenadas disponíveis.',
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 500,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: const MapOptions(
                initialCenter: LatLng(-5.2, -39.5),
                initialZoom: 6,
                minZoom: 3,
                maxZoom: 19,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName:
                      'br.com.omegadistribuidora.gestao_vendas',
                  maxNativeZoom: 19,
                  errorTileCallback: kDebugMode
                      ? (tile, error, stackTrace) {
                          debugPrint('Routing map tile failed: $error');
                        }
                      : null,
                ),
                MarkerClusterLayerWidget(
                  options: MarkerClusterLayerOptions(
                    size: const Size(44, 44),
                    maxClusterRadius: 52,
                    disableClusteringAtZoom: 17,
                    markers: [
                      for (final customer in customers)
                        Marker(
                          point: LatLng(
                            customer.latitude!,
                            customer.longitude!,
                          ),
                          width: 42,
                          height: 42,
                          child: GestureDetector(
                            onTap: () => _showCustomer(customer),
                            child: _MapMarker(purchased: customer.purchased),
                          ),
                        ),
                    ],
                    builder: (context, markers) => Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(color: Color(0x33000000), blurRadius: 6),
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
                const RichAttributionWidget(
                  attributions: [TextSourceAttribution('OpenStreetMap')],
                ),
              ],
            ),
            Positioned(
              top: 12,
              right: 12,
              child: FloatingActionButton.small(
                heroTag: 'fit-routing-map',
                onPressed: _focusMap,
                tooltip: 'Mostrar todos os clientes',
                backgroundColor: Colors.white,
                foregroundColor: primaryColor,
                child: const Icon(Icons.center_focus_strong_rounded),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const _LegendDot(color: kpiFinancialColor),
                      const SizedBox(width: 6),
                      const Text('Com venda'),
                      const SizedBox(width: 16),
                      const _LegendDot(color: Color(0xFF7A879D)),
                      const SizedBox(width: 6),
                      const Text('Sem venda'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

  static String _formatPercent(double? value) {
    if (value == null) {
      return '--';
    }
    final fixed = value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
    return '${fixed.replaceAll('.', ',')}%';
  }
}

enum _RoutingView { list, map }

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF71809A),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerSummaryTile extends StatelessWidget {
  const _SellerSummaryTile({
    required this.seller,
    required this.currencyFormat,
    required this.onTap,
  });
  final RoutingSellerSummary seller;
  final NumberFormat currencyFormat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFE8ECFF),
              foregroundColor: primaryColor,
              child: Text(
                seller.sellerCode,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: seller.sellerName),
                        TextSpan(
                          text:
                              '  ${_RoutingAnalysisScreenState._formatPercent(seller.percent)}',
                          style: const TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${seller.purchased}/${seller.planned} com venda • '
                    '${currencyFormat.format(seller.saleAmount)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF71809A),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _RoutingCustomerCard extends StatelessWidget {
  const _RoutingCustomerCard({
    required this.customer,
    required this.currencyFormat,
    required this.showDate,
    required this.onTap,
  });
  final RoutingCustomer customer;
  final NumberFormat currencyFormat;
  final bool showDate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = customer.purchased
        ? kpiFinancialColor
        : const Color(0xFF71809A);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  customer.purchased
                      ? Icons.check_circle_outline_rounded
                      : Icons.storefront_outlined,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showDate && customer.referenceDate != null) ...[
                      Text(
                        DateFormat(
                          "EEEE, dd/MM",
                          'pt_BR',
                        ).format(customer.referenceDate!),
                        style: const TextStyle(
                          color: primaryColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      '${customer.code} • ${customer.name}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (customer.addressLine.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        customer.addressLine,
                        style: const TextStyle(
                          color: Color(0xFF71809A),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      customer.purchased
                          ? currencyFormat.format(customer.saleAmount)
                          : 'Sem venda',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              if (!customer.hasCoordinates)
                const Tooltip(
                  message: 'Localização indisponível',
                  child: Icon(
                    Icons.location_off_outlined,
                    color: Color(0xFF9AA5B7),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapMarker extends StatelessWidget {
  const _MapMarker({required this.purchased});
  final bool purchased;

  @override
  Widget build(BuildContext context) {
    final color = purchased ? kpiFinancialColor : const Color(0xFF7A879D);
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 5)],
      ),
      child: Icon(
        purchased ? Icons.check_rounded : Icons.storefront_outlined,
        color: Colors.white,
        size: 20,
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _RoutingCustomerSheet extends StatelessWidget {
  const _RoutingCustomerSheet({
    required this.customer,
    required this.currencyFormat,
  });
  final RoutingCustomer customer;
  final NumberFormat currencyFormat;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${customer.code} • ${customer.name}',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            _DetailLine(
              icon: Icons.location_on_outlined,
              text: customer.addressLine,
            ),
            if (customer.routeCode.isNotEmpty && customer.routeCode != '0')
              _DetailLine(
                icon: Icons.route_outlined,
                text:
                    'Rota ${customer.routeCode}'
                    '${customer.routeSequence > 0 ? ' • Sequência ${customer.routeSequence}' : ''}',
              ),
            if (customer.referenceDate != null)
              _DetailLine(
                icon: Icons.calendar_today_outlined,
                text: DateFormat(
                  "EEEE, dd 'de' MMMM 'de' yyyy",
                  'pt_BR',
                ).format(customer.referenceDate!),
              ),
            _DetailLine(
              icon: customer.purchased
                  ? Icons.check_circle_outline_rounded
                  : Icons.remove_shopping_cart_outlined,
              text: customer.purchased
                  ? 'Venda concluída: ${currencyFormat.format(customer.saleAmount)}'
                  : 'Sem venda neste dia',
              color: customer.purchased
                  ? kpiFinancialColor
                  : const Color(0xFF71809A),
            ),
          ],
        ),
      ),
    );
  }
}

enum _RoutingDateMode { day, period }

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color ?? primaryColor, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutingScopePicker extends StatefulWidget {
  const _RoutingScopePicker({
    required this.options,
    required this.selectedValue,
  });
  final List<RoutingScopeOption> options;
  final String? selectedValue;

  @override
  State<_RoutingScopePicker> createState() => _RoutingScopePickerState();
}

class _RoutingScopePickerState extends State<_RoutingScopePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final normalized = _query.trim().toLowerCase();
    final options = widget.options
        .where((option) {
          return normalized.isEmpty ||
              option.label.toLowerCase().contains(normalized) ||
              option.ownerCode.toLowerCase().contains(normalized);
        })
        .toList(growable: false);

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.86,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selecione quem deseja analisar',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      hintText: 'Buscar por nome ou código',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                children: [
                  if (normalized.isEmpty)
                    ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.home_outlined),
                      ),
                      title: const Text('Minha visão geral'),
                      trailing: widget.selectedValue == null
                          ? const Icon(Icons.check_circle, color: primaryColor)
                          : null,
                      onTap: () => Navigator.of(context).pop(''),
                    ),
                  for (final option in options)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFE8ECFF),
                        child: Icon(
                          _scopeIcon(option.profileSlug),
                          color: primaryColor,
                        ),
                      ),
                      title: Text(
                        option.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(_scopeSubtitle(option)),
                      trailing: widget.selectedValue == option.value
                          ? const Icon(Icons.check_circle, color: primaryColor)
                          : null,
                      onTap: () => Navigator.of(context).pop(option.value),
                    ),
                  if (options.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(28),
                      child: Text(
                        'Nenhum usuário encontrado.',
                        textAlign: TextAlign.center,
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

  static IconData _scopeIcon(String profile) => switch (profile) {
    'gerencia' => Icons.manage_accounts_outlined,
    'coordenador' => Icons.account_tree_outlined,
    'supervisor' => Icons.supervisor_account_outlined,
    _ => Icons.storefront_outlined,
  };

  static String _scopeSubtitle(RoutingScopeOption option) {
    if (option.profileSlug == 'gerencia') {
      return 'Gerência';
    }
    final profile = switch (option.profileSlug) {
      'coordenador' => 'Coordenador',
      'supervisor' => 'Supervisor',
      _ => 'Vendedor',
    };
    return '$profile • ${option.ownerCode}';
  }
}

class _RoutingEmpty extends StatelessWidget {
  const _RoutingEmpty({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
        child: Column(
          children: [
            Icon(icon, size: 48, color: primaryColor),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF71809A)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutingError extends StatelessWidget {
  const _RoutingError({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function({bool silent}) onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: primaryColor,
            ),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => onRetry(),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
