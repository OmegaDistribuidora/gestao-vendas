import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/agenda_task.dart';
import '../services/agenda_service.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  final AgendaService _service = AgendaService();
  final Geocoding _geocoding = Geocoding(locale: const Locale('pt', 'BR'));
  DateTime _anchor = DateTime.now();
  String _period = 'today';
  AgendaOverview? _overview;
  AgendaUser? _selectedOwner;
  String? _error;
  bool _loading = true;
  bool _locationPreparationStarted = false;
  AgendaCompletionLocation? _preparedCompletionLocation;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final overview = await _service.load(
        period: _period,
        anchor: _anchor,
        owner: _selectedOwner,
      );
      if (!mounted) return;
      setState(() {
        _overview = overview;
        if (overview.canSelectOwner) _selectedOwner = overview.user;
      });
      if (overview.canEdit && !_locationPreparationStarted) {
        _locationPreparationStarted = true;
        unawaited(_prepareCompletionLocation());
      }
    } on AgendaServiceException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível carregar sua Agenda.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setPeriod(String value) {
    if (_period == value) return;
    setState(() {
      _period = value;
      _anchor = DateTime.now();
    });
    _load();
  }

  void _movePeriod(int direction) {
    setState(() {
      if (_period == 'today') {
        _anchor = _anchor.add(Duration(days: direction));
      } else if (_period == 'week') {
        _anchor = _anchor.add(Duration(days: 7 * direction));
      } else {
        _anchor = DateTime(_anchor.year, _anchor.month + direction, 1);
      }
    });
    _load();
  }

  String get _periodLabel {
    if (_period == 'today') {
      return DateFormat("EEEE, dd 'de' MMMM", 'pt_BR').format(_anchor);
    }
    if (_period == 'month') {
      final text = DateFormat('MMMM yyyy', 'pt_BR').format(_anchor);
      return '${text[0].toUpperCase()}${text.substring(1)}';
    }
    final monday = _anchor.subtract(Duration(days: _anchor.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    final start = DateFormat('dd MMM', 'pt_BR').format(monday);
    final end = DateFormat('dd MMM', 'pt_BR').format(sunday);
    return '$start — $end';
  }

  Future<void> _openTask(AgendaTask task) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AgendaTaskSheet(
        task: task,
        service: _service,
        readOnly: _overview?.canEdit != true,
        completionLocationProvider: _completionLocationForSubmit,
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _prepareCompletionLocation() async {
    _preparedCompletionLocation = await _captureCompletionLocation(
      requestPermission: true,
    );
  }

  Future<AgendaCompletionLocation> _completionLocationForSubmit() async {
    final latest = await _captureCompletionLocation(requestPermission: false);
    if (latest.shared) {
      _preparedCompletionLocation = latest;
      return latest;
    }
    return _preparedCompletionLocation?.shared == true
        ? _preparedCompletionLocation!
        : latest;
  }

  Future<AgendaCompletionLocation> _captureCompletionLocation({
    required bool requestPermission,
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const AgendaCompletionLocation.notShared();
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const AgendaCompletionLocation.notShared();
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return AgendaCompletionLocation(
        shared: true,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        address: await _resolveAddress(position),
        capturedAt: DateTime.now().toUtc(),
      );
    } catch (_) {
      return const AgendaCompletionLocation.notShared();
    }
  }

  Future<String?> _resolveAddress(Position position) async {
    try {
      final places = await _geocoding.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (places.isEmpty) return null;
      final place = places.first;
      final street = <String>[
        if ((place.thoroughfare ?? '').trim().isNotEmpty)
          place.thoroughfare!.trim()
        else if ((place.street ?? '').trim().isNotEmpty)
          place.street!.trim(),
        if ((place.subThoroughfare ?? '').trim().isNotEmpty)
          place.subThoroughfare!.trim(),
      ].join(', ');
      final parts = <String>[
        street,
        (place.subLocality ?? '').trim(),
        (place.locality ?? '').trim(),
        (place.administrativeArea ?? '').trim(),
      ].where((part) => part.isNotEmpty).toList(growable: false);
      return parts.isEmpty ? null : parts.join(' · ');
    } catch (_) {
      return null;
    }
  }

  Future<void> _createTask() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AgendaCreateTaskSheet(service: _service),
    );
    if (created == true) await _load();
  }

  void _selectOwner(AgendaUser owner) {
    if (_selectedOwner?.id == owner.id) return;
    setState(() => _selectedOwner = owner);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        title: const Text('Agenda'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _overview?.canCreate == true
          ? FloatingActionButton.extended(
              onPressed: _loading ? null : _createTask,
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('Nova atividade'),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_loading && _overview == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _overview == null) {
      return _AgendaError(message: _error!, onRetry: _load);
    }
    final overview = _overview;
    if (overview == null) return const SizedBox.shrink();
    final pending = overview.tasks.where((task) => task.isPending).toList();
    final inProgress = overview.tasks
        .where((task) => task.isInProgress)
        .toList();
    final done = overview.tasks.where((task) => task.isDone).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _AgendaHeader(
            user: overview.user,
            owners: overview.owners,
            canSelectOwner: overview.canSelectOwner,
            period: _period,
            periodLabel: _periodLabel,
            onPeriodChanged: _setPeriod,
            onPrevious: () => _movePeriod(-1),
            onNext: () => _movePeriod(1),
            onOwnerChanged: _selectOwner,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _InlineError(message: _error!),
          ],
          const SizedBox(height: 18),
          _AgendaSection(
            title: 'Pendentes',
            icon: Icons.radio_button_unchecked_rounded,
            color: const Color(0xFFE58A00),
            tasks: pending,
            onTap: _openTask,
          ),
          const SizedBox(height: 16),
          _AgendaSection(
            title: 'Em andamento',
            icon: Icons.timelapse_rounded,
            color: const Color(0xFF4B61FF),
            tasks: inProgress,
            onTap: _openTask,
          ),
          const SizedBox(height: 16),
          _AgendaSection(
            title: 'Concluídas',
            icon: Icons.check_circle_outline_rounded,
            color: const Color(0xFF087B5A),
            tasks: done,
            onTap: _openTask,
          ),
        ],
      ),
    );
  }
}

