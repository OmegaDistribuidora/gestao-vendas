import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'screens/app_bootstrap.dart';

class GestaoVendasApp extends StatelessWidget {
  const GestaoVendasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gest\u00E3o de Vendas',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AppBootstrap(),
    );
  }
}
