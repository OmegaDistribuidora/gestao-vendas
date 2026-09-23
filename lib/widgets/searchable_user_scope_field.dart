import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class SearchableUserScopeOption {
  const SearchableUserScopeOption({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.code,
    this.icon = Icons.person_outline_rounded,
  });

  final String value;
  final String title;
  final String subtitle;
  final String code;
  final IconData icon;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    return normalized.isEmpty ||
        title.toLowerCase().contains(normalized) ||
        subtitle.toLowerCase().contains(normalized) ||
        code.toLowerCase().contains(normalized);
  }
}

class SearchableUserScopeField extends StatelessWidget {
  const SearchableUserScopeField({
    super.key,
    required this.labelText,
    required this.options,
    required this.selectedValue,
    required this.allLabel,
    required this.onChanged,
    this.enabled = true,
    this.title = 'Selecione quem deseja filtrar',
    this.allowAll = true,
  });

  final String labelText;
  final List<SearchableUserScopeOption> options;
  final String? selectedValue;
  final String allLabel;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final String title;
  final bool allowAll;

  SearchableUserScopeOption? get _selectedOption {
    for (final option in options) {
      if (option.value == selectedValue) {
        return option;
      }
    }
    return null;
  }

  Future<void> _openPicker(BuildContext context) async {
    if (!enabled) {
      return;
    }
    final result = await showModalBottomSheet<_ScopeSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SearchableUserScopeSheet(
        title: title,
        options: options,
        selectedValue: selectedValue,
        allLabel: allLabel,
        allowAll: allowAll,
      ),
    );
    if (result != null) {
      onChanged(result.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedOption;
    final displayText = selected?.title ?? allLabel;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: enabled ? () => _openPicker(context) : null,
      child: InputDecorator(
        isEmpty: false,
        decoration: InputDecoration(
          labelText: labelText,
          prefixIcon: const Icon(Icons.manage_search_outlined),
          suffixIcon: enabled
              ? const Icon(Icons.arrow_drop_down_rounded)
              : null,
          enabled: enabled,
        ),
        child: Text(displayText, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _ScopeSelection {
  const _ScopeSelection(this.value);

  final String? value;
}

class _SearchableUserScopeSheet extends StatefulWidget {
  const _SearchableUserScopeSheet({
    required this.title,
    required this.options,
    required this.selectedValue,
    required this.allLabel,
    required this.allowAll,
  });

  final String title;
  final List<SearchableUserScopeOption> options;
  final String? selectedValue;
  final String allLabel;
  final bool allowAll;

  @override
  State<_SearchableUserScopeSheet> createState() =>
      _SearchableUserScopeSheetState();
}

class _SearchableUserScopeSheetState extends State<_SearchableUserScopeSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.options
        .where((option) => option.matches(_query))
        .toList(growable: false);
    final showAll = widget.allowAll && _query.trim().isEmpty;

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    autofocus: false,
                    textInputAction: TextInputAction.search,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      hintText: 'Buscar por nome ou código',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty && !showAll
                  ? const Center(child: Text('Nenhum usuário encontrado.'))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                      children: [
                        if (showAll)
                          ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFFF0F2FF),
                              foregroundColor: primaryColor,
                              child: Icon(Icons.groups_outlined),
                            ),
                            title: Text(
                              widget.allLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            trailing: widget.selectedValue == null
                                ? const Icon(
                                    Icons.check_circle,
                                    color: primaryColor,
                                  )
                                : null,
                            onTap: () => Navigator.of(
                              context,
                            ).pop(const _ScopeSelection(null)),
                          ),
                        for (final option in filtered)
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFF0F2FF),
                              foregroundColor: primaryColor,
                              child: Icon(option.icon),
                            ),
                            title: Text(
                              option.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              option.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: widget.selectedValue == option.value
                                ? const Icon(
                                    Icons.check_circle,
                                    color: primaryColor,
                                  )
                                : null,
                            onTap: () => Navigator.of(
                              context,
                            ).pop(_ScopeSelection(option.value)),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
