class MapboxConfig {
  static const publicToken = String.fromEnvironment('MAPBOX_PUBLIC_TOKEN');

  static bool get isConfigured => publicToken.trim().isNotEmpty;
}
