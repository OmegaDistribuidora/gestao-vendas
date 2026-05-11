import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/app_user.dart';
import '../services/app_repository.dart';
import '../models/remembered_login.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  final AppRepository _repository = AppRepository.instance;
  bool _loading = true;
  AppUser? _sessionUser;
  String? _errorMessage;
  RememberedLogin? _rememberedLogin;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      await _repository.initialize();
      final rememberedLogin = await _repository.loadRememberedLogin();
      _rememberedLogin = rememberedLogin;
      AppUser? sessionUser;

      if (rememberedLogin?.rememberLogin == true) {
        sessionUser = await _repository.restoreSession();
      } else {
        await _repository.signOut();
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _sessionUser = sessionUser;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _errorMessage = 'Falha ao inicializar os dados remotos.\n$error';
      });
    }
  }

  Future<void> _handleLogin({
    required String login,
    required String password,
    required bool rememberLogin,
  }) async {
    try {
      final user = await _repository.authenticate(
        login: login,
        password: password,
      );

      if (rememberLogin) {
        await _repository.saveRememberedLogin(
          identifier: login,
          rememberLogin: true,
        );
      } else {
        await _repository.clearRememberedLogin();
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _rememberedLogin = rememberLogin
            ? RememberedLogin(identifier: login, rememberLogin: true)
            : null;
        _sessionUser = user;
      });
    } on RepositoryException catch (error) {
      throw LoginException(error.message);
    }
  }

  Future<void> _handleLogout() async {
    await _repository.clearRememberedLogin();
    await _repository.signOut();

    if (!mounted) {
      return;
    }

    setState(() {
      _rememberedLogin = null;
      _sessionUser = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: primaryColor)),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gest\u00E3o de Vendas')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: primaryColor,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(_errorMessage!, textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _initialize,
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_sessionUser == null) {
      return LoginScreen(
        initialIdentifier: _rememberedLogin?.identifier,
        onLogin: _handleLogin,
      );
    }

    return HomeScreen(currentUser: _sessionUser!, onLogout: _handleLogout);
  }
}

class LoginException implements Exception {
  const LoginException(this.message);

  final String message;
}
