import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/daily_routing.dart';

class DailyRoutingService {
  static const _previewUrl = String.fromEnvironment(
    'DAILY_ROUTING_PREVIEW_URL',
  );
  static const enabled = bool.fromEnvironment(
    'DAILY_ROUTING_ENABLED',
    defaultValue: true,
  );

  Future<DailyRouting> load({
    required String day,
    String? profile,
    String? code,
    bool details = false,
    String filter = 'all',
    int offset = 0,
    String? snapshotId,
  }) async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession?.isExpired == true) {
      await client.auth.refreshSession();
    }
    final params = <String, dynamic>{
      'target_date': day,
      'target_scope_profile_slug': profile,
      'target_scope_owner_code': code,
      'include_details': details,
      'item_filter': filter,
      'page_offset': offset,
      'page_size': 100,
      'expected_snapshot_id': snapshotId,
    };
    Object? data;
    if (kDebugMode && _previewUrl.isNotEmpty) {
      final token = client.auth.currentSession?.accessToken;
      if (token == null) throw Exception('Sessão indisponível.');
      final response = await http
          .post(
            Uri.parse('$_previewUrl/routing'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(params),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw Exception(
          'Não foi possível carregar o roteiro. Atualize para tentar novamente.',
        );
      }
      data = jsonDecode(response.body);
    } else {
      data = await client
          .rpc('get_home_daily_routing', params: params)
          .timeout(const Duration(seconds: 30));
    }
    return DailyRouting.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
