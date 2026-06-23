import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';

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

class _AppBootstrapState extends State<AppBootstrap>
    with WidgetsBindingObserver {
  final AppRepository _repository = AppRepository.instance;
  bool _loading = true;
  AppUser? _sessionUser;
  String? _errorMessage;
  RememberedLogin? _rememberedLogin;
  bool _updateCheckStarted = false;
  bool _updateCheckInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _updateCheckStarted) {
      unawaited(_checkForFlexibleUpdate());
    }
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
      _scheduleUpdateCheck();
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

  void _scheduleUpdateCheck() {
    if (_updateCheckStarted) {
      return;
    }
    _updateCheckStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForFlexibleUpdate());
    });
  }

  Future<void> _checkForFlexibleUpdate() async {
    if (_updateCheckInProgress) {
      return;
    }
    _updateCheckInProgress = true;
    try {
      final updateInfo = await InAppUpdate.checkForUpdate();
      if (!mounted) {
        return;
      }

      if (updateInfo.installStatus == InstallStatus.downloaded) {
        _showUpdateReadyMessage();
        return;
      }

      if (updateInfo.updateAvailability != UpdateAvailability.updateAvailable ||
          !updateInfo.flexibleUpdateAllowed) {
        return;
      }

      final result = await InAppUpdate.startFlexibleUpdate();
      if (!mounted || result != AppUpdateResult.success) {
        return;
      }
      _showUpdateReadyMessage();
    } catch (_) {
      // Play In-App Updates is unavailable for sideloaded APKs and emulators.
    } finally {
      _updateCheckInProgress = false;
    }
  }

  void _showUpdateReadyMessage() {
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Atualizacao pronta para instalar.'),
        duration: const Duration(days: 1),
        action: SnackBarAction(
          label: 'Instalar',
          onPressed: () {
            unawaited(_completeFlexibleUpdate());
          },
        ),
      ),
    );
  }

  Future<void> _completeFlexibleUpdate() async {
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (_) {
      // Google Play will offer the update again on a future app session.
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
