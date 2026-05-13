import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/app_profile.dart';
import '../models/app_user.dart';
import '../models/bi_module.dart';
import '../models/user_module_access_input.dart';
import '../services/app_repository.dart';

class UserFormScreen extends StatefulWidget {
  const UserFormScreen({
    super.key,
    this.existingUser,
    required this.currentUser,
  });

  final AppUser? existingUser;
  final AppUser currentUser;

  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  final AppRepository _repository = AppRepository.instance;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _codeController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _loginAliasController;
  late final TextEditingController _passwordController;

  bool _hidePassword = true;
  bool _loading = true;
  bool _saving = false;
  bool _deleting = false;
  String? _errorMessage;
  List<AppProfile> _profiles = const <AppProfile>[];
  List<BiModule> _modules = const <BiModule>[];
  String? _selectedProfileId;
  bool _isActive = true;

  bool get _editing => widget.existingUser != null;

  AppProfile? get _selectedProfile {
    if (_selectedProfileId == null) {
      return null;
    }
    for (final profile in _profiles) {
      if (profile.id == _selectedProfileId) {
        return profile;
      }
    }
    return null;
  }

  bool get _isSellerProfile => _selectedProfile?.slug == AppProfile.sellerSlug;
  bool get _isSupervisorProfile =>
      _selectedProfile?.slug == AppProfile.supervisorSlug;
  bool get _isCoordinatorProfile =>
      _selectedProfile?.slug == AppProfile.coordinatorSlug;
  bool get _isAdminProfile => _selectedProfile?.slug == AppProfile.adminSlug;
  bool get _isOracleManagedProfile =>
      _isSellerProfile || _isSupervisorProfile || _isCoordinatorProfile;
  bool get _isCodeBasedProfile => _isOracleManagedProfile;
  bool get _requiresLoginAlias =>
      _isAdminProfile || (!_isCodeBasedProfile && !_isSellerProfile);
  bool get _showsLoginAliasField => !_isSellerProfile;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(
      text: widget.existingUser?.code ?? '',
    );
    _displayNameController = TextEditingController(
      text: widget.existingUser?.displayName ?? '',
    );
    _loginAliasController = TextEditingController(
      text: widget.existingUser?.loginAlias ?? '',
    );
    _passwordController = TextEditingController();
    _isActive = widget.existingUser?.isActive ?? true;
    _loadInitialData();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _displayNameController.dispose();
    _loginAliasController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _repository.getProfiles(),
        _repository.getBiModules(),
      ]);

      if (!mounted) {
        return;
      }

      final profiles = results[0] as List<AppProfile>;
      final modules = results[1] as List<BiModule>;

      setState(() {
        _profiles = profiles;
        _modules = modules;
        _selectedProfileId =
            widget.existingUser?.profile?.id ??
            (profiles.isEmpty ? null : profiles.first.id);
        if (_isAdminProfile && _loginAliasController.text.trim().isEmpty) {
          _loginAliasController.text = 'admin';
        }
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
        _errorMessage =
            'Não foi possível carregar os dados do usuário.\n$error';
      });
    }
  }

  String _buildProfileLoginHelpText() {
    if (_isSellerProfile) {
      return 'Vendedores entram exclusivamente com código e senha. A senha inicial é gerada a partir dos 3 primeiros dígitos do CPF e o cadastro é mantido pelo script automático do Oracle.';
    }
    if (_isSupervisorProfile) {
      return 'Supervisores entram pelo primeiro nome, ignorando maiúsculas e minúsculas, com a senha definida pelo administrador. Se o nome mudar no Oracle, o login fica bloqueado até nova definição de senha.';
    }
    if (_isCoordinatorProfile) {
      return 'Coordenadores entram pelo primeiro nome ou por um login alternativo. Se o nome mudar no Oracle, o login fica bloqueado até nova definição de senha.';
    }
    if (_isAdminProfile) {
      return 'O administrador sempre entra com o login "admin". A senha inicial é Omega@123, mas pode ser alterada.';
    }
    return 'Usuários deste perfil entram com o login definido pelo administrador e a senha cadastrada no momento da criação.';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedProfileId == null) {
      _showMessage('Selecione um perfil.');
      return;
    }

    if (_isCodeBasedProfile && _codeController.text.trim().isEmpty) {
      _showMessage('Informe o código para este perfil.');
      return;
    }

    if (_requiresLoginAlias && _loginAliasController.text.trim().isEmpty) {
      _showMessage('Informe o login para este perfil.');
      return;
    }

    if (!_editing && _isOracleManagedProfile) {
      _showMessage(
        'Usuários de vendedor, supervisor e coordenador devem ser cadastrados pelo script automático do Oracle.',
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final loginAlias = _isAdminProfile
          ? 'admin'
          : _loginAliasController.text.trim();

      if (_editing) {
        await _repository.updateUser(
          userId: widget.existingUser!.id,
          code: _codeController.text.trim(),
          displayName: _displayNameController.text.trim(),
          loginAlias: loginAlias,
          profileId: _selectedProfileId!,
          isActive: _isActive,
          newPassword: _passwordController.text.trim(),
        );
      } else {
        final createdUser = await _repository.createUser(
          code: _codeController.text.trim(),
          password: _passwordController.text.trim(),
          displayName: _displayNameController.text.trim(),
          loginAlias: loginAlias,
          profileId: _selectedProfileId!,
          isActive: _isActive,
        );

        if (!mounted) {
          return;
        }

        final initialAccesses = await _showInitialModulesDialog(createdUser);
        if (initialAccesses != null) {
          await _repository.replaceUserModuleAccesses(
            userId: createdUser.id,
            accesses: initialAccesses,
          );
        }
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } on RepositoryException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage('Não foi possível salvar o usuário.\n$error');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<List<UserModuleAccessInput>?> _showInitialModulesDialog(AppUser user) {
    if (_modules.isEmpty) {
      return Future<List<UserModuleAccessInput>?>.value(
        const <UserModuleAccessInput>[],
      );
    }

    return showDialog<List<UserModuleAccessInput>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InitialModuleAccessDialog(user: user, modules: _modules),
    );
  }

  Future<void> _delete() async {
    final user = widget.existingUser;
    if (user == null) {
      return;
    }
    if (user.id == widget.currentUser.id) {
      _showMessage('Não exclua o usuário logado.');
      return;
    }

    setState(() {
      _deleting = true;
    });

    try {
      await _repository.deleteUser(user.id);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on RepositoryException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage('Não foi possível excluir o usuário.\n$error');
    } finally {
      if (mounted) {
        setState(() {
          _deleting = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Editar usuário' : 'Novo usuário'),
        actions: [
          if (_editing)
            IconButton(
              onPressed: _saving || _deleting ? null : _delete,
              icon: _deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.delete_outline),
              tooltip: 'Excluir usuário',
            ),
        ],
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
          : SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_isCodeBasedProfile) ...[
                                TextFormField(
                                  controller: _codeController,
                                  readOnly: _editing && _isOracleManagedProfile,
                                  decoration: const InputDecoration(
                                    labelText: 'Código',
                                    prefixIcon: Icon(Icons.pin_outlined),
                                  ),
                                  validator: (value) {
                                    if (_isCodeBasedProfile &&
                                        (value == null ||
                                            value.trim().isEmpty)) {
                                      return 'Informe o código.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                              ],
                              TextFormField(
                                controller: _displayNameController,
                                decoration: const InputDecoration(
                                  labelText: 'Nome de exibição',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                                validator: (value) {
                                  if (!_isSellerProfile &&
                                      (value == null || value.trim().isEmpty)) {
                                    return 'Informe o nome de exibição para este perfil.';
                                  }
                                  return null;
                                },
                              ),
                              if (_showsLoginAliasField) ...[
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _loginAliasController,
                                  readOnly: _isAdminProfile,
                                  decoration: InputDecoration(
                                    labelText: _isCoordinatorProfile
                                        ? 'Login alternativo (opcional)'
                                        : _requiresLoginAlias
                                        ? 'Login'
                                        : 'Login personalizado (opcional)',
                                    prefixIcon: const Icon(
                                      Icons.alternate_email_outlined,
                                    ),
                                    helperText: _isAdminProfile
                                        ? 'O login do administrador é sempre "admin".'
                                        : _isCoordinatorProfile
                                        ? 'Se preenchido, terá prioridade sobre o primeiro nome.'
                                        : _requiresLoginAlias
                                        ? 'Este será o login usado por este usuário.'
                                        : 'Se preenchido, terá prioridade sobre o nome.',
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedProfileId,
                                items: _profiles.map((profile) {
                                  return DropdownMenuItem<String>(
                                    value: profile.id,
                                    child: Text(profile.name),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedProfileId = value;
                                    if (_isAdminProfile) {
                                      _loginAliasController.text = 'admin';
                                    }
                                  });
                                },
                                decoration: const InputDecoration(
                                  labelText: 'Perfil',
                                  prefixIcon: Icon(Icons.account_tree_outlined),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _hidePassword,
                                decoration: InputDecoration(
                                  labelText: _editing
                                      ? 'Nova senha (opcional)'
                                      : 'Senha',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _hidePassword = !_hidePassword;
                                      });
                                    },
                                    icon: Icon(
                                      _hidePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                                validator: (value) {
                                  if (!_editing &&
                                      (value == null || value.trim().isEmpty)) {
                                    return 'Informe a senha.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              SwitchListTile(
                                value: _isActive,
                                onChanged: (value) {
                                  setState(() {
                                    _isActive = value;
                                  });
                                },
                                contentPadding: EdgeInsets.zero,
                                activeThumbColor: primaryColor,
                                title: const Text('Usuário ativo'),
                              ),
                              const SizedBox(height: 12),
                              Card(
                                color: const Color(0xFFF7F8FC),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(_buildProfileLoginHelpText()),
                                ),
                              ),
                              if (_editing &&
                                  widget
                                          .existingUser
                                          ?.requiresAdminPasswordDefinition ==
                                      true) ...[
                                const SizedBox(height: 12),
                                Card(
                                  color: const Color(0xFFFFF4E5),
                                  child: const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text(
                                      'Este usuário está bloqueado para login até que uma senha seja definida pelo administrador.',
                                    ),
                                  ),
                                ),
                              ],
                              if (!_editing) ...[
                                const SizedBox(height: 12),
                                Card(
                                  color: const Color(0xFFF7F8FC),
                                  child: const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text(
                                      'Depois de salvar, será exibido um pop-up para liberar os módulos BI iniciais do usuário.',
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: _saving ? null : _save,
                                style: FilledButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                ),
                                child: _saving
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Salvar'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _InitialModuleAccessDialog extends StatefulWidget {
  const _InitialModuleAccessDialog({required this.user, required this.modules});

  final AppUser user;
  final List<BiModule> modules;

  @override
  State<_InitialModuleAccessDialog> createState() =>
      _InitialModuleAccessDialogState();
}

class _InitialModuleAccessDialogState
    extends State<_InitialModuleAccessDialog> {
  late final List<_ModuleAccessDraft> _drafts;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _drafts = widget.modules.map(_ModuleAccessDraft.new).toList();
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _confirm() {
    final accesses = <UserModuleAccessInput>[];

    for (final draft in _drafts) {
      if (!draft.enabled) {
        continue;
      }

      final values = draft.buildFilterValues();
      if (draft.hasFilteredData &&
          draft.module.filters.isNotEmpty &&
          values.isEmpty) {
        setState(() {
          _errorMessage =
              'Preencha pelo menos um valor para os módulos marcados com dados filtrados.';
        });
        return;
      }

      accesses.add(
        UserModuleAccessInput(
          moduleId: draft.module.id,
          hasFilteredData: draft.hasFilteredData && values.isNotEmpty,
          filterValues: values,
        ),
      );
    }

    Navigator.of(context).pop(accesses);
  }

  @override
  Widget build(BuildContext context) {
    final userLabel = widget.user.displayName?.trim().isNotEmpty == true
        ? widget.user.displayName!
        : widget.user.label;

    return AlertDialog(
      title: const Text('Liberar módulos iniciais'),
      content: SizedBox(
        width: 720,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Selecione os módulos BI que deseja liberar inicialmente para $userLabel.',
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 420,
              child: SingleChildScrollView(
                child: Column(children: _drafts.map(_buildModuleCard).toList()),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(const <UserModuleAccessInput>[]);
          },
          child: const Text('Pular por agora'),
        ),
        FilledButton(
          onPressed: _confirm,
          style: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
          ),
          child: const Text('Salvar liberações'),
        ),
      ],
    );
  }

  Widget _buildModuleCard(_ModuleAccessDraft draft) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: const Color(0xFFF7F8FC),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              CheckboxListTile(
                value: draft.enabled,
                onChanged: (value) {
                  setState(() {
                    draft.enabled = value ?? false;
                    if (!draft.enabled) {
                      draft.hasFilteredData = false;
                      draft.clearFilters();
                    }
                    _errorMessage = null;
                  });
                },
                activeColor: primaryColor,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  draft.module.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  draft.module.filters.isEmpty
                      ? 'Sem campos filtráveis cadastrados.'
                      : '${draft.module.filters.length} campo(s) filtrável(is) disponível(is).',
                ),
              ),
              if (draft.enabled && draft.module.filters.isNotEmpty)
                SwitchListTile(
                  value: draft.hasFilteredData,
                  onChanged: (value) {
                    setState(() {
                      draft.hasFilteredData = value;
                      if (!value) {
                        draft.clearFilters();
                      }
                      _errorMessage = null;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: primaryColor,
                  title: const Text('Liberar com dados filtrados'),
                ),
              if (draft.enabled &&
                  draft.hasFilteredData &&
                  draft.module.filters.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...draft.module.filters.map((filter) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: draft.controllers[filter.id],
                      decoration: InputDecoration(
                        labelText: filter.displayLabel,
                        helperText:
                            '${filter.filterTable} / ${filter.filterColumn}',
                        prefixIcon: const Icon(Icons.filter_alt_outlined),
                      ),
                      onChanged: (_) {
                        if (_errorMessage != null) {
                          setState(() {
                            _errorMessage = null;
                          });
                        }
                      },
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Você pode preencher apenas os filtros necessários.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ModuleAccessDraft {
  _ModuleAccessDraft(this.module)
    : controllers = <String, TextEditingController>{
        for (final filter in module.filters) filter.id: TextEditingController(),
      };

  final BiModule module;
  final Map<String, TextEditingController> controllers;
  bool enabled = false;
  bool hasFilteredData = false;

  Map<String, String> buildFilterValues() {
    return <String, String>{
      for (final entry in controllers.entries)
        if (entry.value.text.trim().isNotEmpty)
          entry.key: entry.value.text.trim(),
    };
  }

  void clearFilters() {
    for (final controller in controllers.values) {
      controller.clear();
    }
  }

  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }
}
