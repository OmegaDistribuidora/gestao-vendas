import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/customer_analysis.dart';

class CustomerAnalysisService {
  CustomerAnalysisService._({http.Client? client})
    : _client = client ?? http.Client();

  static final CustomerAnalysisService instance = CustomerAnalysisService._();

  static const String _productionBaseUrl =
      'https://apiomega.williamfmarinho.com.br';
  static const String _configuredBaseUrl = String.fromEnvironment(
    'CUSTOMER_ANALYSIS_API_URL',
    defaultValue: _productionBaseUrl,
  );

  final http.Client _client;

  static String get _baseUrl {
    final configured = _configuredBaseUrl.trim().replaceFirst(
      RegExp(r'/$'),
      '',
    );
    if (!kReleaseMode) return configured;
    final uri = Uri.tryParse(configured);
    final local =
        uri == null ||
        uri.scheme != 'https' ||
        uri.host == '10.0.2.2' ||
        uri.host == '127.0.0.1' ||
        uri.host == 'localhost';
    return local ? _productionBaseUrl : configured;
  }

  Future<List<CustomerAnalysisSearchResult>> search(String query) async {
    final uri = Uri.parse('$_baseUrl/v1/analise-cliente/buscar').replace(
      queryParameters: <String, String>{'q': query.trim(), 'limit': '20'},
    );
    final data = await _get(uri, timeout: const Duration(seconds: 12));
    return _mapCustomers(data['customers']);
  }

  Future<List<CustomerAnalysisSearchResult>> nearby({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse('$_baseUrl/v1/analise-cliente/proximos').replace(
      queryParameters: <String, String>{
        'latitude': latitude.toStringAsFixed(7),
        'longitude': longitude.toStringAsFixed(7),
        'limit': '10',
      },
    );
    final data = await _get(uri, timeout: const Duration(seconds: 12));
    return _mapCustomers(data['customers']);
  }

  Future<CustomerAnalysisDetail> getDetail(int customerCode) async {
    final data = await _get(
      Uri.parse('$_baseUrl/v1/analise-cliente/clientes/$customerCode'),
      timeout: const Duration(seconds: 18),
    );
    return CustomerAnalysisDetail.fromJson(data);
  }

  Future<CustomerOrderDetail> getOrderDetail({
    required int customerCode,
    required int orderNumber,
  }) async {
    final data = await _get(
      Uri.parse(
        '$_baseUrl/v1/analise-cliente/clientes/$customerCode/pedidos/$orderNumber',
      ),
      timeout: const Duration(seconds: 15),
    );
    return CustomerOrderDetail.fromJson(data);
  }

  Future<Map<String, dynamic>> _get(
    Uri uri, {
    required Duration timeout,
  }) async {
    try {
      final response = await _client
          .get(uri, headers: await _headers())
          .timeout(timeout);
      return _decode(response);
    } on CustomerAnalysisServiceException {
      rethrow;
    } on TimeoutException catch (error) {
      throw CustomerAnalysisServiceException(
        'A consulta demorou mais que o esperado. Tente novamente.',
        retryable: true,
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw CustomerAnalysisServiceException(
        'Não foi possível conectar ao servidor da Ômega.',
        retryable: true,
        cause: error,
      );
    } catch (error) {
      throw CustomerAnalysisServiceException(
        'Não foi possível consultar os dados do cliente.',
        retryable: true,
        cause: error,
      );
    }
  }

  Future<Map<String, String>> _headers() async => <String, String>{
    'Authorization': 'Bearer ${await _accessToken()}',
    'Accept': 'application/json',
    'X-Client-Name': 'gestao-vendas-analise-cliente',
  };

  Future<String> _accessToken() async {
    var session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      throw const CustomerAnalysisServiceException(
        'Sua sessão expirou. Entre novamente no aplicativo.',
        statusCode: 401,
      );
    }
    final expiresAt = session.expiresAt;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (expiresAt != null && expiresAt <= now + 30) {
      session = (await Supabase.instance.client.auth.refreshSession()).session;
    }
    final token = session?.accessToken.trim() ?? '';
    if (token.isEmpty) {
      throw const CustomerAnalysisServiceException(
        'Sua sessão expirou. Entre novamente no aplicativo.',
        statusCode: 401,
      );
    }
    return token;
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data = const <String, dynamic>{};
    if (response.bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map) {
          data = decoded.map((key, value) => MapEntry('$key', value));
        }
      } catch (_) {
        data = const <String, dynamic>{};
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = data['detail']?.toString().trim();
      throw CustomerAnalysisServiceException(
        detail?.isNotEmpty == true
            ? detail!
            : 'Não foi possível consultar a Análise por Cliente.',
        statusCode: response.statusCode,
        retryable:
            response.statusCode == 408 ||
            response.statusCode == 429 ||
            response.statusCode >= 500,
      );
    }
    return data;
  }

  List<CustomerAnalysisSearchResult> _mapCustomers(dynamic value) {
    if (value is! List) return const <CustomerAnalysisSearchResult>[];
    return value
        .whereType<Map>()
        .map(
          (item) => CustomerAnalysisSearchResult.fromJson(
            item.map((key, value) => MapEntry('$key', value)),
          ),
        )
        .toList(growable: false);
  }
}

class CustomerAnalysisServiceException implements Exception {
  const CustomerAnalysisServiceException(
    this.message, {
    this.statusCode,
    this.retryable = false,
    this.cause,
  });

  final String message;
  final int? statusCode;
  final bool retryable;
  final Object? cause;

  @override
  String toString() => message;
}
