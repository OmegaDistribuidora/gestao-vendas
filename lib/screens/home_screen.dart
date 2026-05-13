import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/app_profile.dart';
import '../models/app_user.dart';
import '../models/bi_module.dart';
import '../models/seller_home_kpis.dart';
import '../models/user_module_access.dart';
import '../services/app_repository.dart';
import '../utils/power_bi_url_builder.dart';
import 'admin_screen.dart';
import 'panel_view_screen.dart';
import 'reports_screen.dart';

enum _HomePeriodPreset { today, currentMonth, currentYear, custom }

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

  bool _loading = true;
  String? _errorMessage;
  List<BiModule> _visibleModules = const <BiModule>[];
  SellerHomeKpis _homeKpis = SellerHomeKpis.empty();
  _HomePeriodPreset _selectedPeriod = _HomePeriodPreset.today;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  bool get _isAdmin => widget.currentUser.isAdmin;
  bool get _isSeller => widget.currentUser.profileSlug == AppProfile.sellerSlug;
  bool get _isSupervisor =>
      widget.currentUser.profileSlug == AppProfile.supervisorSlug;
  bool get _isCoordinator =>
      widget.currentUser.profileSlug == AppProfile.coordinatorSlug;
  bool get _showsHomeKpis => !_isAdmin;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  DateTime get _periodStart {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case _HomePeriodPreset.today:
        return DateTime(now.year, now.month, now.day);
      case _HomePeriodPreset.currentMonth:
        return DateTime(now.year, now.month, 1);
      case _HomePeriodPreset.currentYear:
        return DateTime(now.year, 1, 1);
      case _HomePeriodPreset.custom:
        final customStart = _customStartDate ?? now;
        return DateTime(customStart.year, customStart.month, customStart.day);
    }
  }

  DateTime get _periodEnd {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case _HomePeriodPreset.today:
      case _HomePeriodPreset.currentMonth:
      case _HomePeriodPreset.currentYear:
        return DateTime(now.year, now.month, now.day, 23, 59, 59);
      case _HomePeriodPreset.custom:
        final customEnd = _customEndDate ?? _customStartDate ?? now;
        return DateTime(
          customEnd.year,
          customEnd.month,
          customEnd.day,
          23,
          59,
          59,
        );
    }
  }

  String get _periodDescription {
    switch (_selectedPeriod) {
      case _HomePeriodPreset.today:
        return 'Hoje';
      case _HomePeriodPreset.currentMonth:
        return 'Mês atual';
      case _HomePeriodPreset.currentYear:
        return 'Ano atual';
      case _HomePeriodPreset.custom:
        return '${_formatDate(_periodStart)} até ${_formatDate(_periodEnd)}';
    }
  }

  Future<void> _loadContent() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final futures = <Future<dynamic>>[
        _repository.getModulesForUser(widget.currentUser),
      ];

      if (_showsHomeKpis) {
        futures.add(
          _repository.getHomeKpis(start: _periodStart, end: _periodEnd),
        );
      }

      final results = await Future.wait(futures);
      final modules = results[0] as List<BiModule>;
      final homeKpis = _showsHomeKpis && results.length > 1
          ? results[1] as SellerHomeKpis
          : SellerHomeKpis.empty();

      if (!mounted) {
        return;
      }

      setState(() {
        _visibleModules = modules;
        _homeKpis = homeKpis;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage = 'Falha ao carregar os módulos.\n$error';
      });
    }
  }

  Future<void> _pickCustomDate({required bool isStart}) async {
    final initialDate = isStart
        ? (_customStartDate ?? DateTime.now())
        : (_customEndDate ?? _customStartDate ?? DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime.now(),
    );

    if (picked == null) {
      return;
    }

    setState(() {
      if (isStart) {
        _customStartDate = picked;
        if (_customEndDate != null && _customEndDate!.isBefore(picked)) {
          _customEndDate = picked;
        }
      } else {
        _customEndDate = picked;
        if (_customStartDate != null && _customStartDate!.isAfter(picked)) {
          _customStartDate = picked;
        }
      }
    });

    await _loadContent();
  }

  Future<void> _handlePeriodChanged(_HomePeriodPreset? preset) async {
    if (preset == null) {
      return;
    }

    setState(() {
      _selectedPeriod = preset;
      if (preset == _HomePeriodPreset.custom) {
        final today = DateTime.now();
        _customStartDate ??= DateTime(today.year, today.month, today.day);
        _customEndDate ??= _customStartDate;
      }
    });

    await _loadContent();
  }

  Future<void> _openAdministration() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminScreen(currentUser: widget.currentUser),
      ),
    );
    await _loadContent();
  }

  Future<void> _openAdministrationFromDrawer() async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }
    await _openAdministration();
  }

  Future<void> _openModule(BiModule module) async {
    if (module.panelUrl.trim().isEmpty) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este módulo ainda não possui link de painel configurado.',
          ),
        ),
      );
      return;
    }

    var url = module.panelUrl;
    String? filterDescription;

    if (!_isAdmin) {
      final access = await _repository.getAccessForUserModule(
        widget.currentUser.id,
        module.id,
      );

      if (access == null) {
        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Você não possui filtro configurado para este módulo.',
            ),
          ),
        );
        return;
      }

      final filledFilterValues = access.filterValues
          .where((item) => item.filterValue.trim().isNotEmpty)
          .toList();

      if (access.hasFilteredData && filledFilterValues.isNotEmpty) {
        url = PowerBiUrlBuilder.build(module, filledFilterValues);
        filterDescription = filledFilterValues
            .map(
              (item) =>
                  '${item.moduleFilter?.filterTable ?? '-'}'
                  '/${item.moduleFilter?.filterColumn ?? '-'}'
                  ' = ${item.filterValue}',
            )
            .join(' | ');
      } else {
        filterDescription = 'Sem filtro configurado.';
      }
    }

    if (!mounted) {
      return;
    }

    final openedAt = DateTime.now();
    final usageEventId = await _repository.startModuleUsage(
      userId: widget.currentUser.id,
      moduleId: module.id,
    );

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PanelViewScreen(
          title: module.name,
          initialUrl: url,
          filterDescription: filterDescription,
          isAdminView: _isAdmin,
        ),
      ),
    );

    if (usageEventId != null) {
      await _repository.finishModuleUsage(
        usageEventId: usageEventId,
        duration: DateTime.now().difference(openedAt),
      );
    }
  }

  Future<void> _openReports() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportsScreen(currentUser: widget.currentUser),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName =
        widget.currentUser.displayName?.trim().isNotEmpty == true
        ? widget.currentUser.displayName!
        : widget.currentUser.login;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isAdmin ? 'Bem-vindo, $displayName' : 'Gestão de Vendas'),
        actions: [
          IconButton(
            onPressed: _loadContent,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
          IconButton(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                color: primaryColor,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gestão de Vendas',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isAdmin
                          ? 'Administrador'
                          : '${widget.currentUser.login} • ${widget.currentUser.profileName}',
                      style: const TextStyle(color: Color(0xFFD9E0FF)),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Home'),
                onTap: () => Navigator.of(context).pop(),
              ),
              if (_isAdmin)
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: const Text('Administração'),
                  onTap: _openAdministrationFromDrawer,
                ),
              if (_isAdmin)
                ListTile(
                  leading: const Icon(Icons.insights_outlined),
                  title: const Text('Relatórios'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _openReports();
                  },
                ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: _visibleModules.map((module) {
                    return ListTile(
                      leading: const Icon(Icons.bar_chart_outlined),
                      title: Text(module.name),
                      subtitle: const Text('Acompanhamento BI'),
                      onTap: () async {
                        Navigator.of(context).pop();
                        await _openModule(module);
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _buildBody(displayName),
    );
  }

  Widget _buildBody(String displayName) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: primaryColor),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
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
      );
    }

    return RefreshIndicator(
      onRefresh: _loadContent,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Wrap(
                runSpacing: 16,
                spacing: 16,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isAdmin
                              ? 'Painel administrativo'
                              : 'Bem-vindo, $displayName',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isAdmin
                              ? 'Acesse a área administrativa para gerenciar usuários, perfis, módulos e relatórios.'
                              : 'Por favor, selecione um módulo no menu à esquerda para acessar.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF5E6A7C)),
                        ),
                      ],
                    ),
                  ),
                  if (_isAdmin)
                    FilledButton.icon(
                      onPressed: _openAdministration,
                      style: FilledButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Abrir administração'),
                    ),
                ],
              ),
            ),
          ),
          if (_showsHomeKpis) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isSeller || _isSupervisor || _isCoordinator
                          ? 'Seu desempenho no período'
                          : 'Indicadores do período',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _periodDescription,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF5E6A7C),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<_HomePeriodPreset>(
                      initialValue: _selectedPeriod,
                      decoration: const InputDecoration(
                        labelText: 'Período',
                        prefixIcon: Icon(Icons.date_range_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: _HomePeriodPreset.today,
                          child: Text('Hoje'),
                        ),
                        DropdownMenuItem(
                          value: _HomePeriodPreset.currentMonth,
                          child: Text('Mês atual'),
                        ),
                        DropdownMenuItem(
                          value: _HomePeriodPreset.currentYear,
                          child: Text('Ano atual'),
                        ),
                        DropdownMenuItem(
                          value: _HomePeriodPreset.custom,
                          child: Text('Personalizado'),
                        ),
                      ],
                      onChanged: _handlePeriodChanged,
                    ),
                    if (_selectedPeriod == _HomePeriodPreset.custom) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _pickCustomDate(isStart: true),
                            icon: const Icon(Icons.event_outlined),
                            label: Text(_formatDate(_periodStart)),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _pickCustomDate(isStart: false),
                            icon: const Icon(Icons.event_busy_outlined),
                            label: Text(_formatDate(_periodEnd)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 138,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _HomeKpiCard(
                    title: 'Venda',
                    value: _formatCurrency(_homeKpis.totalVenda),
                  ),
                  _HomeKpiCard(
                    title: 'Volume',
                    value: _formatDecimal(_homeKpis.totalVolume),
                  ),
                  _HomeKpiCard(
                    title: 'Pedidos',
                    value: '${_homeKpis.totalPedidos}',
                  ),
                  _HomeKpiCard(
                    title: 'Positivação',
                    value: '${_homeKpis.totalPositivacao}',
                  ),
                ],
              ),
            ),
          ],
          if (_isAdmin) ...[
            const SizedBox(height: 20),
            Text(
              'Módulos cadastrados',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (_visibleModules.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Nenhum módulo disponível no momento.'),
                ),
              )
            else
              ..._visibleModules.map(
                (module) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ModuleCard(
                    module: module,
                    onOpen: () => _openModule(module),
                    currentUser: widget.currentUser,
                    repository: _repository,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _formatCurrency(double value) {
    final fixed = value.toStringAsFixed(2).replaceAll('.', ',');
    return 'R\$ $fixed';
  }

  String _formatDecimal(double value) {
    return value.toStringAsFixed(1).replaceAll('.', ',');
  }

  String _formatDate(DateTime value) {
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.module,
    required this.onOpen,
    required this.currentUser,
    required this.repository,
  });

  final BiModule module;
  final Future<void> Function() onOpen;
  final AppUser currentUser;
  final AppRepository repository;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 10,
        ),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE7EBFF),
          foregroundColor: primaryColor,
          child: const Icon(Icons.bar_chart_outlined),
        ),
        title: Text(
          module.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: FutureBuilder<UserModuleAccess?>(
          future: currentUser.isAdmin
              ? Future<UserModuleAccess?>.value(null)
              : repository.getAccessForUserModule(currentUser.id, module.id),
          builder: (context, snapshot) {
            final lines = <String>[
              'Tipo: Acompanhamento BI',
              'Campos filtráveis: ${module.filters.isEmpty ? 'Nenhum' : module.filters.map((item) => item.displayLabel).join(' | ')}',
              'Status: ${module.isActive ? 'Ativo' : 'Inativo'}',
            ];

            if (currentUser.isAdmin) {
              lines.add('Visão administrativa sem filtro automático.');
            } else if (snapshot.data != null) {
              final values = snapshot.data!.filterValues
                  .where((item) => item.filterValue.trim().isNotEmpty)
                  .map(
                    (item) =>
                        '${item.moduleFilter?.displayLabel ?? 'Filtro'}: ${item.filterValue}',
                  )
                  .join(' | ');
              if (values.isNotEmpty) {
                lines.add('Filtros: $values');
              }
            }

            return Text(lines.join('\n'));
          },
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onOpen,
      ),
    );
  }
}

class _HomeKpiCard extends StatelessWidget {
  const _HomeKpiCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 178,
      margin: const EdgeInsets.only(right: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF5E6A7C),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
