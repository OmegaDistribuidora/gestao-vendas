import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/app_theme.dart';

class PanelViewScreen extends StatefulWidget {
  const PanelViewScreen({
    super.key,
    required this.title,
    required this.initialUrl,
    this.filterDescription,
    required this.isAdminView,
  });

  final String title;
  final String initialUrl;
  final String? filterDescription;
  final bool isAdminView;

  @override
  State<PanelViewScreen> createState() => _PanelViewScreenState();
}

class _PanelViewScreenState extends State<PanelViewScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) {
              return;
            }

            setState(() {
              _progress = progress;
            });
          },
          onWebResourceError: (error) {
            if (!mounted || !(error.isForMainFrame ?? false)) {
              return;
            }

            setState(() {
              _errorMessage =
                  'Falha ao carregar o painel: ${error.description}';
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  Future<void> _reload() async {
    setState(() {
      _errorMessage = null;
      _progress = 0;
    });
    await _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Text(
              widget.isAdminView
                  ? 'Vis\u00E3o administrativa: painel aberto sem filtro autom\u00E1tico.'
                  : 'Filtro aplicado: ${widget.filterDescription ?? '-'}',
              style: const TextStyle(
                color: Color(0xFF23304A),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_progress > 0 && _progress < 100)
            LinearProgressIndicator(
              value: _progress / 100,
              color: primaryColor,
              backgroundColor: const Color(0xFFD8DEFF),
            ),
          Expanded(
            child: _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.wifi_off_outlined,
                                  color: primaryColor,
                                  size: 48,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 20),
                                FilledButton(
                                  onPressed: _reload,
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
                  )
                : WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}
