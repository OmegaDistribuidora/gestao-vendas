import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/app_user.dart';
import '../models/usage_report.dart';
import '../services/app_repository.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.currentUser});

  final AppUser currentUser;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final AppRepository _repository = AppRepository.instance;
  late DateTime _startDate;
  late DateTime _endDate;
  bool _loading = true;
  String? _errorMessage;
  String? _selectedUserId;
  List<AppUser> _users = const <AppUser>[];
  UsageReport _report = UsageReport.empty();

  @override
  void initState() {
    super.initState();
    _endDate = DateTime.now();
    _startDate = _endDate.subtract(const Duration(days: 6));
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final users = await _repository.getUsers();
      if (!mounted) {
        return;
      }
      setState(() {
        _users = users;
      });
      await _loadReport();
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
        _errorMessage = 'Não foi possível carregar os relatórios.\n$error';
      });
    }
  }

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final report = await _repository.getUsageReport(
        start: DateTime(_startDate.year, _startDate.month, _startDate.day),
        end: DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59),
        userId: _selectedUserId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _report = report;
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
        _errorMessage = 'Não foi possível carregar os relatórios.\n$error';
      });
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initialDate = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('pt', 'BR'),
    );

    if (picked == null) {
      return;
    }

    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_startDate.isAfter(_endDate)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
        if (_endDate.isBefore(_startDate)) {
          _startDate = picked;
        }
      }
    });

    await _loadReport();
  }

  void _applyQuickRange(int days) {
    final now = DateTime.now();
    setState(() {
      _endDate = now;
      _startDate = now.subtract(Duration(days: days - 1));
    });
    _loadReport();
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  String _buildTooltipText(
    List<UsageBucket> items, {
    String empty = 'Sem dados.',
  }) {
    if (items.isEmpty) {
      return empty;
    }

    return items
        .map(
          (item) =>
              '${item.label}: ${item.value.toStringAsFixed(item.value.truncateToDouble() == item.value ? 0 : 1)}',
        )
        .join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Relatórios de uso'),
        actions: [
          IconButton(
            onPressed: _loadReport,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
        ],
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
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _pickDate(isStart: true),
                              icon: const Icon(Icons.date_range_outlined),
                              label: Text(_formatDate(_startDate)),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _pickDate(isStart: false),
                              icon: const Icon(Icons.event_outlined),
                              label: Text(_formatDate(_endDate)),
                            ),
                            ActionChip(
                              label: const Text('7 dias'),
                              onPressed: () => _applyQuickRange(7),
                            ),
                            ActionChip(
                              label: const Text('30 dias'),
                              onPressed: () => _applyQuickRange(30),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String?>(
                          initialValue: _selectedUserId,
                          items: <DropdownMenuItem<String?>>[
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Todos os usuários'),
                            ),
                            ..._users.map((user) {
                              final label =
                                  user.displayName?.trim().isNotEmpty == true
                                  ? '${user.displayName} (${user.code})'
                                  : user.code;
                              return DropdownMenuItem<String?>(
                                value: user.id,
                                child: Text(label),
                              );
                            }),
                          ],
                          onChanged: (value) async {
                            setState(() {
                              _selectedUserId = value;
                            });
                            await _loadReport();
                          },
                          decoration: const InputDecoration(
                            labelText: 'Filtrar por usuário',
                            prefixIcon: Icon(Icons.person_search_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _MetricCard(
                      title: 'Usuários ativos',
                      value: '${_report.activeUsers}',
                      description:
                          'Usuários ativos que fizeram login e/ou abriram pelo menos um painel no período.',
                      tooltipMessage: _buildTooltipText(
                        _report.activeUsersDetails,
                        empty: 'Nenhum usuário ativo no período.',
                      ),
                    ),
                    _MetricCard(
                      title: 'Logins no sistema',
                      value: '${_report.totalLogins}',
                      description:
                          'Quantidade total de logins realizados no período.',
                      tooltipMessage: _buildTooltipText(
                        _report.loginsByUser,
                        empty: 'Nenhum login no período.',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _FlatReportSection(
                  title: 'Logins por perfil',
                  items: _report.loginsByProfile,
                ),
                const SizedBox(height: 16),
                _GroupedReportSection(
                  title: 'Logins por usuário',
                  groups: _report.loginsByUserByProfile,
                ),
                const SizedBox(height: 16),
                _GroupedReportSection(
                  title: 'Módulos mais abertos',
                  groups: _report.modulesByOpenCountByProfile,
                ),
                const SizedBox(height: 16),
                _FlatReportSection(
                  title: 'Tempo por módulo',
                  items: _report.minutesByModule,
                  suffix: ' min',
                ),
                const SizedBox(height: 16),
                _GroupedReportSection(
                  title: 'Logins por hora',
                  groups: _report.loginsByHourByProfile,
                ),
                const SizedBox(height: 16),
                _GroupedReportSection(
                  title: 'Logins por dia da semana',
                  groups: _report.loginsByWeekdayByProfile,
                ),
              ],
            ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.description,
    required this.tooltipMessage,
  });

  final String title;
  final String value;
  final String description;
  final String tooltipMessage;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 5),
      message: tooltipMessage,
      child: SizedBox(
        width: 260,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF5E6A7C),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FlatReportSection extends StatelessWidget {
  const _FlatReportSection({
    required this.title,
    required this.items,
    this.suffix = '',
  });

  final String title;
  final List<UsageBucket> items;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Text('Sem dados no período.')
            else
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(child: Text(item.label)),
                      Text(
                        '${item.value.toStringAsFixed(item.value.truncateToDouble() == item.value ? 0 : 1)}$suffix',
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupedReportSection extends StatelessWidget {
  const _GroupedReportSection({required this.title, required this.groups});

  final String title;
  final List<UsageGroup> groups;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (groups.isEmpty)
              const Text('Sem dados no período.')
            else
              ...groups.map(
                (group) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.label,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      if (group.items.isEmpty)
                        const Text('Sem dados neste perfil.')
                      else
                        ...group.items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(child: Text(item.label)),
                                Text(
                                  item.value.toStringAsFixed(
                                    item.value.truncateToDouble() == item.value
                                        ? 0
                                        : 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
