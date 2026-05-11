import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/app_profile.dart';
import '../services/app_repository.dart';
import 'profile_form_screen.dart';

class ProfilesManagementScreen extends StatefulWidget {
  const ProfilesManagementScreen({super.key});

  @override
  State<ProfilesManagementScreen> createState() =>
      _ProfilesManagementScreenState();
}

class _ProfilesManagementScreenState extends State<ProfilesManagementScreen> {
  final AppRepository _repository = AppRepository.instance;
  bool _loading = true;
  String? _errorMessage;
  String _search = '';
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
      final profiles = await _repository.getProfiles();
      if (!mounted) {
        return;
      }
      setState(() {
        _profiles = profiles;
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
        _errorMessage = 'Falha ao carregar perfis.\n$error';
      });
    }
  }

  Future<void> _openForm([AppProfile? profile]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ProfileFormScreen(existingProfile: profile),
      ),
    );

    if (changed == true) {
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleProfiles = _profiles.where((profile) {
      final search = _search.trim().toLowerCase();
      if (search.isEmpty) {
        return true;
      }
      return profile.name.toLowerCase().contains(search) ||
          profile.slug.toLowerCase().contains(search);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Perfis'),
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
        label: const Text('Novo perfil'),
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
                    labelText: 'Buscar perfil',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _search = value;
                    });
                  },
                ),
                const SizedBox(height: 20),
                if (visibleProfiles.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Nenhum perfil encontrado.'),
                    ),
                  )
                else
                  ...visibleProfiles.map(
                    (profile) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFE7EBFF),
                            foregroundColor: primaryColor,
                            child: Icon(
                              profile.isAdmin
                                  ? Icons.admin_panel_settings_outlined
                                  : Icons.badge_outlined,
                            ),
                          ),
                          title: Text(
                            profile.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            'Slug: ${profile.slug}${profile.isSystem ? '\nPerfil do sistema' : ''}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openForm(profile),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