class _AgendaHeader extends StatelessWidget {
  const _AgendaHeader({
    required this.user,
    required this.owners,
    required this.canSelectOwner,
    required this.period,
    required this.periodLabel,
    required this.onPeriodChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onOwnerChanged,
  });

  final AgendaUser user;
  final List<AgendaUser> owners;
  final bool canSelectOwner;
  final String period;
  final String periodLabel;
  final ValueChanged<String> onPeriodChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<AgendaUser> onOwnerChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE4F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7EBFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: Color(0xFF4B61FF),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      canSelectOwner ? 'Agenda selecionada' : 'Minha agenda',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${user.code} · ${user.displayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF71809D),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (canSelectOwner) ...[
            DropdownButtonFormField<int>(
              initialValue: user.id,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Supervisor ou Coordenador',
                prefixIcon: Icon(Icons.manage_accounts_outlined),
              ),
              items: owners
                  .map(
                    (owner) => DropdownMenuItem<int>(
                      value: owner.id,
                      child: Text(
                        '${owner.code} · ${owner.displayName}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (id) {
                if (id == null) return;
                onOwnerChanged(owners.firstWhere((owner) => owner.id == id));
              },
            ),
            const SizedBox(height: 14),
          ],
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'today', label: Text('Hoje')),
              ButtonSegment(value: 'week', label: Text('Semana')),
              ButtonSegment(value: 'month', label: Text('Mês')),
            ],
            selected: <String>{period},
            onSelectionChanged: (value) => onPeriodChanged(value.first),
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity(horizontal: -1, vertical: -1),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8FC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: 'Período anterior',
                ),
                Expanded(
                  child: Text(
                    periodLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: 'Próximo período',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AgendaSection extends StatelessWidget {
  const _AgendaSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.tasks,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<AgendaTask> tasks;
  final ValueChanged<AgendaTask> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE4F0)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
            child: Row(
              children: [
                Icon(icon, color: color, size: 21),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${tasks.length}',
                    style: TextStyle(color: color, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(22),
              child: Text(
                'Nenhuma atividade neste período.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF7A879F),
                ),
              ),
            )
          else
            for (var index = 0; index < tasks.length; index++) ...[
              _AgendaTaskTile(
                task: tasks[index],
                onTap: () => onTap(tasks[index]),
              ),
              if (index != tasks.length - 1)
                const Divider(height: 1, indent: 16, endIndent: 16),
            ],
        ],
      ),
    );
  }
}

