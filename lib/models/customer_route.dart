import 'package:latlong2/latlong.dart';

class CustomerRoute {
  const CustomerRoute({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.points,
    required this.steps,
  });

  final double distanceMeters;
  final double durationSeconds;
  final List<LatLng> points;
  final List<CustomerRouteStep> steps;

  double get distanceKm => distanceMeters / 1000;

  int get durationMinutes => (durationSeconds / 60).round();

  factory CustomerRoute.fromMapboxJson(Map<String, dynamic> json) {
    final routes = json['routes'];
    if (routes is! List || routes.isEmpty || routes.first is! Map) {
      throw const CustomerRouteException('Nenhuma rota encontrada.');
    }

    final route = (routes.first as Map).map(
      (key, value) => MapEntry('$key', value),
    );
    final geometry = route['geometry'];
    final coordinates = geometry is Map ? geometry['coordinates'] : null;
    final legs = route['legs'];

    return CustomerRoute(
      distanceMeters: _toDouble(route['distance']),
      durationSeconds: _toDouble(route['duration']),
      points: coordinates is List
          ? coordinates
                .whereType<List>()
                .where((coordinate) => coordinate.length >= 2)
                .map(
                  (coordinate) => LatLng(
                    _toDouble(coordinate[1]),
                    _toDouble(coordinate[0]),
                  ),
                )
                .toList(growable: false)
          : const <LatLng>[],
      steps: legs is List && legs.isNotEmpty && legs.first is Map
          ? _parseSteps(
              ((legs.first as Map)['steps'] as List?) ?? const <dynamic>[],
            )
          : const <CustomerRouteStep>[],
    );
  }

  static List<CustomerRouteStep> _parseSteps(List<dynamic> rawSteps) {
    return rawSteps
        .whereType<Map>()
        .map((rawStep) {
          final step = rawStep.map((key, value) => MapEntry('$key', value));
          final maneuver = step['maneuver'];
          final instruction = maneuver is Map
              ? '${maneuver['instruction'] ?? ''}'.trim()
              : '';
          return CustomerRouteStep(
            instruction: instruction.isEmpty
                ? 'Siga pela rota indicada.'
                : instruction,
            distanceMeters: _toDouble(step['distance']),
            durationSeconds: _toDouble(step['duration']),
          );
        })
        .toList(growable: false);
  }
}

class CustomerRouteStep {
  const CustomerRouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final String instruction;
  final double distanceMeters;
  final double durationSeconds;
}

class CustomerRouteException implements Exception {
  const CustomerRouteException(this.message);

  final String message;
}

double _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse('$value') ?? 0;
}
