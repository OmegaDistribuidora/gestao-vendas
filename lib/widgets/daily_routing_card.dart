import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/daily_routing.dart';
import '../services/daily_routing_service.dart';

typedef RoutingLoader =
    Future<DailyRouting> Function({
      required String day,
      String? profile,
      String? code,
      bool details,
      String filter,
      int offset,
      String? snapshotId,
    });

class DailyRoutingCard extends StatefulWidget {
  const DailyRoutingCard({
    super.key,
    required this.day,
    required this.revision,
    this.profile,
    this.code,
    this.loader,
  });
  final String day;
  final int revision;
  final String? profile;
  final String? code;
  final RoutingLoader? loader;
  @override
  State<DailyRoutingCard> createState() => _DailyRoutingCardState();
}

class _DailyRoutingCardState extends State<DailyRoutingCard> {
  DailyRouting? _data;
  bool _error = false;
  int _request = 0;
  late final _service = DailyRoutingService();
  RoutingLoader get _load => widget.loader ?? _service.load;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant DailyRoutingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.day != widget.day ||
        oldWidget.profile != widget.profile ||
        oldWidget.code != widget.code;
    if (changed) _data = null;
    if (changed || oldWidget.revision != widget.revision) _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    try {
      final data = await _load(
        day: widget.day,
        profile: widget.profile,
        code: widget.code,
        details: false,
        filter: 'all',
        offset: 0,
        snapshotId: null,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _data = data;
        _error = false;
      });
    } catch (_) {
      if (mounted && request == _request) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data != null && data.available && !data.applicable) {
      return const SizedBox.shrink();
    }
    final text = data?.percent == null
        ? 'Sem roteiro hoje'
        : '${NumberFormat('0.##', 'pt_BR').format(data!.percent)}%';
    final unavailable = data == null || !data.available;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFF4F3FF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE1DFFD)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: unavailable
              ? _refresh
              : () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  useSafeArea: true,
                  builder: (_) => _RoutingDetails(
                    day: widget.day,
                    profile: widget.profile,
                    code: widget.code,
                    loader: _load,
                  ),
                ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(
                  Icons.route_outlined,
                  color: Color(0xFF6252D8),
                  size: 25,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Efetividade de hoje',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        _error
                            ? 'Não foi possível atualizar. Toque para consultar.'
                            : unavailable
                            ? 'Aguardando dados do roteiro'
                            : 'Roteirização • ${_sourceTime(data.updatedAt)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6D6B85),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    unavailable ? '—' : text,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF6252D8),
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right,
                  color: Color(0xFF6252D8),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _sourceTime(DateTime? value) {
  if (value == null) return 'Horário indisponível';
  final local = value.toUtc().subtract(const Duration(hours: 3));
  return 'Atualizado ${DateFormat('dd/MM HH:mm').format(local)}';
}

class _RoutingDetails extends StatefulWidget {
  const _RoutingDetails({
    required this.day,
    this.profile,
    this.code,
    required this.loader,
  });
  final String day;
  final String? profile;
  final String? code;
  final RoutingLoader loader;
  @override
  State<_RoutingDetails> createState() => _RoutingDetailsState();
}

class _RoutingDetailsState extends State<_RoutingDetails> {
  DailyRouting? _data;
  final List<DailyRoutingCustomer> _items = [];
  String _filter = 'all';
  bool _loading = true;
  bool _error = false;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch({bool more = false}) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final result = await widget.loader(
        day: widget.day,
        profile: widget.profile,
        code: widget.code,
        details: true,
        filter: _filter,
        offset: more ? _items.length : 0,
        snapshotId: more ? _data?.snapshotId : null,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _data = result;
        if (!more) _items.clear();
        _items.addAll(result.items);
        _loading = false;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .82,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Efetividade de hoje',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _loading ? null : () => _fetch(),
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Atualizar roteiro',
                ),
              ],
            ),
            if (data != null) ...[
              Text(
                '${data.planned} previstos • ${data.purchased} com compra • ${data.pending} sem compra',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 5),
              Text(
                _sourceTime(data.updatedAt),
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 6),
            const Text(
              'Compras no dia programado. Não depende de o cliente ser novo no mês.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final choice in const {
                  'all': 'Todos',
                  'purchased': 'Com compra',
                  'pending': 'Sem compra',
                }.entries)
                  ChoiceChip(
                    label: Text(choice.value),
                    selected: _filter == choice.key,
                    onSelected: _loading
                        ? null
                        : (_) {
                            setState(() {
                              _filter = choice.key;
                              _items.clear();
                            });
                            _fetch();
                          },
                  ),
              ],
            ),
            if (_error)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: TextButton(
                  onPressed: () => _fetch(),
                  child: const Text(
                    'Os dados podem ter mudado ou a consulta falhou. Toque para atualizar.',
                  ),
                ),
              ),
            if (_loading) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Expanded(
              child: !_loading && !_error && _items.isEmpty
                  ? Center(
                      child: Text(
                        data?.available == false
                            ? 'Dados do roteiro ainda indisponíveis.'
                            : data?.planned == 0
                            ? 'Sem roteiro hoje.'
                            : 'Nenhum cliente neste filtro.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: _items.length + 1,
                      itemBuilder: (context, index) {
                        if (index == _items.length) {
                          return data != null &&
                                  _items.length < data.filteredCount &&
                                  !_error
                              ? TextButton(
                                  onPressed: _loading
                                      ? null
                                      : () => _fetch(more: true),
                                  child: const Text('Carregar mais'),
                                )
                              : const SizedBox.shrink();
                        }
                        final item = _items[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  item.purchased
                                      ? Icons.check_circle_outline
                                      : Icons.schedule,
                                  color: item.purchased
                                      ? const Color(0xFF00866B)
                                      : const Color(0xFF8A809E),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${item.code} • ${item.name}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        item.purchased
                                            ? 'Comprou hoje'
                                            : 'Sem compra hoje',
                                        style: TextStyle(
                                          color: item.purchased
                                              ? const Color(0xFF00866B)
                                              : const Color(0xFF6D6B85),
                                        ),
                                      ),
                                      if (data?.profileSlug != 'vendedor') ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Vendedor: ${item.sellerCode} - ${item.sellerName}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
