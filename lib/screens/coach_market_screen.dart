import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/app_theme.dart';
import '../models/coach_market.dart';
import '../services/coach_market_service.dart';

class CoachMarketScreen extends StatefulWidget {
  const CoachMarketScreen({
    super.key,
    this.initialCustomer,
    this.startInForm = false,
  });

  final CoachMarketCustomer? initialCustomer;
  final bool startInForm;

  @override
  State<CoachMarketScreen> createState() => _CoachMarketScreenState();
}

class _CoachMarketScreenState extends State<CoachMarketScreen> {
  final _customerCode = TextEditingController();
  final _service = CoachMarketService.instance;
  final _geocoding = Geocoding(locale: const Locale('pt', 'BR'));
  final Map<int, bool> _answers = {};

  CoachMarketCustomer? _customer;
  bool _lookupUnavailable = false;
  bool _lookupSucceeded = false;
  bool _formMode = false;
  bool _searching = false;
  bool _submitting = false;
  int _pendingCount = 0;
  String? _lookupWarning;

  @override
  void initState() {
    super.initState();
    final initialCustomer = widget.initialCustomer;
    if (initialCustomer != null) {
      _customer = initialCustomer;
      _customerCode.text = initialCustomer.code.toString();
      _lookupSucceeded = true;
      _formMode = widget.startInForm;
    }
    _refreshPendingCount();
  }

  @override
  void dispose() {
    _customerCode.dispose();
    super.dispose();
  }

  Future<void> _refreshPendingCount() async {
    final count = await _service.pendingCount();
    if (mounted) setState(() => _pendingCount = count);
  }

