import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/app_theme.dart';
import 'app_bootstrap.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onLogin, this.initialIdentifier});

  final Future<void> Function({
    required String login,
    required String password,
    required bool rememberLogin,
  })
  onLogin;
  final String? initialIdentifier;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _hidePassword = true;
  bool _rememberLogin = true;
  bool _submitting = false;
  String _appVersionLabel = '';

  @override
  void initState() {
    super.initState();
    _loginController.text = widget.initialIdentifier ?? '';
    _loadVersionLabel();
  }

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadVersionLabel() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version.trim();
      final buildNumber = packageInfo.buildNumber.trim();
      if (!mounted || version.isEmpty) {
        return;
      }
      setState(() {
        _appVersionLabel = buildNumber.isEmpty
            ? 'Versão $version'
            : 'Versão $version+$buildNumber';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _appVersionLabel = '';
        });
      }
    }
  }

  Future<void> _submit() async {
    final login = _loginController.text.trim();
    final password = _passwordController.text;

    if (login.isEmpty || password.isEmpty) {
      _showMessage('Informe o identificador e a senha.');
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await widget.onLogin(
        login: login,
        password: password,
        rememberLogin: _rememberLogin,
      );
    } on LoginException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage('Falha ao autenticar.\n$error');
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
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
    final topPadding = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final headerHeight = (constraints.maxHeight * 0.43).clamp(
            330.0,
            390.0,
          );

          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: headerHeight,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [primaryColor, Color(0xFF0824B8)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                        ),
                        const Positioned.fill(
                          child: CustomPaint(painter: _LoginHeaderPainter()),
                        ),
                        Positioned.fill(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              24,
                              topPadding + 42,
                              24,
                              0,
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: 66,
                                  height: 66,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x33000000),
                                        blurRadius: 18,
                                        offset: Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.bar_chart_rounded,
                                    color: primaryColor,
                                    size: 38,
                                  ),
                                ),
                                const SizedBox(height: 22),
                                Text(
                                  'Gestão de Vendas',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 28,
                                      ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Bem-vindo de volta!',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: Colors.white.withValues(
                                          alpha: 0.88,
                                        ),
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -58),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(26, 34, 26, 28),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(color: const Color(0xFFE1E7F2)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x22010066),
                                blurRadius: 28,
                                offset: Offset(0, 16),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Entrar na conta',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: const Color(0xFF111936),
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Acesse seus indicadores comerciais em tempo real.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: const Color(0xFF5B6682),
                                      height: 1.35,
                                    ),
                              ),
                              const SizedBox(height: 30),
                              TextField(
                                controller: _loginController,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  hintText: 'Código do vendedor ou login',
                                  prefixIcon: Icon(Icons.person_outline),
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _passwordController,
                                obscureText: _hidePassword,
                                onSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  hintText: 'Senha',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
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
                              ),
                              const SizedBox(height: 16),
                              CheckboxListTile(
                                value: _rememberLogin,
                                onChanged: (value) {
                                  setState(() {
                                    _rememberLogin = value ?? false;
                                  });
                                },
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                activeColor: primaryColor,
                                title: const Text('Lembrar meu acesso'),
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                height: 54,
                                child: FilledButton(
                                  onPressed: _submitting ? null : _submit,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: primaryColor,
                                    foregroundColor: Colors.white,
                                    textStyle: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  child: _submitting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Entrar'),
                                ),
                              ),
                              if (_appVersionLabel.isNotEmpty) ...[
                                const SizedBox(height: 26),
                                Text(
                                  _appVersionLabel,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF6B7490),
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LoginHeaderPainter extends CustomPainter {
  const _LoginHeaderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final upperWave = Path()
      ..moveTo(size.width * 0.45, 0)
      ..cubicTo(
        size.width * 0.56,
        size.height * 0.28,
        size.width * 0.80,
        size.height * 0.44,
        size.width,
        size.height * 0.31,
      )
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(
      upperWave,
      Paint()..color = Colors.white.withValues(alpha: 0.055),
    );

    final lowerWave = Path()
      ..moveTo(0, size.height * 0.78)
      ..cubicTo(
        size.width * 0.22,
        size.height * 0.60,
        size.width * 0.44,
        size.height * 0.70,
        size.width * 0.58,
        size.height,
      )
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      lowerWave,
      Paint()..color = Colors.white.withValues(alpha: 0.07),
    );

    final barsPaint = Paint()..color = Colors.white.withValues(alpha: 0.055);
    for (var index = 0; index < 4; index++) {
      final barHeight = 28.0 + (index * 18);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width - 72 + (index * 14),
          size.height - barHeight - 28,
          9,
          barHeight,
        ),
        const Radius.circular(5),
      );
      canvas.drawRRect(rect, barsPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LoginHeaderPainter oldDelegate) => false;
}
