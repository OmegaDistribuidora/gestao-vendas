import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/routing_analysis.dart';

class RoutingAnalysisService {
  static const _previewUrl = String.fromEnvironment(
    'DAILY_ROUTING_PREVIEW_URL',
  );
  static const enabled = bool.fromEnvironment(
    'ROUTING_ANALYSIS_ENABLED',
    defaultValue: true,
  );

  Future<RoutingAnalysis> load({
    required DateTime date,
    String? targetScopeProfileSlug,
    String? targetScopeOwnerCode,
  }) async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession?.isExpired == true) {
      await client.auth.refreshSession();
    }

    final params = <String, dynamic>{
      'target_date': _dateText(date),
      'target_scope_profile_slug': targetScopeProfileSlug,
      'target_scope_owner_code': targetScopeOwnerCode,
    };

    Object? responseData;
    if (kDebugMode && _previewUrl.isNotEmpty) {
      final accessToken = client.auth.currentSession?.accessToken;
      if (accessToken == null) {
        throw const RoutingAnalysisException('Sessão indisponível.');
      }
      final response = await http
          .post(
            Uri.parse('$_previewUrl/route-analysis'),
            headers: <String, String>{
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(params),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw const RoutingAnalysisException(
          'Não foi possível carregar a roteirização.',
        );
      }
      responseData = jsonDecode(response.body);
    } else {
      responseData = await client
          .rpc('get_routing_analysis', params: params)
          .timeout(const Duration(seconds: 30));
    }

    if (responseData is! Map) {
      throw const RoutingAnalysisException('Resposta de roteiro inválida.');
    }
    return RoutingAnalysis.fromJson(Map<String, dynamic>.from(responseData));
  }

  static String _dateText(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class RoutingAnalysisException implements Exception {
  const RoutingAnalysisException(this.message);
  final String message;

  @override
  String toString() => message;
}
