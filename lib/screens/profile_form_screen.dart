import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/app_profile.dart';
import '../services/app_repository.dart';

class ProfileFormScreen extends StatefulWidget {
  const ProfileFormScreen({super.key, this.existingProfile});

  final AppProfile? existingProfile;

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  final AppRepository _repository = AppRepository.instance;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _slugController;
  bool _saving = false;
  bool _deleting = false;

  bool get _editing => widget.existingProfile != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existingProfile?.name ?? '');
    _slugController = TextEditingController(text: widget.existingProfile?.slug ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      if (_editing) {
        await _repository.updateProfile(
          profileId: widget.existingProfile!.id,
          name: _nameController.text,
          slug: _slugController.text,
        );
      } else {
        await _repository.createProfile(
          name: _nameController.text,
          slug: _slugController.text,
        );
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } on RepositoryException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage('N\u00E3o foi poss\u00EDvel salvar o perfil.\n$error');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    final profile = widget.existingProfile;
    if (profile == null) {
      return;
    }

    setState(() {
      _deleting = true;
    });

    try {
      await _repository.deleteProfile(profile.id);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on RepositoryException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage('N\u00E3o foi poss\u00EDvel excluir o perfil.\n$error');
    } finally {
      if (mounted) {
        setState(() {
          _deleting = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isSystem = widget.existingProfile?.isSystem ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Editar perfil' : 'Novo perfil'),
        actions: [
          if (_editing && !isSystem)
            IconButton(
              onPressed: _saving || _deleting ? null : _delete,
              icon: _deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.delete_outline),
              tooltip: 'Excluir perfil',
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
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
                            labelText: 'Nome do perfil',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Informe o nome do perfil.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _slugController,
                          decoration: const InputDecoration(
                            labelText: 'Slug interno',
                            prefixIcon: Icon(Icons.code_outlined),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Informe o identificador do perfil.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        Card(
                          color: const Color(0xFFF7F8FC),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              isSystem
                                  ? 'Este perfil faz parte da base do sistema e n\u00E3o pode ser exclu\u00EDdo.'
                                  : 'Ao excluir um perfil, os usu\u00E1rios vinculados ser\u00E3o movidos para "Sem perfil".',
                            ),
                          ),
                        ),
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
