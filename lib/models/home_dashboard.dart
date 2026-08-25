import 'app_profile.dart';
import 'commitment_overview.dart';
import 'home_positive_customers.dart';
import 'performance_overview.dart';
import 'seller_home_kpis.dart';

class HomeDashboard {
  const HomeDashboard({
    required this.viewerProfileSlug,
    required this.effectiveProfileSlug,
    required this.effectiveOwnerCode,
    required this.selectedScopeProfileSlug,
    required this.selectedScopeOwnerCode,
    required this.availableScopes,
    required this.kpis,
    required this.positiveCustomers,
    required this.performanceOverview,
    required this.commitmentOverview,
  });

  final String viewerProfileSlug;
  final String effectiveProfileSlug;
  final String effectiveOwnerCode;
  final String? selectedScopeProfileSlug;
  final String? selectedScopeOwnerCode;
  final List<HomeScopeOption> availableScopes;
  final SellerHomeKpis kpis;
  final HomePositiveCustomers positiveCustomers;
  final PerformanceOverview performanceOverview;
  final CommitmentOverview commitmentOverview;

  factory HomeDashboard.fromJson(Map<String, dynamic> json) {
    return HomeDashboard(
      viewerProfileSlug: '${json['viewer_profile_slug'] ?? ''}'.trim(),
      effectiveProfileSlug: '${json['effective_profile_slug'] ?? ''}'.trim(),
      effectiveOwnerCode: '${json['effective_owner_code'] ?? ''}'.trim(),
      selectedScopeProfileSlug: _nullableText(
        json['selected_scope_profile_slug'],
      ),
      selectedScopeOwnerCode: _nullableText(json['selected_scope_owner_code']),
      availableScopes: _parseList(
        json['available_scopes'],
        HomeScopeOption.fromJson,
      ),
      kpis: SellerHomeKpis.fromJson(_map(json['home_kpis'])),
      positiveCustomers: HomePositiveCustomers.fromJson(
        _map(json['positive_customers']),
      ),
      performanceOverview: PerformanceOverview.fromJson(
        _map(json['performance_overview']),
      ),
      commitmentOverview: CommitmentOverview.fromJson(
        _map(json['commitment_overview']),
      ),
    );
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map) {
      return <String, dynamic>{};
    }
    return value.map((key, value) => MapEntry('$key', value));
  }

  static List<T> _parseList<T>(
    Object? value,
    T Function(Map<String, dynamic>) parser,
  ) {
    if (value is! List) {
      return <T>[];
    }
    return value
        .whereType<Map>()
        .map((row) => parser(row.map((key, value) => MapEntry('$key', value))))
        .toList();
  }

  static String? _nullableText(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }
}

class HomeScopeOption {
  const HomeScopeOption({
    required this.profileSlug,
    required this.ownerCode,
    required this.displayName,
    required this.label,
  });

  final String profileSlug;
  final String ownerCode;
  final String displayName;
  final String label;

  String get value => '$profileSlug|$ownerCode';

  String get profileLabel => switch (profileSlug) {
    AppProfile.coordinatorSlug => 'Coordenador',
    AppProfile.supervisorSlug => 'Supervisor',
    AppProfile.sellerSlug => 'Vendedor',
    _ => 'Usuário',
  };

  factory HomeScopeOption.fromJson(Map<String, dynamic> json) {
    return HomeScopeOption(
      profileSlug: '${json['profile_slug'] ?? ''}'.trim(),
      ownerCode: '${json['owner_code'] ?? ''}'.trim(),
      displayName: '${json['display_name'] ?? ''}'.trim(),
      label: '${json['label'] ?? ''}'.trim(),
    );
  }
}
