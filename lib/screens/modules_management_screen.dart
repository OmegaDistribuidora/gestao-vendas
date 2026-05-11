import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/bi_module.dart';
import '../services/app_repository.dart';
import 'bi_module_form_screen.dart';

class ModulesManagementScreen extends StatefulWidget {
  const ModulesManagementScreen({super.key});

  @override
  State<ModulesManagementScreen> createState() =>
      _ModulesManagementScreenState();
}

class _ModulesManagementScreenState extends State<ModulesManagementScreen> {
  final AppRepository _repository = AppRepository.instance;
  bool _loading = true;
  String? _errorMessage;
  String _search = '';
  List<BiModule> _modules = const <BiModule>[];

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
      final modules = await _repository.getBiModules();
      if (!mounted) {
        return;
      }
      setState(() {
        _modules = modules;
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
        _errorMessage = 'Falha ao carregar módulos.\n$error';
      });
    }
  }

  Future<void> _openForm([BiModule? module]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BiModuleFormScreen(existingModule: module),
      ),
    );

    if (changed == true) {
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleModules = _modules.where((module) {
      final search = _search.trim().toLowerCase();
      if (search.isEmpty) {
        return true;
      }
      return module.name.toLowerCase().contains(search) ||
          module.filters.any(
            (filter) =>
                filter.displayLabel.toLowerCase().contains(search) ||
                filter.filterTable.toLowerCase().contains(search) ||
                filter.filterColumn.toLowerCase().contains(search),
          );
    }).toList();

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Módulos BI'),
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
        label: const Text('Novo módulo'),
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
                    labelText: 'Buscar módulo',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _search = value;
                    });
                  },
                ),
                const SizedBox(height: 20),
                if (visibleModules.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Nenhum módulo encontrado.'),
                    ),
                  )
                else
                  ...visibleModules.map(
                    (module) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFE7EBFF),
                            foregroundColor: primaryColor,
                            child: Icon(Icons.bar_chart_outlined),
                          ),
                          title: Text(
                            module.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            'Filtros: ${module.filters.isEmpty ? 'Nenhum' : module.filters.map((item) => item.displayLabel).join(' | ')}\nStatus: ${module.isActive ? 'Ativo' : 'Inativo'}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openForm(module),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
