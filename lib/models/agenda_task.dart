class AgendaOverview {
  const AgendaOverview({
    required this.user,
    required this.tasks,
    required this.owners,
    required this.canCreate,
    required this.canEdit,
    required this.canSelectOwner,
  });

  final AgendaUser user;
  final List<AgendaTask> tasks;
  final List<AgendaUser> owners;
  final bool canCreate;
  final bool canEdit;
  final bool canSelectOwner;

  factory AgendaOverview.fromJson(Map<String, dynamic> json) {
    final taskRows = json['tasks'] as List<dynamic>? ?? const <dynamic>[];
    final ownerRows = json['owners'] as List<dynamic>? ?? const <dynamic>[];
    final viewer = _map(json['viewer']);
    return AgendaOverview(
      user: AgendaUser.fromJson(_map(json['user'])),
      tasks: taskRows
          .whereType<Map>()
          .map((row) => AgendaTask.fromJson(_map(row)))
          .toList(growable: false),
      owners: ownerRows
          .whereType<Map>()
          .map((row) => AgendaUser.fromJson(_map(row)))
          .toList(growable: false),
      canCreate: viewer['canCreate'] == true,
      canEdit: viewer['canEdit'] == true,
      canSelectOwner: viewer['canSelectOwner'] == true,
    );
  }
}

class AgendaUser {
  const AgendaUser({
    required this.id,
    required this.displayName,
    required this.code,
    required this.role,
  });

  final int id;
  final String displayName;
  final String code;
  final String role;

  factory AgendaUser.fromJson(Map<String, dynamic> json) => AgendaUser(
    id: _integer(json['id']),
    displayName: '${json['displayName'] ?? ''}'.trim(),
    code: '${json['code'] ?? ''}'.trim(),
    role: '${json['role'] ?? ''}'.trim(),
  );
}

class AgendaTask {
  const AgendaTask({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.dueAt,
    required this.completedAt,
    required this.teamName,
    required this.folderName,
    required this.tags,
    required this.notes,
    required this.attachments,
  });

  final int id;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final String teamName;
  final String? folderName;
  final List<AgendaTag> tags;
  final List<AgendaNote> notes;
  final List<AgendaAttachment> attachments;

  bool get isPending => status == 'TODO';
  bool get isInProgress => status == 'IN_PROGRESS';
  bool get isDone => status == 'DONE';

  factory AgendaTask.fromJson(Map<String, dynamic> json) {
    final tagRows = json['tags'] as List<dynamic>? ?? const <dynamic>[];
    final noteRows = json['comments'] as List<dynamic>? ?? const <dynamic>[];
    final attachmentRows =
        json['attachments'] as List<dynamic>? ?? const <dynamic>[];
    return AgendaTask(
      id: _integer(json['id']),
      title: '${json['title'] ?? ''}'.trim(),
      description: _nullableText(json['description']),
      status: '${json['status'] ?? 'TODO'}',
      priority: '${json['priority'] ?? 'MEDIUM'}',
      dueAt: _date(json['dueAt']),
      completedAt: _date(json['completedAt']),
      teamName: '${_map(json['team'])['name'] ?? ''}'.trim(),
      folderName: _nullableText(_map(json['folder'])['name']),
      tags: tagRows
          .whereType<Map>()
          .map((row) {
            return AgendaTag.fromJson(_map(_map(row)['tag']));
          })
          .toList(growable: false),
      notes: noteRows
          .whereType<Map>()
          .map((row) => AgendaNote.fromJson(_map(row)))
          .toList(growable: false),
      attachments: attachmentRows
          .whereType<Map>()
          .map((row) => AgendaAttachment.fromJson(_map(row)))
          .toList(growable: false),
    );
  }
}

class AgendaTag {
  const AgendaTag({required this.name, required this.color});

  final String name;
  final String color;

  factory AgendaTag.fromJson(Map<String, dynamic> json) => AgendaTag(
    name: '${json['name'] ?? ''}'.trim(),
    color: '${json['color'] ?? '#6594a6'}'.trim(),
  );
}

class AgendaNote {
  const AgendaNote({
    required this.id,
    required this.body,
    required this.authorName,
    required this.createdAt,
  });

  final int id;
  final String body;
  final String authorName;
  final DateTime? createdAt;

  factory AgendaNote.fromJson(Map<String, dynamic> json) => AgendaNote(
    id: _integer(json['id']),
    body: '${json['body'] ?? ''}'.trim(),
    authorName: '${_map(json['author'])['displayName'] ?? ''}'.trim(),
    createdAt: _date(json['createdAt']),
  );
}

class AgendaAttachment {
  const AgendaAttachment({
    required this.id,
    required this.originalName,
    required this.mimeType,
    required this.size,
    required this.createdAt,
  });

  final int id;
  final String originalName;
  final String mimeType;
  final int size;
  final DateTime? createdAt;

  factory AgendaAttachment.fromJson(Map<String, dynamic> json) =>
      AgendaAttachment(
        id: _integer(json['id']),
        originalName: '${json['originalName'] ?? ''}'.trim(),
        mimeType: '${json['mimeType'] ?? ''}'.trim(),
        size: _integer(json['size']),
        createdAt: _date(json['createdAt']),
      );
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const <String, dynamic>{};
}

int _integer(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

DateTime? _date(Object? value) {
  final text = '$value'.trim();
  return text.isEmpty || text == 'null' ? null : DateTime.tryParse(text);
}

String? _nullableText(Object? value) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty ? null : text;
}
