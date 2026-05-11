import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/app_user.dart';
import '../models/bi_module.dart';
import '../models/bi_module_filter.dart';
import '../models/user_module_access.dart';
import '../services/app_repository.dart';

class UserModuleAccessFormScreen extends StatefulWidget {
  const UserModuleAccessFormScreen({super.key, this.existingAccess});

  final UserModuleAccess? existingAccess;

  @override
  State<UserModuleAccessFormScreen> createState() =>
      _UserModuleAccessFormScreenState();
}

class _UserModuleAccessFormScreenState
    extends State<UserModuleAccessFormScreen> {
  final AppRepository _repository = AppRepository.instance;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;
  bool _deleting = false;
  bool _hasFilteredData = false;
  String? _errorMessage;
  List<AppUser> _users = const <AppUser>[];
  List<BiModule> _modules = const <BiModule>[];
  String? _selectedUserId;
  String? _selectedModuleId;
  Map<String, TextEditingController> _filterControllers =
      <String, TextEditingController>{};

  bool get _editing => widget.existingAccess != null;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _disposeFilterControllers();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final users = (await _repository.getUsers())
          .where((user) => !user.isAdmin)
          .toList();
      final modules = await _repository.getBiModules();

      if (!mounted) {
        return;
      }

      final selectedUserId =
          widget.existingAccess?.userId ?? (users.isEmpty ? null : users.first.id);
      final selectedModuleId = widget.existingAccess?.moduleId ??
          (modules.isEmpty ? null : modules.first.id);
      final selectedModule = _findModuleById(modules, selectedModuleId);

      _syncFilterControllers(
        module: selectedModule,
        initialValues: {
          for (final item in widget.existingAccess?.filterValues ??
              const <dynamic>[])
            item.moduleFilterId: item.filterValue,
        },
      );

      setState(() {
        _users = users;
        _modules = modules;
        _selectedUserId = selectedUserId;
        _selectedModuleId = selectedModuleId;
        _hasFilteredData = widget.existingAccess?.hasFilteredData ?? false;
        if (selectedModule == null || selectedModule.filters.isEmpty) {
          _hasFilteredData = false;
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
            'Falha ao carregar os dados da liberacao.\n$error';
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedUserId == null || _selectedModuleId == null) {
      _showMessage('Selecione um usuario e um modulo.');
      return;
    }

    final selectedModule = _selectedModule;
    final filterValues = _buildFilterValues();
    if (_hasFilteredData &&
        selectedModule != null &&
        selectedModule.filters.isNotEmpty &&
        filterValues.isEmpty) {
      _showMessage(
        'Informe pelo menos um valor de filtro para este modulo.',
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      if (_editing) {
        await _repository.updateUserModuleAccess(
          accessId: widget.existingAccess!.id,
          userId: _selectedUserId!,
          moduleId: _selectedModuleId!,
          hasFilteredData: _hasFilteredData,
          filterValues: _hasFilteredData ? filterValues : <String, String>{},
        );
      } else {
        await _repository.createUserModuleAccess(
          userId: _selectedUserId!,
          moduleId: _selectedModuleId!,
          hasFilteredData: _hasFilteredData,
          filterValues: _hasFilteredData ? filterValues : <String, String>{},
        );
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } on RepositoryException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage('Nao foi possivel salvar a liberacao.\n$error');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    final access = widget.existingAccess;
    if (access == null) {
      return;
    }

    setState(() {
      _deleting = true;
    });

    try {
      await _repository.deleteUserModuleAccess(access.id);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on RepositoryException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage('Nao foi possivel excluir a liberacao.\n$error');
    } finally {
      if (mounted) {
        setState(() {
          _deleting = false;
        });
      }
    }
  }

  BiModule? get _selectedModule => _findModuleById(_modules, _selectedModuleId);

  BiModule? _findModuleById(List<BiModule> modules, String? moduleId) {
    if (moduleId == null) {
      return null;
    }

    for (final module in modules) {
      if (module.id == moduleId) {
        return module;
      }
    }
    return null;
  }

  void _syncFilterControllers({
    required BiModule? module,
    Map<String, String> initialValues = const <String, String>{},
  }) {
    final previousValues = _buildFilterValues();
    _disposeFilterControllers();

    if (module == null) {
      _filterControllers = <String, TextEditingController>{};
      return;
    }

    _filterControllers = <String, TextEditingController>{
      for (final filter in module.filters)
        filter.id: TextEditingController(
          text: initialValues[filter.id] ?? previousValues[filter.id] ?? '',
        ),
    };
  }

  void _disposeFilterControllers() {
    for (final controller in _filterControllers.values) {
      controller.dispose();
    }
    _filterControllers = <String, TextEditingController>{};
  }

  Map<String, String> _buildFilterValues() {
    return <String, String>{
      for (final entry in _filterControllers.entries)
        if (entry.value.text.trim().isNotEmpty)
          entry.key: entry.value.text.trim(),
    };
  }

  void _handleModuleChanged(String? moduleId) {
    final selectedModule = _findModuleById(_modules, moduleId);
    _syncFilterControllers(module: selectedModule);
    setState(() {
      _selectedModuleId = moduleId;
      if (selectedModule == null || selectedModule.filters.isEmpty) {
        _hasFilteredData = false;
      }
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing ? 'Editar liberacao' : 'Liberacao usuario x modulo',
        ),
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
              tooltip: 'Excluir liberacao',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: primaryColor),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_errorMessage!, textAlign: TextAlign.center),
        ),
      );
    }

    if (_users.isEmpty || _modules.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _users.isEmpty
                      ? 'Cadastre pelo menos um usuario nao administrador antes de criar liberacoes.'
                      : 'Cadastre pelo menos um modulo BI antes de criar liberacoes.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final selectedModule = _selectedModule;

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _selectedUserId,
                        items: _users.map((user) {
                          final label = user.displayName?.trim().isNotEmpty == true
                              ? '${user.code} - ${user.displayName}'
                              : user.code;
                          return DropdownMenuItem<String>(
                            value: user.id,
                            child: Text('$label (${user.profileName})'),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedUserId = value;
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: 'Usuario',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedModuleId,
                        items: _modules.map((module) {
                          return DropdownMenuItem<String>(
                            value: module.id,
                            child: Text(module.name),
                          );
                        }).toList(),
                        onChanged: _handleModuleChanged,
                        decoration: const InputDecoration(
                          labelText: 'Modulo BI',
                          prefixIcon: Icon(Icons.bar_chart_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        color: const Color(0xFFF7F8FC),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Configuracao do modulo',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 12),
                              Text('Modulo: ${selectedModule?.name ?? '-'}'),
                              const SizedBox(height: 8),
                              Text(
                                selectedModule == null
                                    ? 'Nenhum modulo selecionado.'
                                    : selectedModule.filters.isEmpty
                                        ? 'Este modulo nao possui campos filtraveis cadastrados.'
                                        : 'Campos filtraveis: ${selectedModule.filters.map((item) => item.displayLabel).join(' | ')}',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        value: _hasFilteredData,
                        onChanged: selectedModule == null ||
                                selectedModule.filters.isEmpty
                            ? null
                            : (value) {
                                setState(() {
                                  _hasFilteredData = value;
                                });
                              },
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: primaryColor,
                        title: const Text('Liberar com dados filtrados'),
                      ),
                      if (_hasFilteredData &&
                          selectedModule != null &&
                          selectedModule.filters.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...selectedModule.filters.map(_buildFilterField),
                        const SizedBox(height: 8),
                        Text(
                          'Preencha apenas os filtros necessarios para este usuario.',
                          style: Theme.of(context).textTheme.bodySmall,
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
    );
  }

  Widget _buildFilterField(BiModuleFilter filter) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _filterControllers[filter.id],
        decoration: InputDecoration(
          labelText: filter.displayLabel,
          helperText: '${filter.filterTable} / ${filter.filterColumn}',
          prefixIcon: const Icon(Icons.filter_alt_outlined),
        ),
      ),
    );
  }
}