class _AgendaTaskTile extends StatelessWidget {
  const _AgendaTaskTile({required this.task, required this.onTap});

  final AgendaTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final due = _dueLabel(task.dueAt, task.isDone);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 5,
              height: 50,
              decoration: BoxDecoration(
                color: _priorityColor(task.priority),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      decoration: task.isDone
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      _Meta(icon: Icons.calendar_today_outlined, text: due),
                      if (task.teamName.isNotEmpty)
                        _Meta(
                          icon: Icons.groups_2_outlined,
                          text: task.teamName,
                        ),
                      if (task.attachments.isNotEmpty)
                        _Meta(
                          icon: Icons.photo_outlined,
                          text: '${task.attachments.length}',
                        ),
                      if (task.notes.isNotEmpty)
                        _Meta(
                          icon: Icons.notes_rounded,
                          text: '${task.notes.length}',
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF8793AA)),
          ],
        ),
      ),
    );
  }
}

class _AgendaTaskSheet extends StatefulWidget {
  const _AgendaTaskSheet({
    required this.task,
    required this.service,
    required this.readOnly,
    required this.completionLocationProvider,
  });

  final AgendaTask task;
  final AgendaService service;
  final bool readOnly;
  final Future<AgendaCompletionLocation> Function() completionLocationProvider;

  @override
  State<_AgendaTaskSheet> createState() => _AgendaTaskSheetState();
}

