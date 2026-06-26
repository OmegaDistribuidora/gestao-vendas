import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_theme.dart';
import '../models/recovered_customer_opportunities.dart';
import '../services/app_repository.dart';

class RecoveredCustomersScreen extends StatefulWidget {
  const RecoveredCustomersScreen({super.key});

  @override
  State<RecoveredCustomersScreen> createState() =>
      _RecoveredCustomersScreenState();
}

class _RecoveredCustomersScreenState extends State<RecoveredCustomersScreen> {
  final AppRepository _repository = AppRepository.instance;
  final TextEditingController _searchController = TextEditingController();
  final DateFormat _dateTimeFormat = DateFormat(
    "dd/MM/yyyy 'as' HH:mm",
    'pt_BR',
  );

  RecoveredCustomerOpportunitiesOverview _overview =
      RecoveredCustomerOpportunitiesOverview.empty();
  bool _loading = true;
  String? _errorMessage;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final overview = await _repository.getRecoveredCustomerOpportunities(
        search: _searchController.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _overview = overview;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage =
            'Nao foi possivel carregar clientes recuperados.\n$error';
      });
    }
  }

  void _handleSearchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _loadData);
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

  Widget _buildSummaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7F5EF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.how_to_reg_outlined,
                    color: Color(0xFF087B5A),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_overview.totalRecovered} clientes recuperados',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Clientes que sairam do mapa por cadastro no WinThor.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF647084),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_overview.lastUpdatedAt != null) ...[
              const SizedBox(height: 12),
              Text(
                'Ultima verificacao: '
                '${_dateTimeFormat.format(_overview.lastUpdatedAt!)}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFF5E6A7C),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: _handleSearchChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_outlined),
        hintText: 'Buscar por cliente, CNPJ, cidade, bairro ou atividade',
        suffixIcon: _searchController.text.trim().isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpar busca',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _searchController.clear();
                  setState(() {});
                  _loadData();
                },
              ),
      ),
    );
  }

  Widget _buildCustomerCard(RecoveredCustomerOpportunity customer) {
    final secondaryName = customer.secondaryName;
    final recoveredAt = customer.recoveredAt == null
        ? 'Data nao informada'
        : _dateTimeFormat.format(customer.recoveredAt!);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7EBFF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.storefront_outlined,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.displayName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (secondaryName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          secondaryName,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF647084)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.badge_outlined,
                  label: _formatTaxId(customer.taxId),
                ),
                if (customer.cityLabel.isNotEmpty)
                  _InfoChip(
                    icon: Icons.location_city_outlined,
                    label: customer.cityLabel,
                  ),
                if (customer.district.isNotEmpty)
                  _InfoChip(
                    icon: Icons.holiday_village_outlined,
                    label: customer.district,
                  ),
                _InfoChip(
                  icon: Icons.event_available_outlined,
                  label: 'Recuperado em $recoveredAt',
                ),
              ],
            ),
            if (customer.fullAddress.isNotEmpty) ...[
              const SizedBox(height: 12),
              _InlineInfo(
                icon: Icons.signpost_outlined,
                text: customer.fullAddress,
              ),
            ],
            if (customer.activityLabel.isNotEmpty) ...[
              const SizedBox(height: 8),
              _InlineInfo(
                icon: Icons.category_outlined,
                text: customer.activityLabel,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_overview.customers.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          _buildSummaryCard(),
          const SizedBox(height: 14),
          _buildSearchField(),
          const SizedBox(height: 36),
          const _EmptyState(),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: primaryColor,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          _buildSummaryCard(),
          const SizedBox(height: 14),
          _buildSearchField(),
          const SizedBox(height: 14),
          ..._overview.customers.map(_buildCustomerCard),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes Recuperados'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadData,
            icon: const Icon(Icons.refresh_rounded),
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
            ? _ErrorState(message: _errorMessage!, onRetry: _loadData)
            : _buildContent(),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16, color: primaryColor),
      label: Text(label),
      visualDensity: VisualDensity.compact,
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: primaryColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF465267),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.inbox_outlined, size: 54, color: Color(0xFF7B8798)),
        const SizedBox(height: 12),
        Text(
          'Nenhum cliente recuperado ainda',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Quando uma oportunidade for cadastrada no WinThor, ela aparecera aqui.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF647084)),
        ),
      ],
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
              Icons.error_outline_rounded,
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
