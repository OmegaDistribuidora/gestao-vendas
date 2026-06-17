import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_theme.dart';
import '../models/app_user.dart';
import '../models/usage_report.dart';
import '../services/app_repository.dart';

enum _ReportsSection { overview, users, hours, weekdays }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.currentUser});

  final AppUser currentUser;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final AppRepository _repository = AppRepository.instance;
  final TextEditingController _userSearchController = TextEditingController();
  final NumberFormat _integerFormat = NumberFormat.decimalPattern('pt_BR');
  final NumberFormat _percentFormat = NumberFormat.decimalPattern('pt_BR');

  late DateTime _startDate;
  late DateTime _endDate;
  bool _loading = true;
  String? _errorMessage;
  String? _selectedUserId;
  int? _selectedQuickRangeDays = 7;
  List<AppUser> _users = const <AppUser>[];
  UsageReport _report = UsageReport.empty();
  _ReportsSection _selectedSection = _ReportsSection.overview;
  final Set<String> _expandedUserGroups = <String>{};

  @override
  void initState() {
    super.initState();
    _endDate = DateTime.now();
    _startDate = _endDate.subtract(const Duration(days: 6));
    _loadInitialData();
  }

  @override
  void dispose() {
    _userSearchController.dispose();
    super.dispose();
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
        _errorMessage = 'Nao foi possivel carregar os relatorios.\n$error';
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
        _errorMessage = 'Nao foi possivel carregar os relatorios.\n$error';
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
      _selectedQuickRangeDays = null;
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

  Future<void> _applyQuickRange(int days) async {
    final now = DateTime.now();
    setState(() {
      _selectedQuickRangeDays = days;
      _endDate = now;
      _startDate = now.subtract(Duration(days: days - 1));
    });
    await _loadReport();
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  String _formatCount(num value) {
    final rounded = value.round();
    return _integerFormat.format(rounded);
  }

  String _formatPercent(double ratio) {
    final fixed = double.parse((ratio * 100).toStringAsFixed(1));
    return '${_percentFormat.format(fixed)}%';
  }

  String _formatSectionLabel(_ReportsSection section) {
    switch (section) {
      case _ReportsSection.overview:
        return 'Visao geral';
      case _ReportsSection.users:
        return 'Usuarios';
      case _ReportsSection.hours:
        return 'Horarios';
      case _ReportsSection.weekdays:
        return 'Dias';
    }
  }

  IconData _formatSectionIcon(_ReportsSection section) {
    switch (section) {
      case _ReportsSection.overview:
        return Icons.dashboard_customize_outlined;
      case _ReportsSection.users:
        return Icons.groups_2_outlined;
      case _ReportsSection.hours:
        return Icons.schedule_outlined;
      case _ReportsSection.weekdays:
        return Icons.calendar_view_week_outlined;
    }
  }

  List<_ProfileUsageStat> get _profileStats {
    final total = _report.totalLogins.toDouble();
    final items = _report.loginsByProfile.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    return items.map((item) {
      final style = _profileStyle(item.label);
      final ratio = total <= 0 ? 0.0 : item.value / total;
      return _ProfileUsageStat(
        label: item.label,
        value: item.value,
        ratio: ratio,
        color: style.color,
        backgroundColor: style.backgroundColor,
        icon: style.icon,
      );
    }).toList();
  }

  List<UsageBucket> get _aggregatedHours {
    final combined = <String, double>{};
    for (final group in _report.loginsByHourByProfile) {
      for (final item in group.items) {
        combined.update(
          item.label,
          (value) => value + item.value,
          ifAbsent: () => item.value,
        );
      }
    }

    final buckets = combined.entries
        .map((entry) => UsageBucket(label: entry.key, value: entry.value))
        .toList();
    buckets.sort(
      (left, right) =>
          _parseHourLabel(left.label).compareTo(_parseHourLabel(right.label)),
    );
    return buckets;
  }

  List<UsageBucket> get _aggregatedWeekdays {
    const weekdayOrder = <String, int>{
      'Segunda': 1,
      'Terca': 2,
      'Terça': 2,
      'Quarta': 3,
      'Quinta': 4,
      'Sexta': 5,
      'Sabado': 6,
      'Sábado': 6,
      'Domingo': 7,
    };

    final combined = <String, double>{};
    for (final group in _report.loginsByWeekdayByProfile) {
      for (final item in group.items) {
        combined.update(
          item.label,
          (value) => value + item.value,
          ifAbsent: () => item.value,
        );
      }
    }

    final buckets = combined.entries
        .map((entry) => UsageBucket(label: entry.key, value: entry.value))
        .toList();
    buckets.sort((left, right) {
      final leftOrder = weekdayOrder[left.label] ?? 99;
      final rightOrder = weekdayOrder[right.label] ?? 99;
      return leftOrder.compareTo(rightOrder);
    });
    return buckets;
  }

  UsageBucket? get _peakHour {
    final items = _aggregatedHours;
    if (items.isEmpty) {
      return null;
    }
    return items.reduce((best, next) => next.value > best.value ? next : best);
  }

  UsageBucket? get _peakWeekday {
    final items = _aggregatedWeekdays;
    if (items.isEmpty) {
      return null;
    }
    return items.reduce((best, next) => next.value > best.value ? next : best);
  }

  List<UsageBucket> get _topActiveUsers {
    final items = _report.activeUsersDetails.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    return items.take(5).toList();
  }

  List<UsageGroup> get _filteredUserGroups {
    final term = _userSearchController.text.trim().toLowerCase();
    final groups = _report.loginsByUserByProfile.toList()
      ..sort(
        (left, right) => _profileGroupSort(
          left.label,
        ).compareTo(_profileGroupSort(right.label)),
      );

    if (term.isEmpty) {
      return groups;
    }

    return groups
        .map((group) {
          final items = group.items
              .where((item) => item.label.toLowerCase().contains(term))
              .toList();
          if (items.isEmpty) {
            return null;
          }
          return UsageGroup(label: group.label, items: items);
        })
        .whereType<UsageGroup>()
        .toList();
  }

  int _parseHourLabel(String label) {
    final match = RegExp(r'(\d{1,2})').firstMatch(label);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  int _profileGroupSort(String label) {
    final normalized = label.trim().toLowerCase();
    if (normalized.contains('admin')) {
      return 1;
    }
    if (normalized.contains('diretoria')) {
      return 2;
    }
    if (normalized.contains('coorden')) {
      return 3;
    }
    if (normalized.contains('supervis')) {
      return 4;
    }
    if (normalized.contains('vendedor')) {
      return 5;
    }
    return 9;
  }

  _ProfileStyle _profileStyle(String label) {
    final normalized = label.trim().toLowerCase();
    if (normalized.contains('admin')) {
      return const _ProfileStyle(
        color: Color(0xFF5B3DF5),
        backgroundColor: Color(0xFFEEE9FF),
        icon: Icons.admin_panel_settings_outlined,
      );
    }
    if (normalized.contains('diretoria')) {
      return const _ProfileStyle(
        color: Color(0xFF2F7DF6),
        backgroundColor: Color(0xFFE8F1FF),
        icon: Icons.apartment_outlined,
      );
    }
    if (normalized.contains('coorden')) {
      return const _ProfileStyle(
        color: Color(0xFF2FA66A),
        backgroundColor: Color(0xFFE7F8EE),
        icon: Icons.hub_outlined,
      );
    }
    if (normalized.contains('supervis')) {
      return const _ProfileStyle(
        color: Color(0xFFF59E0B),
        backgroundColor: Color(0xFFFFF4DE),
        icon: Icons.manage_accounts_outlined,
      );
    }
    if (normalized.contains('vendedor')) {
      return const _ProfileStyle(
        color: Color(0xFFE6495D),
        backgroundColor: Color(0xFFFFE9EC),
        icon: Icons.storefront_outlined,
      );
    }
    return const _ProfileStyle(
      color: Color(0xFF7C5AC9),
      backgroundColor: Color(0xFFF0EBFF),
      icon: Icons.more_horiz_outlined,
    );
  }

  String _initials(String label) {
    final parts = label
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '--';
    }
    if (parts.length == 1) {
      return parts.first
          .substring(0, math.min(2, parts.first.length))
          .toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  bool _isGroupExpanded(String label) => _expandedUserGroups.contains(label);

  void _toggleUserGroup(String label) {
    setState(() {
      if (_expandedUserGroups.contains(label)) {
        _expandedUserGroups.remove(label);
      } else {
        _expandedUserGroups.add(label);
      }
    });
  }

  Widget _buildDropdownLabel(String text) {
    return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  Widget _buildHeader() {
    final sparklineItems = _aggregatedHours;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [primaryColor, Color(0xFF1B26A8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Central de uso',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Resumo administrativo de acessos, horarios e perfis.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.insights_outlined,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatCount(_report.totalLogins),
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              height: 0.95,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'logins no periodo selecionado',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _HeroPill(
                            icon: Icons.people_alt_outlined,
                            label:
                                '${_formatCount(_report.activeUsers)} usuarios ativos',
                          ),
                          if (_peakHour != null)
                            _HeroPill(
                              icon: Icons.schedule_outlined,
                              label: 'Pico em ${_peakHour!.label}',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (sparklineItems.isNotEmpty)
                  SizedBox(
                    width: 118,
                    height: 76,
                    child: CustomPaint(
                      painter: _SparklinePainter(
                        values: sparklineItems
                            .map((item) => item.value)
                            .toList(),
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filtros',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
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
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _RangeChip(
                  label: 'Hoje',
                  selected: _selectedQuickRangeDays == 1,
                  onTap: () => _applyQuickRange(1),
                ),
                _RangeChip(
                  label: '7 dias',
                  selected: _selectedQuickRangeDays == 7,
                  onTap: () => _applyQuickRange(7),
                ),
                _RangeChip(
                  label: '30 dias',
                  selected: _selectedQuickRangeDays == 30,
                  onTap: () => _applyQuickRange(30),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _selectedUserId,
              isExpanded: true,
              items: <DropdownMenuItem<String?>>[
                DropdownMenuItem<String?>(
                  value: null,
                  child: _buildDropdownLabel('Todos os usuarios'),
                ),
                ..._users.map((user) {
                  final label = user.displayName?.trim().isNotEmpty == true
                      ? '${user.displayName} (${user.code})'
                      : user.code;
                  return DropdownMenuItem<String?>(
                    value: user.id,
                    child: _buildDropdownLabel(label),
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
                labelText: 'Escopo do relatorio',
                prefixIcon: Icon(Icons.person_search_outlined),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionSwitcher() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _ReportsSection.values.map((section) {
            final selected = section == _selectedSection;
            return ChoiceChip(
              selected: selected,
              onSelected: (_) {
                setState(() {
                  _selectedSection = section;
                });
              },
              avatar: Icon(
                _formatSectionIcon(section),
                size: 18,
                color: selected ? Colors.white : primaryColor,
              ),
              label: Text(_formatSectionLabel(section)),
              labelStyle: TextStyle(
                color: selected ? Colors.white : primaryColor,
                fontWeight: FontWeight.w700,
              ),
              selectedColor: primaryColor,
              backgroundColor: const Color(0xFFE8ECFF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildOverviewSection() {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 620;
            final cards = [
              _SummaryMetricCard(
                title: 'Usuarios ativos',
                value: _formatCount(_report.activeUsers),
                subtitle: 'Pessoas diferentes que fizeram login no periodo.',
                icon: Icons.verified_user_outlined,
                accentColor: const Color(0xFF5B3DF5),
                accentBackgroundColor: const Color(0xFFEFE9FF),
              ),
              _SummaryMetricCard(
                title: 'Total de logins',
                value: _formatCount(_report.totalLogins),
                subtitle: 'Soma de todos os acessos confirmados no sistema.',
                icon: Icons.login_rounded,
                accentColor: const Color(0xFF1BB56D),
                accentBackgroundColor: const Color(0xFFE7F8EE),
              ),
            ];

            if (stacked) {
              return Column(
                children: [cards[0], const SizedBox(height: 12), cards[1]],
              );
            }

            return Row(
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 12),
                Expanded(child: cards[1]),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _buildProfileBreakdownCard(),
        const SizedBox(height: 16),
        _buildSpotlightUsersCard(),
      ],
    );
  }

  Widget _buildProfileBreakdownCard() {
    final stats = _profileStats;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Logins por perfil',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Distribuicao dos acessos por perfil no periodo filtrado.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF5E6A7C),
                        ),
                      ),
                    ],
                  ),
                ),
                if (stats.isNotEmpty)
                  SizedBox(
                    width: 92,
                    height: 92,
                    child: CustomPaint(
                      painter: _DonutChartPainter(
                        sections: stats
                            .map(
                              (item) => _DonutSection(item.color, item.ratio),
                            )
                            .toList(),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Total',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: const Color(0xFF64748B)),
                            ),
                            Text(
                              _formatCount(_report.totalLogins),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (stats.isEmpty)
              const _EmptySectionCard(
                message: 'Sem logins por perfil neste periodo.',
              )
            else
              ...stats.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ProfileBreakdownRow(
                    item: item,
                    formatCount: _formatCount,
                    formatPercent: _formatPercent,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpotlightUsersCard() {
    final users = _topActiveUsers;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Usuarios em destaque',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Quem mais apareceu no app dentro do recorte atual.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF5E6A7C)),
            ),
            const SizedBox(height: 18),
            if (users.isEmpty)
              const _EmptySectionCard(
                message: 'Sem usuarios ativos neste periodo.',
              )
            else
              ...users.asMap().entries.map((entry) {
                final item = entry.value;
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: entry.key == users.length - 1 ? 0 : 12,
                  ),
                  child: _SpotlightUserRow(
                    rank: entry.key + 1,
                    label: item.label,
                    value: _formatCount(item.value),
                    initials: _initials(item.label),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersSection() {
    final groups = _filteredUserGroups;
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Logins por usuario',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Pesquise usuarios e navegue pelos perfis com mais acessos.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5E6A7C),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _userSearchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Buscar usuario',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _userSearchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _userSearchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  onChanged: (_) {
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (groups.isEmpty)
          const _EmptySectionCard(
            message: 'Nenhum usuario encontrado com os filtros atuais.',
          )
        else
          ...groups.map((group) {
            final expanded = _isGroupExpanded(group.label);
            final visibleItems = expanded
                ? group.items
                : group.items.take(5).toList();
            final style = _profileStyle(group.label);
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: style.backgroundColor,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(style.icon, color: style.color),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  group.label,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${group.items.length} usuario(s)',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF64748B),
                                      ),
                                ),
                              ],
                            ),
                          ),
                          if (group.items.length > 5)
                            TextButton(
                              onPressed: () => _toggleUserGroup(group.label),
                              child: Text(
                                expanded ? 'Mostrar menos' : 'Ver todos',
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ...visibleItems.asMap().entries.map((entry) {
                        final item = entry.value;
                        final maxValue = group.items.isEmpty
                            ? 1.0
                            : group.items.first.value <= 0
                            ? 1.0
                            : group.items.first.value;
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: entry.key == visibleItems.length - 1
                                ? 0
                                : 12,
                          ),
                          child: _UserRankRow(
                            rank: entry.key + 1,
                            label: item.label,
                            value: _formatCount(item.value),
                            ratio: maxValue <= 0
                                ? 0
                                : (item.value / maxValue).clamp(0.0, 1.0),
                            color: style.color,
                            backgroundColor: style.backgroundColor,
                            initials: _initials(item.label),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildHoursSection() {
    final hours = _aggregatedHours;
    return Column(
      children: [
        _SummaryMetricCard(
          title: 'Logins por hora',
          value: _formatCount(_report.totalLogins),
          subtitle: _peakHour == null
              ? 'Sem dados horarios para o periodo.'
              : 'Maior concentracao em ${_peakHour!.label}.',
          icon: Icons.schedule_outlined,
          accentColor: const Color(0xFF5B3DF5),
          accentBackgroundColor: const Color(0xFFEFE9FF),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Distribuicao horaria',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Panorama dos horarios com mais atividade dentro do app.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5E6A7C),
                  ),
                ),
                const SizedBox(height: 18),
                if (hours.isEmpty)
                  const _EmptySectionCard(
                    message: 'Sem logins por hora neste periodo.',
                  )
                else ...[
                  SizedBox(
                    height: 220,
                    child: _UsageBarChart(
                      items: hours,
                      color: const Color(0xFF5B3DF5),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ...hours.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(child: Text(item.label)),
                          Text(
                            _formatCount(item.value),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekdaysSection() {
    final weekdays = _aggregatedWeekdays;
    final peak = _peakWeekday;
    final maxValue = weekdays.isEmpty
        ? 1.0
        : weekdays.map((item) => item.value).reduce(math.max);

    return Column(
      children: [
        _SummaryMetricCard(
          title: 'Logins por dia da semana',
          value: _formatCount(_report.totalLogins),
          subtitle: peak == null
              ? 'Sem dados semanais para o periodo.'
              : 'Dia com maior volume: ${peak.label}.',
          icon: Icons.calendar_today_outlined,
          accentColor: const Color(0xFF1BB56D),
          accentBackgroundColor: const Color(0xFFE7F8EE),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ritmo semanal',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Veja como os acessos se distribuem ao longo da semana.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5E6A7C),
                  ),
                ),
                const SizedBox(height: 18),
                if (weekdays.isEmpty)
                  const _EmptySectionCard(
                    message: 'Sem logins por dia da semana neste periodo.',
                  )
                else
                  ...weekdays.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _WeekdayBarRow(
                        label: item.label,
                        value: _formatCount(item.value),
                        fraction: maxValue <= 0
                            ? 0
                            : (item.value / maxValue).clamp(0.0, 1.0),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionContent() {
    switch (_selectedSection) {
      case _ReportsSection.overview:
        return _buildOverviewSection();
      case _ReportsSection.users:
        return _buildUsersSection();
      case _ReportsSection.hours:
        return _buildHoursSection();
      case _ReportsSection.weekdays:
        return _buildWeekdaysSection();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Relatorios de uso'),
        actions: [
          IconButton(
            onPressed: _loadReport,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: primaryColor),
              )
            : _errorMessage != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_errorMessage!, textAlign: TextAlign.center),
                ),
              )
            : RefreshIndicator(
                color: primaryColor,
                onRefresh: _loadReport,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 16),
                    _buildFilterCard(),
                    const SizedBox(height: 16),
                    _buildSectionSwitcher(),
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: KeyedSubtree(
                        key: ValueKey<_ReportsSection>(_selectedSection),
                        child: _buildSectionContent(),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onTap(),
      label: Text(label),
      labelStyle: TextStyle(
        color: selected ? Colors.white : primaryColor,
        fontWeight: FontWeight.w700,
      ),
      selectedColor: primaryColor,
      backgroundColor: const Color(0xFFE8ECFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }
}

class _SummaryMetricCard extends StatelessWidget {
  const _SummaryMetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.accentBackgroundColor,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final Color accentBackgroundColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 0.95,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF5E6A7C),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: accentBackgroundColor,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: accentColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileBreakdownRow extends StatelessWidget {
  const _ProfileBreakdownRow({
    required this.item,
    required this.formatCount,
    required this.formatPercent,
  });

  final _ProfileUsageStat item;
  final String Function(num value) formatCount;
  final String Function(double ratio) formatPercent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: item.backgroundColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(item.icon, color: item.color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${formatCount(item.value)} (${formatPercent(item.ratio)})',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF475569),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: item.ratio,
                  minHeight: 7,
                  color: item.color,
                  backgroundColor: const Color(0xFFE8EDF7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpotlightUserRow extends StatelessWidget {
  const _SpotlightUserRow({
    required this.rank,
    required this.label,
    required this.value,
    required this.initials,
  });

  final int rank;
  final String label;
  final String value;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E9F5)),
      ),
      child: Row(
        children: [
          Text(
            '$rank',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 14),
          _AvatarBadge(initials: initials),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _UserRankRow extends StatelessWidget {
  const _UserRankRow({
    required this.rank,
    required this.label,
    required this.value,
    required this.ratio,
    required this.color,
    required this.backgroundColor,
    required this.initials,
  });

  final int rank;
  final String label;
  final String value;
  final double ratio;
  final Color color;
  final Color backgroundColor;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E9F5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$rank',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _AvatarBadge(
            initials: initials,
            backgroundColor: backgroundColor,
            foregroundColor: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    color: color,
                    backgroundColor: const Color(0xFFE8EDF7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekdayBarRow extends StatelessWidget {
  const _WeekdayBarRow({
    required this.label,
    required this.value,
    required this.fraction,
  });

  final String label;
  final String value;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 14,
              color: primaryColor,
              backgroundColor: const Color(0xFFE8EDF7),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 34,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge({
    required this.initials,
    this.backgroundColor = const Color(0xFFE9ECFF),
    this.foregroundColor = primaryColor,
  });

  final String initials;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: foregroundColor,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptySectionCard extends StatelessWidget {
  const _EmptySectionCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E9F5)),
      ),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF5E6A7C)),
      ),
    );
  }
}

class _UsageBarChart extends StatelessWidget {
  const _UsageBarChart({required this.items, required this.color});

  final List<UsageBucket> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final maxValue = items.isEmpty
        ? 1.0
        : items.map((item) => item.value).reduce(math.max);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final item in items)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: maxValue <= 0
                            ? 4
                            : math.max(4, (item.value / maxValue) * 150),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      return;
    }

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final valueRange = (maxValue - minValue).abs() < 0.001
        ? 1.0
        : maxValue - minValue;
    final path = Path();

    for (var index = 0; index < values.length; index++) {
      final dx = size.width * index / (values.length - 1);
      final normalized = (values[index] - minValue) / valueRange;
      final dy = size.height - (normalized * size.height);
      if (index == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}

class _DonutSection {
  const _DonutSection(this.color, this.ratio);

  final Color color;
  final double ratio;
}

class _DonutChartPainter extends CustomPainter {
  const _DonutChartPainter({required this.sections});

  final List<_DonutSection> sections;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.18;
    final rect = Offset.zero & size;
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFE9EEF8);

    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      -math.pi / 2,
      math.pi * 2,
      false,
      basePaint,
    );

    var startAngle = -math.pi / 2;
    for (final section in sections) {
      if (section.ratio <= 0) {
        continue;
      }
      final sweep = (math.pi * 2) * section.ratio;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = section.color;
      canvas.drawArc(
        rect.deflate(strokeWidth / 2),
        startAngle,
        sweep,
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.sections != sections;
  }
}

class _ProfileUsageStat {
  const _ProfileUsageStat({
    required this.label,
    required this.value,
    required this.ratio,
    required this.color,
    required this.backgroundColor,
    required this.icon,
  });

  final String label;
  final double value;
  final double ratio;
  final Color color;
  final Color backgroundColor;
  final IconData icon;
}

class _ProfileStyle {
  const _ProfileStyle({
    required this.color,
    required this.backgroundColor,
    required this.icon,
  });

  final Color color;
  final Color backgroundColor;
  final IconData icon;
}
