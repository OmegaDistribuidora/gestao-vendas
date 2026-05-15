import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/app_profile.dart';
import '../models/app_user.dart';
import '../services/app_repository.dart';
import 'user_form_screen.dart';

enum _UserStatusFilter { all, active, inactive }

class UsersManagementScreen extends StatefulWidget {
  const UsersManagementScreen({super.key, required this.currentUser});

  final AppUser currentUser;

  @override
  State<UsersManagementScreen> createState() => _UsersManagementScreenState();
}

class _UsersManagementScreenState extends State<UsersManagementScreen> {
  final AppRepository _repository = AppRepository.instance;
  bool _loading = true;
  String? _errorMessage;
  String _search = '';
  String? _selectedProfileId;
  _UserStatusFilter _selectedStatusFilter = _UserStatusFilter.all;
  List<AppProfile> _profiles = const <AppProfile>[];
  List<AppUser> _users = const <AppUser>[];

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
      ]);
      final profiles = results[0] as List<AppProfile>;
      final users = results[1] as List<AppUser>;
      if (!mounted) {
        return;
      }
      setState(() {
        _profiles = profiles;
        _users = users;
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
        _errorMessage = 'Falha ao carregar usuários.\n$error';
      });
    }
  }

  Future<void> _openForm([AppUser? user]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            UserFormScreen(existingUser: user, currentUser: widget.currentUser),
      ),
    );

    if (changed == true) {
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleUsers = _users.where((user) {
      final search = _search.trim().toLowerCase();
      final matchesProfile =
          _selectedProfileId == null || user.profile?.id == _selectedProfileId;
      final matchesStatus = switch (_selectedStatusFilter) {
        _UserStatusFilter.all => true,
        _UserStatusFilter.active => user.isActive,
        _UserStatusFilter.inactive => !user.isActive,
      };

      if (!matchesProfile || !matchesStatus) {
        return false;
      }

      if (search.isEmpty) {
        return true;
      }

      return user.code.toLowerCase().contains(search) ||
          (user.loginAlias ?? '').toLowerCase().contains(search) ||
          (user.displayName ?? '').toLowerCase().contains(search) ||
          user.profileName.toLowerCase().contains(search);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Usuários'),
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
        label: const Text('Novo usuário'),
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
                    labelText: 'Buscar usuário',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _search = value;
                    });
                  },
                ),
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
                const SizedBox(height: 20),
                Text(
                  '${visibleUsers.length} usuário(s) encontrado(s)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF5E6A7C),
                  ),
                ),
                const SizedBox(height: 12),
                if (visibleUsers.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Nenhum usuário encontrado.'),
                    ),
                  )
                else
                  ...visibleUsers.map(
                    (user) => Padding(
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
                            'Status: ${user.isActive ? 'Ativo' : 'Inativo'}'
                            '${user.loginAlias?.trim().isNotEmpty == true ? '\nLogin: ${user.loginAlias}' : ''}'
                            '${user.requiresAdminPasswordDefinition ? '\nSenha pendente de definição pelo admin' : ''}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openForm(user),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