class _AgendaTaskSheetState extends State<_AgendaTaskSheet> {
  final ImagePicker _picker = ImagePicker();
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on AgendaServiceException catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: Colors.red),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível concluir a operação.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _addNote() async {
    final controller = TextEditingController();
    final body = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Adicionar descrição'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 7,
          maxLength: 5000,
          decoration: const InputDecoration(
            hintText: 'Registre detalhes sobre a atividade...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
            },
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (body == null) return;
    await _run(
      () => widget.service.addNote(widget.task.id, body),
      'Descrição adicionada.',
    );
  }

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Tirar foto'),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Escolher da galeria'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    final photo = await _picker.pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1920,
    );
    if (photo == null || !mounted) return;
    await _run(
      () => widget.service.uploadPhoto(widget.task.id, photo),
      'Foto anexada.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFE),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 4,
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFC7CFDD),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Pill(
                        label: _statusLabel(task.status),
                        color: _statusColor(task.status),
                      ),
                      _Pill(
                        label: _priorityLabel(task.priority),
                        color: _priorityColor(task.priority),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    task.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DetailLine(
                    icon: Icons.calendar_today_outlined,
                    text: _dueLabel(task.dueAt, task.isDone),
                  ),
                  if (task.teamName.isNotEmpty)
                    _DetailLine(
                      icon: Icons.groups_2_outlined,
                      text: task.folderName == null
                          ? task.teamName
                          : '${task.teamName} · ${task.folderName}',
                    ),
                  if (task.description != null) ...[
                    const SizedBox(height: 18),
                    const _SectionLabel('Descrição da atividade'),
                    const SizedBox(height: 8),
                    _TextBlock(text: task.description!),
                  ],
                  if (task.notes.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const _SectionLabel('Descrições adicionadas'),
                    const SizedBox(height: 8),
                    for (final note in task.notes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _TextBlock(
                          text: note.body,
                          footer: note.createdAt == null
                              ? note.authorName
                              : '${note.authorName} · ${DateFormat('dd/MM HH:mm', 'pt_BR').format(note.createdAt!.toLocal())}',
                        ),
                      ),
                  ],
                  if (task.attachments.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const _SectionLabel('Fotos e anexos'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: task.attachments
                          .map(
                            (file) => file.mimeType.startsWith('image/')
                                ? _AgendaPhotoThumbnail(
                                    file: file,
                                    service: widget.service,
                                  )
                                : Chip(
                                    avatar: const Icon(
                                      Icons.attach_file_rounded,
                                      size: 17,
                                    ),
                                    label: Text(
                                      file.originalName,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                  const SizedBox(height: 22),
                  if (!widget.readOnly && !task.isDone) ...[
                    Row(
                      children: [
                        if (task.isPending) ...[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _run(
                                      () => widget.service.updateStatus(
                                        task.id,
                                        'IN_PROGRESS',
                                      ),
                                      'Atividade iniciada.',
                                    ),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Iniciar'),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _run(() async {
                                    final location = await widget
                                        .completionLocationProvider();
                                    await widget.service.updateStatus(
                                      task.id,
                                      'DONE',
                                      completionLocation: location,
                                    );
                                  }, 'Atividade concluída.'),
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Concluir'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (!widget.readOnly)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _addNote,
                            icon: const Icon(Icons.notes_rounded),
                            label: const Text('Descrição'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _addPhoto,
                            icon: const Icon(Icons.add_a_photo_outlined),
                            label: const Text('Foto'),
                          ),
                        ),
                      ],
                    ),
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgendaCreateTaskSheet extends StatefulWidget {
  const _AgendaCreateTaskSheet({required this.service});

  final AgendaService service;

  @override
  State<_AgendaCreateTaskSheet> createState() => _AgendaCreateTaskSheetState();
}

class _AgendaCreateTaskSheetState extends State<_AgendaCreateTaskSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  DateTime? _dueAt = DateUtils.dateOnly(DateTime.now());
  String _priority = 'MEDIUM';
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (selected != null && mounted) setState(() => _dueAt = selected);
  }

  Future<void> _save() async {
    if (_busy || _formKey.currentState?.validate() != true) return;
    setState(() => _busy = true);
    try {
      await widget.service.createTask(
        title: _title.text,
        description: _description.text.trim().isEmpty
            ? null
            : _description.text,
        dueAt: _dueAt,
        priority: _priority,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Atividade criada na sua agenda.')),
      );
    } on AgendaServiceException catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: Colors.red),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível criar a atividade.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFE),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC7CFDD),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Text(
                'Nova atividade',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Ela será atribuída somente a você e arquivada automaticamente na pasta da sua região.',
                style: TextStyle(color: Color(0xFF71809D), height: 1.35),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _title,
                autofocus: true,
                maxLength: 180,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Título',
                  hintText: 'O que precisa ser feito?',
                  prefixIcon: Icon(Icons.task_alt_rounded),
                ),
                validator: (value) => value?.trim().isEmpty == true
                    ? 'Informe o título da atividade.'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _description,
                minLines: 3,
                maxLines: 6,
                maxLength: 10000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Descrição (opcional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _priority,
                decoration: const InputDecoration(
                  labelText: 'Prioridade',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'LOW', child: Text('Baixa')),
                  DropdownMenuItem(value: 'MEDIUM', child: Text('Média')),
                  DropdownMenuItem(value: 'HIGH', child: Text('Alta')),
                  DropdownMenuItem(value: 'URGENT', child: Text('Urgente')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _priority = value);
                },
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _busy ? null : _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Prazo (opcional)',
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(
                    _dueAt == null
                        ? 'Sem prazo definido'
                        : DateFormat('dd/MM/yyyy').format(_dueAt!),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_task_rounded),
                      label: Text(_busy ? 'Criando...' : 'Criar atividade'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgendaPhotoThumbnail extends StatefulWidget {
  const _AgendaPhotoThumbnail({required this.file, required this.service});

  final AgendaAttachment file;
  final AgendaService service;

  @override
  State<_AgendaPhotoThumbnail> createState() => _AgendaPhotoThumbnailState();
}

class _AgendaPhotoThumbnailState extends State<_AgendaPhotoThumbnail> {
  late final Future<Uint8List> _photo = widget.service.loadPhoto(
    widget.file.id,
  );

  void _open(Uint8List bytes) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: Center(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      semanticLabel: widget.file.originalName,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton.filled(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Fechar',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _photo,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return Semantics(
          button: bytes != null,
          label: 'Foto ${widget.file.originalName}',
          child: InkWell(
            onTap: bytes == null ? null : () => _open(bytes),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 112,
              height: 96,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFFE8ECF5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD7DEEB)),
              ),
              child: bytes != null
                  ? Image.memory(bytes, fit: BoxFit.cover)
                  : snapshot.hasError
                  ? const Icon(
                      Icons.broken_image_outlined,
                      color: Color(0xFF8A96AA),
                    )
                  : const Center(
                      child: SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: const Color(0xFF8290A9)),
      const SizedBox(width: 4),
      Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF6C7A94),
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF71809D)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF4E5E7A),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.titleSmall?.copyWith(
      color: const Color(0xFF23376D),
      fontWeight: FontWeight.w900,
    ),
  );
}

