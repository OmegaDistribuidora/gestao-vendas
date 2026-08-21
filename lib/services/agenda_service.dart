import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/agenda_task.dart';

class AgendaService {
  AgendaService({http.Client? client}) : _client = client ?? http.Client();

  static const String _baseUrl = String.fromEnvironment(
    'AGENDA_API_URL',
    defaultValue: 'https://agenda-omega-production.up.railway.app',
  );

  final http.Client _client;

  Future<AgendaOverview> load({
    required String period,
    required DateTime anchor,
    AgendaUser? owner,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/mobile/agenda').replace(
      queryParameters: <String, String>{
        'period': period,
        'anchor': DateFormat('yyyy-MM-dd').format(anchor),
        if (owner != null) 'ownerCode': owner.code,
        if (owner != null) 'ownerRole': owner.role,
      },
    );
    final response = await _client.get(uri, headers: await _headers());
    final data = _decode(response);
    return AgendaOverview.fromJson(data);
  }

  Future<void> createTask({
    required String title,
    String? description,
    DateTime? dueAt,
    String priority = 'MEDIUM',
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/api/mobile/agenda/tasks'),
      headers: await _headers(json: true),
      body: jsonEncode(<String, dynamic>{
        'title': title.trim(),
        'description': description?.trim(),
        'dueAt': dueAt?.toUtc().toIso8601String(),
        'priority': priority,
      }),
    );
    _decode(response);
  }

  Future<void> updateStatus(
    int taskId,
    String status, {
    AgendaCompletionLocation? completionLocation,
  }) async {
    final response = await _client.patch(
      Uri.parse('$_baseUrl/api/mobile/agenda/tasks/$taskId/status'),
      headers: await _headers(json: true),
      body: jsonEncode(<String, dynamic>{
        'status': status,
        if (status == 'DONE')
          'location':
              (completionLocation ?? const AgendaCompletionLocation.notShared())
                  .toJson(),
      }),
    );
    _decode(response);
  }

  Future<void> addNote(int taskId, String body) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/api/mobile/agenda/tasks/$taskId/notes'),
      headers: await _headers(json: true),
      body: jsonEncode(<String, String>{'body': body.trim()}),
    );
    _decode(response);
  }

  Future<void> uploadPhoto(int taskId, XFile photo) async {
    final token = await _accessToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/api/mobile/agenda/tasks/$taskId/photos'),
    )..headers['Authorization'] = 'Bearer $token';
    final bytes = await photo.readAsBytes();
    request.files.add(
      http.MultipartFile.fromBytes(
        'photo',
        bytes,
        filename: photo.name,
        contentType: MediaType.parse(photo.mimeType ?? _mimeType(photo.name)),
      ),
    );
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    _decode(response);
  }

  Future<Uint8List> loadPhoto(int attachmentId) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/api/mobile/agenda/attachments/$attachmentId/photo'),
      headers: await _headers(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decode(response);
    }
    return response.bodyBytes;
  }

  Future<Map<String, String>> _headers({bool json = false}) async =>
      <String, String>{
        'Authorization': 'Bearer ${await _accessToken()}',
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json; charset=utf-8',
      };

  Future<String> _accessToken() async {
    var session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      throw const AgendaServiceException(
        'Sua sessão expirou. Entre novamente no aplicativo.',
      );
    }
    final expiresAt = session.expiresAt;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (expiresAt != null && expiresAt <= now + 30) {
      final refreshed = await Supabase.instance.client.auth.refreshSession();
      session = refreshed.session;
    }
    final token = session?.accessToken.trim() ?? '';
    if (token.isEmpty) {
      throw const AgendaServiceException(
        'Sua sessão expirou. Entre novamente no aplicativo.',
      );
    }
    return token;
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data = const <String, dynamic>{};
    if (response.body.trim().isNotEmpty) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) {
        data = decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AgendaServiceException(
        '${data['message'] ?? 'Não foi possível acessar a Agenda.'}',
        statusCode: response.statusCode,
      );
    }
    return data;
  }

  String _mimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
      return 'image/heic';
    }
    return 'image/jpeg';
  }
}

class AgendaCompletionLocation {
  const AgendaCompletionLocation({
    required this.shared,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.address,
    this.capturedAt,
  });

  const AgendaCompletionLocation.notShared()
    : shared = false,
      latitude = null,
      longitude = null,
      accuracyMeters = null,
      address = null,
      capturedAt = null;

  final bool shared;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final String? address;
  final DateTime? capturedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'shared': shared,
    if (shared) 'latitude': latitude,
    if (shared) 'longitude': longitude,
    if (shared) 'accuracyMeters': accuracyMeters,
    if (shared && address != null) 'address': address,
    if (shared && capturedAt != null)
      'capturedAt': capturedAt!.toUtc().toIso8601String(),
  };
}

class AgendaServiceException implements Exception {
  const AgendaServiceException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
