import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/mapbox_config.dart';
import '../models/customer_route.dart';

class MapboxDirectionsService {
  MapboxDirectionsService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  void close() {
    _client.close();
  }

  Future<CustomerRoute> getDrivingRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    if (!MapboxConfig.isConfigured) {
      throw const CustomerRouteException(
        'Token publico do Mapbox nao configurado.',
      );
    }

    final uri = Uri.https(
      'api.mapbox.com',
      '/directions/v5/mapbox/driving/'
          '${origin.longitude},${origin.latitude};'
          '${destination.longitude},${destination.latitude}',
      <String, String>{
        'access_token': MapboxConfig.publicToken,
        'alternatives': 'false',
        'geometries': 'geojson',
        'language': 'pt-BR',
        'overview': 'full',
        'steps': 'true',
      },
    );

    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CustomerRouteException(
        'Falha ao calcular rota (${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const CustomerRouteException('Resposta invalida do Mapbox.');
    }

    final code = '${decoded['code'] ?? ''}';
    if (code.isNotEmpty && code != 'Ok') {
      throw CustomerRouteException(
        '${decoded['message'] ?? 'Nao foi possivel calcular a rota.'}',
      );
    }

    final route = CustomerRoute.fromMapboxJson(decoded);
    if (route.points.length < 2) {
      throw const CustomerRouteException('A rota retornada esta incompleta.');
    }
    return route;
  }
}
