import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/app_user.dart';
import 'change_password_screen.dart';
import 'profiles_management_screen.dart';
import 'reports_screen.dart';
import 'users_management_screen.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key, required this.currentUser});

  final AppUser currentUser;

  Future<void> _openProfiles(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ProfilesManagementScreen()),
    );
  }

  Future<void> _openUsers(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UsersManagementScreen(currentUser: currentUser),
      ),
    );
  }

  Future<void> _openReports(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportsScreen(currentUser: currentUser),
      ),
    );
  }

  Future<void> _openChangePassword(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangePasswordScreen(currentUser: currentUser),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Administração'),
        actions: [
          IconButton(
            onPressed: () => _openChangePassword(context),
            icon: const Icon(Icons.lock_reset_outlined),
            tooltip: 'Alterar minha senha',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Área administrativa',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Selecione o grupo que deseja acessar. Em cada tela você poderá criar, editar, inativar ou excluir os registros.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF5E6A7C),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _AdminAccessTile(
            title: 'Acessar perfis',
            description: 'Gerencie perfis e categorias de acesso.',
            icon: Icons.badge_outlined,
            onTap: () => _openProfiles(context),
          ),
          const SizedBox(height: 12),
          _AdminAccessTile(
            title: 'Acessar usuários',
            description: 'Cadastre, edite, inative e remova usuários.',
            icon: Icons.group_outlined,
            onTap: () => _openUsers(context),
          ),
          const SizedBox(height: 12),
          _AdminAccessTile(
            title: 'Acessar relatórios',
            description: 'Veja logins e atividade geral de uso do sistema.',
            icon: Icons.insights_outlined,
            onTap: () => _openReports(context),
          ),
        ],
      ),
    );
  }
}

class _AdminAccessTile extends StatelessWidget {
  const _AdminAccessTile({
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE7EBFF),
          foregroundColor: primaryColor,
          child: Icon(icon),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(description),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
