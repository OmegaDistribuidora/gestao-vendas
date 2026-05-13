import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/app_profile.dart';
import '../models/app_user.dart';
import '../models/bi_module.dart';
import '../models/bi_module_filter.dart';
import '../models/bi_module_filter_input.dart';
import '../models/user_module_access.dart';
import '../services/app_repository.dart';

class BiModuleFormScreen extends StatefulWidget {
  const BiModuleFormScreen({super.key, this.existingModule});

  final BiModule? existingModule;

  @override
  State<BiModuleFormScreen> createState() => _BiModuleFormScreenState();
}

class _BiModuleFormScreenState extends State<BiModuleFormScreen> {
  final AppRepository _repository = AppRepository.instance;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late List<_FilterDraft> _filters;
  List<AppProfile> _profiles = const <AppProfile>[];
  List<AppUser> _users = const <AppUser>[];
  Set<String> _selectedProfileIds = <String>{};
  Set<String> _selectedUserIds = <String>{};
  String? _selectedSellerDefaultDraftKey;
  bool _loading = true;
  bool _isActive = true;
  bool _saving = false;
  bool _deleting = false;
  String? _errorMessage;

  bool get _editing => widget.existingModule != null;

  AppProfile? get _sellerProfile {
    for (final profile in _profiles) {
      if (profile.slug == AppProfile.sellerSlug) {
        return profile;
      }
    }
    return null;
  }

  bool get _sellerProfileSelected =>
      _sellerProfile != null &&
      _selectedProfileIds.contains(_sellerProfile!.id);