  Future<void> _searchCustomer() async {
    FocusScope.of(context).unfocus();
    final code = int.tryParse(_customerCode.text.trim());
    if (code == null || code < 1) {
      _showMessage('Informe um código de cliente válido.', error: true);
      return;
    }

    setState(() {
      _searching = true;
      _customer = null;
      _lookupUnavailable = false;
      _lookupSucceeded = false;
      _formMode = false;
      _lookupWarning = null;
      _answers.clear();
    });
    try {
      final customer = await _service.findCustomer(code);
      if (!mounted) return;
      setState(() {
        _customer = customer;
        _lookupSucceeded = true;
      });
    } on CoachMarketServiceException catch (error) {
      if (!mounted) return;
      if (error.retryable) {
        setState(() {
          _lookupUnavailable = true;
          _lookupWarning =
              'Conexão falhou com o servidor da Ômega, mas você ainda pode marcar as opções e enviar suas respostas.';
        });
      } else {
        _showMessage(error.message, error: true);
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  CoachMarketCustomer? _buildCustomer() {
    final code = int.tryParse(_customerCode.text.trim());
    if (code == null) return null;
    if (_customer != null) return _customer;
    if (!_lookupUnavailable) return null;
    return CoachMarketCustomer(
      code: code,
      name: 'Dados aguardando consulta na API',
      neverPurchased: true,
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final customer = _buildCustomer();
    if (customer == null) return;
    if (_answers.length != coachMarketSections.length) {
      final missing = coachMarketSections.length - _answers.length;
      _showMessage(
        'Responda Sim ou Não para ${missing == 1 ? 'a seção restante' : 'as $missing seções restantes'}.',
        error: true,
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final location = await _captureRequiredLocation();
      final package = await PackageInfo.fromPlatform();
      final submission = CoachMarketSubmission(
        submissionId: _newUuid(),
        customer: customer,
        customerDataSource: 'api',
        customerLookupSucceeded: _lookupSucceeded,
        location: location,
        filledAt: DateTime.now().toUtc(),
        appVersion: package.buildNumber.trim().isEmpty
            ? package.version
            : '${package.version}+${package.buildNumber}',
        answers: Map<int, bool>.unmodifiable(_answers),
      );
      final result = await _service.submitOrQueue(
        submission,
        requiresCustomerLookup: _lookupUnavailable,
      );
      if (!mounted) return;
      await _refreshPendingCount();
      await _showSuccessDialog(queued: result.queued);
      if (!mounted) return;
      if (result.sent) {
        await _searchCustomer();
      } else {
        setState(() {
          _formMode = false;
          _answers.clear();
        });
      }
    } on CoachMarketLocationException catch (error) {
      if (mounted) _showMessage(error.message, error: true);
    } on CoachMarketServiceException catch (error) {
      if (mounted) _showMessage(error.message, error: true);
    } catch (_) {
      if (mounted) {
        _showMessage('Não foi possível concluir o envio.', error: true);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<CoachMarketLocation> _captureRequiredLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const CoachMarketLocationException(
        'Ative a localização do aparelho para enviar o formulário.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const CoachMarketLocationException(
        'A localização é obrigatória para usar o Coach Mercado.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const CoachMarketLocationException(
        'A permissão de localização foi bloqueada. Libere-a nas configurações do aparelho.',
      );
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return CoachMarketLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        address: await _resolveAddress(position),
        capturedAt: DateTime.now().toUtc(),
      );
    } catch (_) {
      throw const CoachMarketLocationException(
        'Não foi possível obter sua localização. Tente novamente em um local com melhor sinal.',
      );
    }
  }

  Future<String?> _resolveAddress(Position position) async {
    try {
      final places = await _geocoding.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (places.isEmpty) return null;
      final place = places.first;
      final parts = [
        place.street,
        place.subLocality,
        place.locality,
        place.administrativeArea,
      ].map((item) => item?.trim() ?? '').where((item) => item.isNotEmpty);
      final address = parts.join(' · ');
      return address.isEmpty ? null : address;
    } catch (_) {
      return null;
    }
  }

  Future<void> _showSuccessDialog({required bool queued}) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          queued ? Icons.cloud_off_outlined : Icons.check_circle_outline,
          color: queued ? const Color(0xFFE58A00) : const Color(0xFF087B5A),
          size: 42,
        ),
        title: Text(queued ? 'Salvo no aparelho' : 'Formulário enviado'),
        content: Text(
          queued
              ? 'O formulário foi protegido no aparelho. Quando a conexão voltar, o app consultará os dados oficiais do cliente e enviará as respostas automaticamente.'
              : 'As respostas foram registradas no Coach Mercado.',
          textAlign: TextAlign.center,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _startNewForm() {
    setState(() {
      _formMode = true;
      _answers.clear();
    });
  }

  void _showMessage(String message, {required bool error}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : const Color(0xFF087B5A),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canStartForm = _customer != null || _lookupUnavailable;
    final canAnswer = _formMode && canStartForm;
    return Scaffold(
      appBar: AppBar(title: const Text('Coach Mercado')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            if (_pendingCount > 0) _buildPendingBanner(),
            _buildSearchCard(),
            if (_lookupWarning != null) ...[
              const SizedBox(height: 12),
              _buildWarning(),
            ],
            if (_customer != null) ...[
              const SizedBox(height: 12),
              _buildCustomerCard(_customer!),
            ],
            if (canStartForm && !_formMode) ...[
              const SizedBox(height: 12),
              if (_customer != null)
                _buildHistorySection(_customer!)
              else
                _buildOfflineNewCard(),
            ],
            if (canAnswer) ...[
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Marque se o cliente possui cada seção de produtos abaixo:',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1F2A44),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                            _formMode = false;
                            _answers.clear();
                          }),
                    child: const Text('Voltar'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildSupplierSections(),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(54),
                ),
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(_submitting ? 'Enviando...' : 'Enviar'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPendingBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4DF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFD892)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_upload_outlined, color: Color(0xFFA55D00)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$_pendingCount ${_pendingCount == 1 ? 'formulário aguarda' : 'formulários aguardam'} envio automático.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Consultar cliente',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            const Text(
              'Digite o código do cliente para iniciar o levantamento.',
              style: TextStyle(color: Color(0xFF71809D)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _customerCode,
              enabled: !_searching && !_submitting,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchCustomer(),
              onChanged: (_) {
                if (_customer != null || _lookupUnavailable) {
                  setState(() {
                    _customer = null;
                    _lookupUnavailable = false;
                    _lookupSucceeded = false;
                    _formMode = false;
                    _lookupWarning = null;
                    _answers.clear();
                  });
                }
              },
              decoration: InputDecoration(
                labelText: 'Código do cliente',
                hintText: 'Ex.: 12345',
                prefixIcon: const Icon(Icons.badge_outlined),
                suffixIcon: IconButton(
                  tooltip: 'Buscar cliente',
                  onPressed: _searching ? null : _searchCustomer,
                  icon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(10),
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

  Widget _buildWarning() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFD9A0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFB36500)),
          const SizedBox(width: 10),
          Expanded(child: Text(_lookupWarning!)),
        ],
      ),
    );
  }

  Widget _buildCustomerCard(CoachMarketCustomer customer) {
    final lastPurchase = customer.neverPurchased
        ? 'Este cliente nunca comprou.'
        : 'Última compra: ${DateFormat('dd/MM/yyyy').format(customer.lastPurchaseDate!)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFE8ECFF),
                  foregroundColor: primaryColor,
                  child: Icon(Icons.storefront_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      Text(
                        'Cliente ${customer.code}',
                        style: const TextStyle(color: Color(0xFF71809D)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 26),
            _detail(
              Icons.location_city_outlined,
              _join(customer.city, customer.neighborhood),
            ),
            _detail(
              Icons.home_outlined,
              customer.address ?? 'Endereço não informado',
            ),
            _detail(Icons.shopping_bag_outlined, lastPurchase),
            if (customer.sellerAssignments.isNotEmpty) ...[
              const Divider(height: 22),
              for (final assignment in customer.sellerAssignments)
                _detail(
                  Icons.badge_outlined,
                  'Vendedor: ${assignment.sellerName}; Supervisor: ${assignment.supervisorName}',
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistorySection(CoachMarketCustomer customer) {
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
                    'Últimos registros',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _startNewForm,
                  icon: const Icon(Icons.add, size: 19),
                  label: const Text('Novo'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (customer.history.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.history, color: Color(0xFF71809D)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Nenhum Coach Mercado foi registrado para este cliente.',
                        style: TextStyle(color: Color(0xFF71809D)),
                      ),
                    ),
                  ],
                ),
              )
            else
              for (var index = 0; index < customer.history.length; index++) ...[
                _buildHistoryItem(customer.history[index]),
                if (index != customer.history.length - 1)
                  const Divider(height: 1),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineNewCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'O histórico e os dados do cliente serão consultados quando a conexão voltar.',
              style: TextStyle(color: Color(0xFF71809D)),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _startNewForm,
              icon: const Icon(Icons.add),
              label: const Text('Novo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(CoachMarketHistoryRecord record) {
    final localDate = record.filledAt.toLocal();
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _showHistoryDetails(record),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            _supplierLogo(size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${record.supplierName} · ${DateFormat('dd/MM/yyyy HH:mm').format(localDate)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_formatPercentage(record.yesPercentage)} · ${record.filledByName}',
                    style: const TextStyle(
                      color: Color(0xFF71809D),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF71809D)),
          ],
        ),
      ),
    );
  }

  Future<void> _showHistoryDetails(CoachMarketHistoryRecord record) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.88,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFBBC3D1),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                children: [
                  Row(
                    children: [
                      _supplierLogo(size: 54),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.supplierName,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              _formatPercentage(record.yesPercentage),
                              style: const TextStyle(
                                color: Color(0xFF087B5A),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _detail(
                    Icons.calendar_today_outlined,
                    DateFormat(
                      "dd/MM/yyyy 'às' HH:mm",
                    ).format(record.filledAt.toLocal()),
                  ),
                  _detail(
                    Icons.person_outline,
                    'Preenchido por: ${record.filledByName}',
                  ),
                  if (record.locationAddress != null)
                    _detail(Icons.location_on_outlined, record.locationAddress!)
                  else if (record.latitude != null && record.longitude != null)
                    _detail(
                      Icons.location_on_outlined,
                      '${record.latitude!.toStringAsFixed(6)}, ${record.longitude!.toStringAsFixed(6)}',
                    ),
                  const Divider(height: 28),
                  Text(
                    '${record.yesCount} de ${record.totalCount} seções marcadas como Sim',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  for (final answer in record.answers)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: answer.hasSection
                            ? const Color(0xFFE2F5EE)
                            : const Color(0xFFFFE8E8),
                        foregroundColor: answer.hasSection
                            ? const Color(0xFF087B5A)
                            : const Color(0xFFC62828),
                        child: Icon(
                          answer.hasSection ? Icons.check : Icons.close,
                          size: 19,
                        ),
                      ),
                      title: Text(
                        answer.sectionName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      trailing: Text(
                        answer.hasSection ? 'Sim' : 'Não',
                        style: TextStyle(
                          color: answer.hasSection
                              ? const Color(0xFF087B5A)
                              : const Color(0xFFC62828),
                          fontWeight: FontWeight.w900,
                        ),
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

  Widget _buildSupplierSections() {
    final yesCount = _answers.values.where((answer) => answer).length;
    final yesPercentage = _answers.isEmpty
        ? 0
        : (yesCount * 100 / _answers.length).round();
    return Card(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            decoration: const BoxDecoration(
              color: Color(0xFFFFF8E1),
              borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                _supplierLogo(size: 42),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'Bombril',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE7A4),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$yesPercentage%',
                    style: const TextStyle(
                      color: Color(0xFF8B5700),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                const SizedBox(
                  width: 52,
                  child: Center(
                    child: Text(
                      'Sim',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(
                  width: 52,
                  child: Center(
                    child: Text(
                      'Não',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var index = 0; index < coachMarketSections.length; index++) ...[
            _buildSectionRow(coachMarketSections[index]),
            if (index != coachMarketSections.length - 1)
              const Divider(height: 1, indent: 12, endIndent: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionRow(CoachMarketSectionDefinition section) {
    final answer = _answers[section.code];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 58,
              height: 58,
              color: Colors.white,
              child: Image.asset(
                section.assetPath,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.image_not_supported_outlined),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              section.name,
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.2),
            ),
          ),
          _answerButton(
            selected: answer == true,
            isYes: true,
            semanticLabel: '${section.name}: Sim',
            onTap: () => setState(() => _answers[section.code] = true),
          ),
          _answerButton(
            selected: answer == false,
            isYes: false,
            semanticLabel: '${section.name}: Não',
            onTap: () => setState(() => _answers[section.code] = false),
          ),
        ],
      ),
    );
  }

  Widget _answerButton({
    required bool selected,
    required bool isYes,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    final selectedColor = isYes
        ? const Color(0xFF087B5A)
        : const Color(0xFFC62828);
    return Semantics(
      label: semanticLabel,
      selected: selected,
      button: true,
      child: SizedBox(
        width: 52,
        height: 48,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? selectedColor : Colors.white,
                border: Border.all(
                  color: selected ? selectedColor : const Color(0xFF9AA6BA),
                  width: 2,
                ),
              ),
              child: selected
                  ? Icon(
                      isYes ? Icons.check : Icons.close,
                      color: Colors.white,
                      size: 16,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _supplierLogo({required double size}) => Container(
    width: size,
    height: size,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFFFD98A)),
    ),
    child: Image.asset(
      'assets/coach_mercado/bombril/la_de_aco.webp',
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported_outlined),
    ),
  );

  String _formatPercentage(double value) {
    final rounded = value.roundToDouble();
    return rounded == value
        ? '${rounded.toInt()}%'
        : '${value.toStringAsFixed(1)}%';
  }

  Widget _detail(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: const Color(0xFF71809D)),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );

  String _join(String? first, String? second) {
    final values = [
      first,
      second,
    ].whereType<String>().where((item) => item.trim().isNotEmpty);
    return values.isEmpty
        ? 'Cidade e bairro não informados'
        : values.join(' · ');
  }

  String _newUuid() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

class CoachMarketLocationException implements Exception {
  const CoachMarketLocationException(this.message);

  final String message;
}
