import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/app_user.dart';
import '../models/bi_module.dart';
import '../models/user_module_access.dart';
import '../services/app_repository.dart';
import 'user_module_access_form_screen.dart';

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
  List<AppUser> _users = const <AppUser>[];
  List<BiModule> _modules = const <BiModule>[];
  List<UserModuleAccess> _accesses = const <UserModuleAccess>[];

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
      final users = await _repository.getUsers();
      final modules = await _repository.getBiModules();
      final accesses = await _repository.getUserModuleAccesses();

      if (!mounted) {
        return;
      }

      setState(() {
        _users = users;
        _modules = modules;
        _accesses = accesses;
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

  AppUser? _findUser(String userId) {
    for (final user in _users) {
      if (user.id == userId) {
        return user;
      }
    }
    return null;
  }

  BiModule? _findModule(String moduleId) {
    for (final module in _modules) {
      if (module.id == moduleId) {
        return module;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final visibleAccesses = _accesses.where((access) {
      final user = _findUser(access.userId);
      final module = _findModule(access.moduleId);
      final search = _search.trim().toLowerCase();
      if (search.isEmpty) {
        return true;
      }
      return (user?.code ?? '').toLowerCase().contains(search) ||
          (user?.displayName ?? '').toLowerCase().contains(search) ||
          (module?.name ?? '').toLowerCase().contains(search) ||
          access.filterValues.any(
            (item) => item.filterValue.toLowerCase().contains(search),
          );
    }).toList();

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
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Buscar liberação',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _search = value;
                    });
                  },
                ),
                const SizedBox(height: 20),
                if (visibleAccesses.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Nenhuma liberação encontrada.'),
                    ),
                  )
                else
                  ...visibleAccesses.map((access) {
                    final user = _findUser(access.userId);
                    final module = _findModule(access.moduleId);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFE7EBFF),
                            foregroundColor: primaryColor,
                            child: Icon(Icons.link_outlined),
                          ),
                          title: Text(
                            '${user?.code ?? 'Usuário'} -> ${module?.name ?? 'Módulo'}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            _buildAccessSummary(module, access),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openForm(access),
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }

  String _buildAccessSummary(BiModule? module, UserModuleAccess access) {
    final details = access.filterValues
        .where((item) => item.filterValue.trim().isNotEmpty)
        .map(
          (item) =>
              '${item.moduleFilter?.displayLabel ?? 'Filtro'}: ${item.filterValue}',
        )
        .join(' | ');

    final moduleFilters = module?.filters.map((item) => item.displayLabel).join(
          ' | ',
        ) ??
        '-';

    return 'Campos disponíveis: $moduleFilters\n'
        'Filtrado: ${access.hasFilteredData ? 'Sim' : 'Não'}\n'
        'Valores: ${details.isEmpty ? 'Sem filtros informados' : details}';
  }
}