  List<_FilterDraft> get _validFilterDrafts => _filters
      .where(
        (draft) =>
            draft.tableController.text.trim().isNotEmpty &&
            draft.columnController.text.trim().isNotEmpty,
      )
      .toList();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existingModule?.name ?? '',
    );
    _urlController = TextEditingController(
      text: widget.existingModule?.panelUrl ?? '',
    );
    _filters = widget.existingModule?.filters.isNotEmpty == true
        ? widget.existingModule!.filters
              .map((filter) => _FilterDraft.fromFilter(filter))
              .toList()
        : <_FilterDraft>[_FilterDraft()];
    _isActive = widget.existingModule?.isActive ?? true;
    _loadInitialData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    for (final filter in _filters) {
      filter.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final futures = <Future<dynamic>>[
        _repository.getProfiles(),
        _repository.getUsers(),
      ];
      if (_editing) {
        futures.add(
          _repository.getUserModuleAccessesForModule(widget.existingModule!.id),
        );
      }

      final results = await Future.wait(futures);
      final profiles = (results[0] as List<AppProfile>)
          .where((profile) => !profile.isAdmin)
          .toList();
      final users = (results[1] as List<AppUser>)
          .where((user) => !user.isAdmin)
          .toList();
      final accesses = _editing
          ? results[2] as List<UserModuleAccess>
          : const <UserModuleAccess>[];

      final selectedUserIds = accesses.map((item) => item.userId).toSet();
      final selectedProfileIds = <String>{};
      for (final user in users) {
        if (selectedUserIds.contains(user.id) && user.profile != null) {
          selectedProfileIds.add(user.profile!.id);
        }
      }

      String? selectedSellerDefaultDraftKey;
      final sellerDefaultFilterId =
          widget.existingModule?.sellerDefaultFilterId;
      if (sellerDefaultFilterId != null) {
        for (final draft in _filters) {
          if (draft.id == sellerDefaultFilterId) {
            selectedSellerDefaultDraftKey = draft.draftKey;
            break;
          }
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _profiles = profiles;
        _users = users;
        _selectedProfileIds = selectedProfileIds;
        _selectedUserIds = selectedUserIds;
        _selectedSellerDefaultDraftKey = selectedSellerDefaultDraftKey;
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
        _errorMessage = 'Não foi possível carregar os dados do módulo.\n$error';
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final filterInputs = _filters
        .map(
          (draft) => BiModuleFilterInput(
            id: draft.id,
            filterTable: draft.tableController.text.trim(),
            filterColumn: draft.columnController.text.trim(),
            label: draft.labelController.text.trim(),
          ),
        )
        .where(
          (item) => item.filterTable.isNotEmpty && item.filterColumn.isNotEmpty,
        )
        .toList();

    if (_sellerProfileSelected &&
        filterInputs.isNotEmpty &&
        (_selectedSellerDefaultDraftKey == null ||
            _selectedSellerDefaultDraftKey!.trim().isEmpty)) {
      _showMessage(
        'Selecione qual campo filtrável será aplicado por padrão aos vendedores.',
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final savedModule = _editing
          ? await _repository.updateBiModule(
              moduleId: widget.existingModule!.id,
              name: _nameController.text.trim(),
              panelUrl: _urlController.text.trim(),
              filters: filterInputs,
              isActive: _isActive,
            )
          : await _repository.createBiModule(
              name: _nameController.text.trim(),
              panelUrl: _urlController.text.trim(),
              filters: filterInputs,
              isActive: _isActive,
            );

      final sellerDefaultFilterId = _resolveSavedSellerDefaultFilterId(
        savedModule.filters,
      );

      await _repository.setModuleSellerDefaultFilter(
        moduleId: savedModule.id,
        sellerDefaultFilterId: sellerDefaultFilterId,
      );

      final allowedUsers = _users
          .where((user) => _selectedUserIds.contains(user.id))
          .toList();
      await _repository.syncModuleAllowedUsers(
        moduleId: savedModule.id,
        allowedUsers: allowedUsers,
        sellerDefaultFilterId: sellerDefaultFilterId,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } on RepositoryException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage('Não foi possível salvar o módulo.\n$error');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String? _resolveSavedSellerDefaultFilterId(
    List<BiModuleFilter> savedFilters,
  ) {
    if (!_sellerProfileSelected ||
        _selectedSellerDefaultDraftKey == null ||
        _selectedSellerDefaultDraftKey!.trim().isEmpty) {
      return null;
    }

    final validDrafts = _validFilterDrafts;
    final draftIndex = validDrafts.indexWhere(
      (item) => item.draftKey == _selectedSellerDefaultDraftKey,
    );
    if (draftIndex < 0 || draftIndex >= savedFilters.length) {
      return null;
    }

    return savedFilters[draftIndex].id;
  }

  Future<void> _delete() async {
    final module = widget.existingModule;
    if (module == null) {
      return;
    }

    setState(() {
      _deleting = true;
    });

    try {
      await _repository.deleteBiModule(module.id);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on RepositoryException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage('Não foi possível excluir o módulo.\n$error');
    } finally {
      if (mounted) {
        setState(() {
          _deleting = false;
        });
      }
    }
  }

  void _addFilter() {
    setState(() {
      _filters = [..._filters, _FilterDraft()];
    });
  }

  void _removeFilter(int index) {
    if (_filters.length == 1) {
      return;
    }
    final item = _filters[index];
    final removedWasSelected = item.draftKey == _selectedSellerDefaultDraftKey;
    item.dispose();
    setState(() {
      _filters = [..._filters]..removeAt(index);
      if (removedWasSelected) {
        _selectedSellerDefaultDraftKey = null;
      }
    });
  }

  List<AppUser> _usersForProfile(String profileId) {
    return _users.where((user) => user.profile?.id == profileId).toList();
  }

  void _toggleProfile(AppProfile profile, bool selected) {
    final users = _usersForProfile(profile.id);
    setState(() {
      if (selected) {
        _selectedProfileIds.add(profile.id);
        for (final user in users) {
          _selectedUserIds.add(user.id);
        }
        if (profile.slug == AppProfile.sellerSlug &&
            _selectedSellerDefaultDraftKey == null &&
            _validFilterDrafts.isNotEmpty) {
          _selectedSellerDefaultDraftKey = _validFilterDrafts.first.draftKey;
        }
      } else {
        _selectedProfileIds.remove(profile.id);
        for (final user in users) {
          _selectedUserIds.remove(user.id);
        }
        if (profile.slug == AppProfile.sellerSlug) {
          _selectedSellerDefaultDraftKey = null;
        }
      }
    });
  }

  void _toggleUser(String userId, bool selected) {
    setState(() {
      if (selected) {
        _selectedUserIds.add(userId);
      } else {
        _selectedUserIds.remove(userId);
      }
    });
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
        title: Text(_editing ? 'Editar módulo BI' : 'Novo módulo BI'),
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
              tooltip: 'Excluir módulo',
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
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _nameController,
                                decoration: const InputDecoration(
                                  labelText: 'Nome do módulo',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Informe o nome do módulo.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _urlController,
                                minLines: 2,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  labelText: 'Link base do painel Power BI',
                                  prefixIcon: Icon(Icons.link_outlined),
                                ),
                                validator: (value) {
                                  final trimmed = value?.trim() ?? '';
                                  final uri = Uri.tryParse(trimmed);
                                  if (trimmed.isEmpty) {
                                    return 'Informe o link do painel.';
                                  }
                                  if (uri == null ||
                                      !uri.hasScheme ||
                                      !uri.hasAuthority) {
                                    return 'Informe uma URL válida.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Campos filtráveis',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: _addFilter,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Adicionar campo'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ..._filters.asMap().entries.map((entry) {
                                final index = entry.key;
                                final filter = entry.value;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Card(
                                    color: const Color(0xFFF7F8FC),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Campo ${index + 1}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                ),
                                              ),
                                              IconButton(
                                                onPressed: _filters.length == 1
                                                    ? null
                                                    : () =>
                                                          _removeFilter(index),
                                                icon: const Icon(
                                                  Icons.remove_circle_outline,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          TextFormField(
                                            controller: filter.tableController,
                                            onChanged: (_) {
                                              setState(() {});
                                            },
                                            decoration: const InputDecoration(
                                              labelText: 'Tabela filtrável',
                                              prefixIcon: Icon(
                                                Icons.table_chart_outlined,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          TextFormField(
                                            controller: filter.columnController,
                                            onChanged: (_) {
                                              setState(() {});
                                            },
                                            decoration: const InputDecoration(
                                              labelText: 'Coluna filtrável',
                                              prefixIcon: Icon(
                                                Icons.view_column_outlined,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          TextFormField(
                                            controller: filter.labelController,
                                            onChanged: (_) {
                                              setState(() {});
                                            },
                                            decoration: const InputDecoration(
                                              labelText: 'Rótulo opcional',
                                              prefixIcon: Icon(
                                                Icons.label_outline,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
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
                                title: const Text('Módulo ativo'),
                              ),
                              const SizedBox(height: 16),
                              Card(
                                color: const Color(0xFFF7F8FC),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    'Exemplo de filtro gerado:\n?filter=dVendedor/codusur eq 1716 and dFilial/codfilial eq 3',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Usuários com acesso a este módulo',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Selecione os perfis. Ao marcar um perfil, todos os usuários dele já ficam marcados e você pode desmarcar exceções.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: const Color(0xFF5E6A7C)),
                              ),
                              const SizedBox(height: 12),
                              ..._profiles.map(_buildProfileCard),
                              if (_sellerProfileSelected) ...[
                                const SizedBox(height: 16),
                                DropdownButtonFormField<String>(
                                  initialValue: _selectedSellerDefaultDraftKey,
                                  items: _validFilterDrafts.map((draft) {
                                    return DropdownMenuItem<String>(
                                      value: draft.draftKey,
                                      child: Text(draft.displayLabel),
                                    );
                                  }).toList(),
                                  onChanged: _validFilterDrafts.isEmpty
                                      ? null
                                      : (value) {
                                          setState(() {
                                            _selectedSellerDefaultDraftKey =
                                                value;
                                          });
                                        },
                                  decoration: const InputDecoration(
                                    labelText:
                                        'Campo padrão para filtrar todos os vendedores',
                                    prefixIcon: Icon(Icons.filter_alt_outlined),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Ao salvar, os vendedores deste módulo receberão esse campo preenchido automaticamente com o código deles, sem impedir ajustes individuais depois.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF5E6A7C),
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

  Widget _buildProfileCard(AppProfile profile) {
    final users = _usersForProfile(profile.id);
    final isSelected = _selectedProfileIds.contains(profile.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: const Color(0xFFF7F8FC),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              CheckboxListTile(
                value: isSelected,
                onChanged: (value) => _toggleProfile(profile, value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: primaryColor,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  profile.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  users.isEmpty
                      ? 'Nenhum usuário neste perfil.'
                      : '${users.length} usuário(s) neste perfil.',
                ),
              ),
              if (isSelected && users.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...users.map((user) {
                  final label = user.displayName?.trim().isNotEmpty == true
                      ? user.label
                      : user.code;
                  return CheckboxListTile(
                    value: _selectedUserIds.contains(user.id),
                    onChanged: (value) => _toggleUser(user.id, value ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: primaryColor,
                    contentPadding: const EdgeInsets.only(left: 12),
                    dense: true,
                    title: Text(label),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterDraft {
  _FilterDraft({
    this.id,
    String? draftKey,
    String table = '',
    String column = '',
    String label = '',
  }) : draftKey =
           draftKey ??
           'draft_${DateTime.now().microsecondsSinceEpoch}_${_seed++}',
       tableController = TextEditingController(text: table),
       columnController = TextEditingController(text: column),
       labelController = TextEditingController(text: label);

  factory _FilterDraft.fromFilter(BiModuleFilter filter) {
    return _FilterDraft(
      id: filter.id,
      draftKey: filter.id,
      table: filter.filterTable,
      column: filter.filterColumn,
      label: filter.label ?? '',
    );
  }

  static int _seed = 0;

  final String? id;
  final String draftKey;
  final TextEditingController tableController;
  final TextEditingController columnController;
  final TextEditingController labelController;

  String get displayLabel {
    final label = labelController.text.trim();
    if (label.isNotEmpty) {
      return label;
    }
    final table = tableController.text.trim();
    final column = columnController.text.trim();
    if (table.isNotEmpty || column.isNotEmpty) {
      return '$table / $column';
    }
    return 'Campo sem nome';
  }

  void dispose() {
    tableController.dispose();
    columnController.dispose();
    labelController.dispose();
  }
}
