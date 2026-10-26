import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/coach_market.dart';

class CoachMarketService {
  CoachMarketService._({http.Client? client})
    : _client = client ?? http.Client();

  static final CoachMarketService instance = CoachMarketService._();

  static const String _productionBaseUrl =
      'https://apiomega.williamfmarinho.com.br';
  static const String _configuredBaseUrl = String.fromEnvironment(
    'COACH_MARKET_API_URL',
    defaultValue: _productionBaseUrl,
  );
  static const String _queueKey = 'coach_market_pending_submissions_v1';
  static const int _maximumQueuedSubmissions = 100;
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  final http.Client _client;
  Timer? _retryTimer;
  bool _flushing = false;

  static String get _baseUrl {
    final configured = _configuredBaseUrl.trim().replaceFirst(
      RegExp(r'/$'),
      '',
    );
    if (!kReleaseMode) return configured;

    final uri = Uri.tryParse(configured);
    final isLocalAddress =
        uri == null ||
        uri.scheme != 'https' ||
        uri.host == '10.0.2.2' ||
        uri.host == '127.0.0.1' ||
        uri.host == 'localhost';
    return isLocalAddress ? _productionBaseUrl : configured;
  }

  Future<CoachMarketCustomer> findCustomer(int customerCode) async {
    final response = await _request(
      () async => _client
          .get(
            Uri.parse('$_baseUrl/v1/coach-mercado/clientes/$customerCode'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 15)),
    );
    return CoachMarketCustomer.fromJson(_decode(response));
  }

  Future<bool> canAccess() async {
    final response = await _request(
      () async => _client
          .get(
            Uri.parse('$_baseUrl/v1/coach-mercado/acesso'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 10)),
    );
    return _decode(response)['enabled'] == true;
  }

  Future<CoachMarketSubmitResult> submitOrQueue(
    CoachMarketSubmission submission, {
    bool requiresCustomerLookup = false,
  }) async {
    final payload = submission.toJson();
    if (requiresCustomerLookup) {
      payload['_awaitingCustomerLookup'] = true;
      await _enqueue(payload);
      return const CoachMarketSubmitResult(sent: false, queued: true);
    }
    try {
      await _send(payload);
      return const CoachMarketSubmitResult(sent: true, queued: false);
    } on CoachMarketServiceException catch (error) {
      if (!error.retryable) rethrow;
      await _enqueue(payload);
      return const CoachMarketSubmitResult(sent: false, queued: true);
    }
  }