class _TextBlock extends StatelessWidget {
  const _TextBlock({required this.text, this.footer});
  final String text;
  final String? footer;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFDDE4F0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: const TextStyle(height: 1.4)),
        if (footer != null && footer!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            footer!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF7A879F),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFE9E9),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: Colors.red),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ],
    ),
  );
}

class _AgendaError extends StatelessWidget {
  const _AgendaError({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 90),
      const Icon(Icons.event_busy_outlined, size: 56, color: Color(0xFF4B61FF)),
      const SizedBox(height: 18),
      Text(
        'Não foi possível abrir sua Agenda',
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 10),
      Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF6D7B94), height: 1.4),
      ),
      const SizedBox(height: 20),
      Center(
        child: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
        ),
      ),
    ],
  );
}

String _statusLabel(String status) => switch (status) {
  'IN_PROGRESS' => 'Em andamento',
  'DONE' => 'Concluída',
  _ => 'Pendente',
};

Color _statusColor(String status) => switch (status) {
  'IN_PROGRESS' => const Color(0xFF4B61FF),
  'DONE' => const Color(0xFF087B5A),
  _ => const Color(0xFFE58A00),
};

String _priorityLabel(String priority) => switch (priority) {
  'LOW' => 'Baixa',
  'HIGH' => 'Alta',
  'URGENT' => 'Urgente',
  _ => 'Média',
};

Color _priorityColor(String priority) => switch (priority) {
  'LOW' => const Color(0xFF5B8E7D),
  'HIGH' => const Color(0xFFE58A00),
  'URGENT' => const Color(0xFFE34B5F),
  _ => const Color(0xFF4B61FF),
};

String _dueLabel(DateTime? value, bool completed) {
  if (value == null) return 'Sem prazo';
  final date = value.toLocal();
  final today = DateTime.now();
  final todayStart = DateTime(today.year, today.month, today.day);
  final dueStart = DateTime(date.year, date.month, date.day);
  if (!completed && dueStart.isBefore(todayStart)) {
    return 'Atrasada · ${DateFormat('dd/MM/yyyy').format(date)}';
  }
  if (dueStart == todayStart) return 'Hoje';
  return DateFormat('dd/MM/yyyy').format(date);
}
