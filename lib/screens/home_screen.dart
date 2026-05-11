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
  SellerHomeKpis _sellerKpis = SellerHomeKpis.empty();

  bool get _isAdmin => widget.currentUser.isAdmin;
  bool get _isSeller =>
      widget.currentUser.profileSlug == AppProfile.sellerSlug;

  @override
  void initState() {
    super.initState();
    _loadContent();
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

      if (_isSeller) {
        futures.add(_repository.getSellerHomeKpis(widget.currentUser.code));
      }

      final results = await Future.wait(futures);
      final modules = results[0] as List<BiModule>;
      final sellerKpis = _isSeller && results.length > 1
          ? results[1] as SellerHomeKpis
          : SellerHomeKpis.empty();

      if (!mounted) {
        return;
      }

      setState(() {
        _visibleModules = modules;
        _sellerKpis = sellerKpis;
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

    String url = module.panelUrl;
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
                              : 'Por favor selecione um módulo no menu à esquerda para acessar.',
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
          if (_isSeller) ...[
            const SizedBox(height: 20),
            Text(
              'Seu desempenho hoje',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 138,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _SellerKpiCard(
                    title: 'Venda hoje',
                    value: _formatCurrency(_sellerKpis.totalVenda),
                  ),
                  _SellerKpiCard(
                    title: 'Volume hoje',
                    value: _formatDecimal(_sellerKpis.totalVolume),
                  ),
                  _SellerKpiCard(
                    title: 'Pedidos hoje',
                    value: '${_sellerKpis.totalPedidos}',
                  ),
                  _SellerKpiCard(
                    title: 'Positivação hoje',
                    value: '${_sellerKpis.totalPositivacao}',
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

class _SellerKpiCard extends StatelessWidget {
  const _SellerKpiCard({
    required this.title,
    required this.value,
  });

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
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