  void startAutoRetry() {
    _retryTimer ??= Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(flushPending()),
    );
    unawaited(flushPending());
  }

  void stopAutoRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<int> pendingCount() async => (await _readQueue()).length;

  Future<CoachMarketFlushResult> flushPending() async {
    if (_flushing) {
      return CoachMarketFlushResult(sent: 0, remaining: await pendingCount());
    }
    _flushing = true;
    var sent = 0;
    try {
      final pending = await _readQueue();
      final remaining = <Map<String, dynamic>>[];
      for (var index = 0; index < pending.length; index++) {
        final item = pending[index];
        var candidate = Map<String, dynamic>.from(item);
        try {
          candidate = await _prepareQueuedSubmission(candidate);
          await _send(candidate);
          sent++;
        } on CoachMarketServiceException catch (error) {
          remaining.add(candidate);
          remaining.addAll(pending.skip(index + 1));
          if (error.retryable || error.statusCode == 401) break;
          // Uma resposta de validacao/permissao precisa de intervencao e nao
          // deve ser descartada silenciosamente.
          break;
        }
      }
      await _writeQueue(remaining);
      return CoachMarketFlushResult(sent: sent, remaining: remaining.length);
    } finally {
      _flushing = false;
    }
  }

  Future<Map<String, dynamic>> _prepareQueuedSubmission(
    Map<String, dynamic> payload,
  ) async {
    final needsLookup =
        payload['_awaitingCustomerLookup'] == true ||
        (payload['customerLookupSucceeded'] == false &&
            payload['customerDataSource'] == 'manual');
    if (!needsLookup) {
      payload.remove('_awaitingCustomerLookup');
      return payload;
    }

    final customerCode = (payload['customerCode'] as num?)?.toInt();
    if (customerCode == null || customerCode < 1) {
      throw const CoachMarketServiceException(
        'Formulário pendente com código de cliente inválido.',
      );
    }
    final customer = await findCustomer(customerCode);
    payload
      ..['customerName'] = customer.name
      ..['customerCity'] = customer.city
      ..['customerNeighborhood'] = customer.neighborhood
      ..['customerAddress'] = customer.address
      ..['lastPurchaseDate'] = customer.lastPurchaseDate == null
          ? null
          : _dateOnly(customer.lastPurchaseDate!)
      ..['customerNeverPurchased'] = customer.neverPurchased
      ..['customerDataSource'] = 'api'
      ..['customerLookupSucceeded'] = true
      ..remove('_awaitingCustomerLookup');
    return payload;
  }

  Future<void> _send(Map<String, dynamic> payload) async {
    final apiPayload = Map<String, dynamic>.from(payload)
      ..remove('_awaitingCustomerLookup');
    final response = await _request(
      () async => _client
          .post(
            Uri.parse('$_baseUrl/v1/coach-mercado/respostas'),
            headers: await _headers(json: true),
            body: jsonEncode(apiPayload),
          )
          .timeout(const Duration(seconds: 20)),
    );
    _decode(response);
  }

  Future<http.Response> _request(
    Future<http.Response> Function() operation,
  ) async {
    try {
      return await operation();
    } on CoachMarketServiceException {
      rethrow;
    } on TimeoutException catch (error) {
      throw CoachMarketServiceException(
        'A API demorou para responder.',
        retryable: true,
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw CoachMarketServiceException(
        'A API local está indisponível.',
        retryable: true,
        cause: error,
      );
    } catch (error) {
      throw CoachMarketServiceException(
        'Não foi possível acessar a API local.',
        retryable: true,
        cause: error,
      );
    }
  }

  Future<Map<String, String>> _headers({bool json = false}) async => {
    'Authorization': 'Bearer ${await _accessToken()}',
    'Accept': 'application/json',
    'X-Client-Name': 'gestao-vendas-coach-mercado',
    if (json) 'Content-Type': 'application/json; charset=utf-8',
  };

  Future<String> _accessToken() async {
    var session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      throw const CoachMarketServiceException(
        'Sua sessão expirou. Entre novamente no aplicativo.',
        statusCode: 401,
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
      throw const CoachMarketServiceException(
        'Sua sessão expirou. Entre novamente no aplicativo.',
        statusCode: 401,
      );
    }
    return token;
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data = const {};
    if (response.bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map) {
          data = decoded.map((key, value) => MapEntry('$key', value));
        }
      } catch (_) {
        data = const {};
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = data['detail']?.toString().trim();
      throw CoachMarketServiceException(
        message?.isNotEmpty == true
            ? message!
            : 'Não foi possível acessar o Coach Mercado.',
        statusCode: response.statusCode,
        retryable:
            response.statusCode == 408 ||
            response.statusCode == 429 ||
            response.statusCode >= 500,
      );
    }
    return data;
  }

  Future<void> _enqueue(Map<String, dynamic> submission) async {
    final queue = await _readQueue();
    final submissionId = submission['submissionId']?.toString();
    if (queue.any((item) => item['submissionId']?.toString() == submissionId)) {
      return;
    }
    if (queue.length >= _maximumQueuedSubmissions) {
      throw const CoachMarketServiceException(
        'Há muitos formulários aguardando envio. Conecte o aparelho à API antes de continuar.',
      );
    }
    queue.add(submission);
    await _writeQueue(queue);
  }

  Future<List<Map<String, dynamic>>> _readQueue() async {
    final raw = await _storage.read(key: _queueKey);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => item.map((key, value) => MapEntry('$key', value)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeQueue(List<Map<String, dynamic>> queue) async {
    if (queue.isEmpty) {
      await _storage.delete(key: _queueKey);
      return;
    }
    await _storage.write(key: _queueKey, value: jsonEncode(queue));
  }
}

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

class CoachMarketSubmitResult {
  const CoachMarketSubmitResult({required this.sent, required this.queued});

  final bool sent;
  final bool queued;
}

class CoachMarketFlushResult {
  const CoachMarketFlushResult({required this.sent, required this.remaining});

  final int sent;
  final int remaining;
}

class CoachMarketServiceException implements Exception {
  const CoachMarketServiceException(
    this.message, {
    this.statusCode,
    this.retryable = false,
    this.cause,
  });

  final String message;
  final int? statusCode;
  final bool retryable;
  final Object? cause;

  bool get isNotFound => statusCode == 404;

  @override
  String toString() => message;
}
