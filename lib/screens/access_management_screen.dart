import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/app_profile.dart';
import '../models/app_user.dart';
import '../models/bi_module.dart';
import '../models/user_module_access.dart';
import '../services/app_repository.dart';
import 'user_module_access_form_screen.dart';

enum _AccessViewMode { byModule, byUser }

enum _UserStatusFilter { all, active, inactive }

class AccessManagementScreen extends StatefulWidget {
  const AccessManagementScreen({super.key});

  @override
  State<AccessManagementScreen> createState() => _AccessManagementScreenState();
}

class _AccessManagementScreenState extends State<AccessManagementScreen> {
  final AppRepository _repository = AppRepository.instance;
  bool _loading = true;
  String? _errorMessage;
  String _search = '';
  _AccessViewMode _viewMode = _AccessViewMode.byModule;
  String? _selectedProfileId;
  _UserStatusFilter _selectedStatusFilter = _UserStatusFilter.all;
  List<AppUser> _users = const <AppUser>[];
  List<BiModule> _modules = const <BiModule>[];
  List<UserModuleAccess> _accesses = const <UserModuleAccess>[];
  List<AppProfile> _profiles = const <AppProfile>[];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait<dynamic>([
        _repository.getProfiles(),
        _repository.getUsers(),
        _repository.getBiModules(),
        _repository.getUserModuleAccesses(),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _profiles = results[0] as List<AppProfile>;
        _users = results[1] as List<AppUser>;
        _modules = results[2] as List<BiModule>;
        _accesses = results[3] as List<UserModuleAccess>;
        _loading = false;
      });
    } on RepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = 'Falha ao carregar liberações.\n$error';
      });
    }
  }

  Future<void> _openForm([UserModuleAccess? access]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => UserModuleAccessFormScreen(existingAccess: access),
      ),
    );

    if (changed == true) {
      await _loadData();
    }
  }

  bool _matchesUserFilters(AppUser user) {
    final matchesProfile =
        _selectedProfileId == null || user.profile?.id == _selectedProfileId;
    final matchesStatus = switch (_selectedStatusFilter) {
      _UserStatusFilter.all => true,
      _UserStatusFilter.active => user.isActive,
      _UserStatusFilter.inactive => !user.isActive,
    };
    return matchesProfile && matchesStatus;
  }

  List<BiModule> get _visibleModules {
    final search = _search.trim().toLowerCase();
    return _modules.where((module) {
      if (search.isEmpty) {
        return true;
      }
      return module.name.toLowerCase().contains(search) ||
          module.filters.any(
            (filter) => filter.displayLabel.toLowerCase().contains(search),
          );
    }).toList();
  }

  List<AppUser> get _visibleUsers {
    final search = _search.trim().toLowerCase();
    return _users.where((user) {
      if (!_matchesUserFilters(user)) {
        return false;
      }
      if (search.isEmpty) {
        return true;
      }
      return user.code.toLowerCase().contains(search) ||
          (user.displayName ?? '').toLowerCase().contains(search) ||
          (user.loginAlias ?? '').toLowerCase().contains(search) ||
          user.profileName.toLowerCase().contains(search);
    }).toList();
  }

  List<UserModuleAccess> _accessesForModule(String moduleId) {
    return _accesses.where((access) => access.moduleId == moduleId).toList();
  }

  List<UserModuleAccess> _accessesForUser(String userId) {
    return _accesses.where((access) => access.userId == userId).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Liberações de módulos'),
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nova liberação'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: primaryColor))
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_errorMessage!, textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                SegmentedButton<_AccessViewMode>(
                  segments: const [
                    ButtonSegment(
                      value: _AccessViewMode.byModule,
                      icon: Icon(Icons.view_module_outlined),
                      label: Text('Por módulo'),
                    ),
                    ButtonSegment(
                      value: _AccessViewMode.byUser,
                      icon: Icon(Icons.people_outline),
                      label: Text('Por usuário'),
                    ),
                  ],
                  selected: <_AccessViewMode>{_viewMode},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _viewMode = selection.first;
                    });
                  },
                ),
                const SizedBox(height: 20),
                TextField(
                  decoration: InputDecoration(
                    labelText: _viewMode == _AccessViewMode.byModule
                        ? 'Buscar módulo'
                        : 'Buscar usuário',
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _search = value;
                    });
                  },
                ),
                if (_viewMode == _AccessViewMode.byUser) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    key: ValueKey<String?>(_selectedProfileId),
                    initialValue: _selectedProfileId,
                    decoration: const InputDecoration(
                      labelText: 'Filtrar por perfil',
                      prefixIcon: Icon(Icons.filter_list_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Todos os perfis'),
                      ),
                      ..._profiles.map(
                        (profile) => DropdownMenuItem<String?>(
                          value: profile.id,
                          child: Text(profile.name),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedProfileId = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<_UserStatusFilter>(
                    key: ValueKey<_UserStatusFilter>(_selectedStatusFilter),
                    initialValue: _selectedStatusFilter,
                    decoration: const InputDecoration(
                      labelText: 'Filtrar por status',
                      prefixIcon: Icon(Icons.toggle_on_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: _UserStatusFilter.all,
                        child: Text('Todos'),
                      ),
                      DropdownMenuItem(
                        value: _UserStatusFilter.active,
                        child: Text('Ativos'),
                      ),
                      DropdownMenuItem(
                        value: _UserStatusFilter.inactive,
                        child: Text('Inativos'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _selectedStatusFilter = value;
                      });
                    },
                  ),
                ],
                const SizedBox(height: 20),
                if (_viewMode == _AccessViewMode.byModule)
                  _buildModulesView(context)
                else
                  _buildUsersView(context),
              ],
            ),
    );
  }

  Widget _buildModulesView(BuildContext context) {
    final modules = _visibleModules;
    if (modules.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Nenhum módulo encontrado.'),
        ),
      );
    }

    return Column(
      children: modules.map((module) {
        final accessCount = _accessesForModule(module.id).length;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE7EBFF),
                foregroundColor: primaryColor,
                child: Icon(Icons.view_module_outlined),
              ),
              title: Text(
                module.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '$accessCount usuário(s) com acesso\n'
                'Campos filtráveis: ${module.filters.isEmpty ? 'Nenhum' : module.filters.map((item) => item.displayLabel).join(' | ')}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _ModuleAccessDetailScreen(
                      module: module,
                      accesses: _accessesForModule(module.id),
                      users: _users,
                      onEditAccess: _openForm,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildUsersView(BuildContext context) {
    final users = _visibleUsers;
    if (users.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Nenhum usuário encontrado.'),
        ),
      );
    }

    return Column(
      children: users.map((user) {
        final accessCount = _accessesForUser(user.id).length;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFE7EBFF),
                foregroundColor: primaryColor,
                child: Icon(
                  user.isAdmin
                      ? Icons.admin_panel_settings_outlined
                      : Icons.person_outline,
                ),
              ),
              title: Text(
                user.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Perfil: ${user.profileName}\n'
                'Status: ${user.isActive ? 'Ativo' : 'Inativo'}\n'
                '$accessCount módulo(s) liberado(s)',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _UserAccessDetailScreen(
                      user: user,
                      accesses: _accessesForUser(user.id),
                      modules: _modules,
                      onEditAccess: _openForm,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ModuleAccessDetailScreen extends StatelessWidget {
  const _ModuleAccessDetailScreen({
    required this.module,
    required this.accesses,
    required this.users,
    required this.onEditAccess,
  });

  final BiModule module;
  final List<UserModuleAccess> accesses;
  final List<AppUser> users;
  final Future<void> Function([UserModuleAccess? access]) onEditAccess;

  AppUser? _findUser(String userId) {
    for (final user in users) {
      if (user.id == userId) {
        return user;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton(), title: Text(module.name)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Campos filtráveis: ${module.filters.isEmpty ? 'Nenhum' : module.filters.map((item) => item.displayLabel).join(' | ')}',
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (accesses.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('Nenhum usuário possui acesso a este módulo.'),
              ),
            )
          else
            ...accesses.map((access) {
              final user = _findUser(access.userId);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: ListTile(
                    title: Text(
                      user?.label ?? 'Usuário',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'Perfil: ${user?.profileName ?? 'Sem perfil'}\n'
                      'Filtrado: ${access.hasFilteredData ? 'Sim' : 'Não'}\n'
                      'Valores: ${_buildFilterValueSummary(access)}',
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () async {
                      await onEditAccess(access);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _UserAccessDetailScreen extends StatelessWidget {
  const _UserAccessDetailScreen({
    required this.user,
    required this.accesses,
    required this.modules,
    required this.onEditAccess,
  });

  final AppUser user;
  final List<UserModuleAccess> accesses;
  final List<BiModule> modules;
  final Future<void> Function([UserModuleAccess? access]) onEditAccess;

  BiModule? _findModule(String moduleId) {
    for (final module in modules) {
      if (module.id == moduleId) {
        return module;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton(), title: Text(user.label)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: ListTile(
              title: Text(user.profileName),
              subtitle: Text(user.isActive ? 'Ativo' : 'Inativo'),
            ),
          ),
          const SizedBox(height: 16),
          if (accesses.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('Este usuário não possui módulos liberados.'),
              ),
            )
          else
            ...accesses.map((access) {
              final module = _findModule(access.moduleId);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: ListTile(
                    title: Text(
                      module?.name ?? 'Módulo',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'Campos disponíveis: ${module == null || module.filters.isEmpty ? 'Nenhum' : module.filters.map((item) => item.displayLabel).join(' | ')}\n'
                      'Filtrado: ${access.hasFilteredData ? 'Sim' : 'Não'}\n'
                      'Valores: ${_buildFilterValueSummary(access)}',
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () async {
                      await onEditAccess(access);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

String _buildFilterValueSummary(UserModuleAccess access) {
  final details = access.filterValues
      .where((item) => item.filterValue.trim().isNotEmpty)
      .map(
        (item) =>
            '${item.moduleFilter?.displayLabel ?? 'Filtro'}: ${item.filterValue}',
      )
      .join(' | ');

  if (details.isEmpty) {
    return access.hasFilteredData
        ? 'Sem filtros informados'
        : 'Sem filtragem configurada';
  }

  return details;
}
