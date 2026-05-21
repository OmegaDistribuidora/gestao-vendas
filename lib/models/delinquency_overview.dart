import '../utils/text_sanitizer.dart';

class DelinquencyOverview {
  const DelinquencyOverview({
    required this.viewerProfileSlug,
    required this.profileSlug,
    required this.groupByProfileSlug,
    required this.selectedScopeProfileSlug,
    required this.selectedScopeOwnerCode,
    required this.availableScopes,
    required this.totalAmount,
    required this.totalOrders,
    required this.totalClients,
    required this.groups,
    required this.clients,
    this.lastUpdatedAt,
  });

  final String viewerProfileSlug;
  final String profileSlug;
  final String? groupByProfileSlug;
  final String? selectedScopeProfileSlug;
  final String? selectedScopeOwnerCode;
  final List<DelinquencyScopeOption> availableScopes;
  final double totalAmount;
  final int totalOrders;
  final int totalClients;
  final List<DelinquencyGroup> groups;
  final List<DelinquencyClientSummary> clients;
  final DateTime? lastUpdatedAt;

  factory DelinquencyOverview.empty() {
    return const DelinquencyOverview(
      viewerProfileSlug: '',
      profileSlug: '',
      groupByProfileSlug: null,
      selectedScopeProfileSlug: null,
      selectedScopeOwnerCode: null,
      availableScopes: <DelinquencyScopeOption>[],
      totalAmount: 0,
      totalOrders: 0,
      totalClients: 0,
      groups: <DelinquencyGroup>[],
      clients: <DelinquencyClientSummary>[],
      lastUpdatedAt: null,
    );
  }

  factory DelinquencyOverview.fromJson(Map<String, dynamic> json) {
    final rawScopes = json['available_scopes'];
    final rawGroups = json['groups'];
    final rawClients = json['clients'];

    return DelinquencyOverview(
      viewerProfileSlug: '${json['viewer_profile_slug'] ?? ''}',
      profileSlug: '${json['profile_slug'] ?? ''}',
      groupByProfileSlug: _toNullableString(json['group_by_profile_slug']),
      selectedScopeProfileSlug: _toNullableString(
        json['selected_scope_profile_slug'],
      ),
      selectedScopeOwnerCode: _toNullableString(
        json['selected_scope_owner_code'],
      ),
      availableScopes: rawScopes is List
          ? rawScopes
                .whereType<Map>()
                .map(
                  (row) => DelinquencyScopeOption.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <DelinquencyScopeOption>[],
      totalAmount: _toDouble(json['total_amount']),
      totalOrders: _toInt(json['total_orders']),
      totalClients: _toInt(json['total_clients']),
      groups: rawGroups is List
          ? rawGroups
                .whereType<Map>()
                .map(
                  (row) => DelinquencyGroup.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <DelinquencyGroup>[],
      clients: rawClients is List
          ? rawClients
                .whereType<Map>()
                .map(
                  (row) => DelinquencyClientSummary.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <DelinquencyClientSummary>[],
      lastUpdatedAt: _parseDateTime(json['last_updated_at']),
    );
  }

  static double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? 0;
    }
    return 0;
  }

  static int _toInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  static String? _toNullableString(Object? value) {
    final text = '$value'.trim();
    if (value == null || text.isEmpty || text == 'null') {
      return null;
    }
    return text;
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }
}

class DelinquencyScopeOption {
  const DelinquencyScopeOption({
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

  factory DelinquencyScopeOption.fromJson(Map<String, dynamic> json) {
    return DelinquencyScopeOption(
      profileSlug: '${json['profile_slug'] ?? ''}',
      ownerCode: '${json['owner_code'] ?? ''}',
      displayName: TextSanitizer.normalize('${json['display_name'] ?? ''}'),
      label: TextSanitizer.normalize('${json['label'] ?? ''}'),
    );
  }
}

class DelinquencyGroup {
  const DelinquencyGroup({
    required this.profileSlug,
    required this.code,
    required this.displayName,
    required this.label,
    required this.totalAmount,
    required this.totalOrders,
    required this.totalClients,
    required this.clients,
  });

  final String? profileSlug;
  final String code;
  final String displayName;
  final String label;
  final double totalAmount;
  final int totalOrders;
  final int totalClients;
  final List<DelinquencyClientSummary> clients;

  factory DelinquencyGroup.fromJson(Map<String, dynamic> json) {
    final rawClients = json['clients'];
    return DelinquencyGroup(
      profileSlug: DelinquencyOverview._toNullableString(json['profile_slug']),
      code: '${json['code'] ?? ''}',
      displayName: TextSanitizer.normalize('${json['display_name'] ?? ''}'),
      label: TextSanitizer.normalize('${json['label'] ?? ''}'),
      totalAmount: DelinquencyOverview._toDouble(json['total_amount']),
      totalOrders: DelinquencyOverview._toInt(json['total_orders']),
      totalClients: DelinquencyOverview._toInt(json['total_clients']),
      clients: rawClients is List
          ? rawClients
                .whereType<Map>()
                .map(
                  (row) => DelinquencyClientSummary.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <DelinquencyClientSummary>[],
    );
  }

  DelinquencyGroup copyWith({
    String? profileSlug,
    String? code,
    String? displayName,
    String? label,
    double? totalAmount,
    int? totalOrders,
    int? totalClients,
    List<DelinquencyClientSummary>? clients,
  }) {
    return DelinquencyGroup(
      profileSlug: profileSlug ?? this.profileSlug,
      code: code ?? this.code,
      displayName: displayName ?? this.displayName,
      label: label ?? this.label,
      totalAmount: totalAmount ?? this.totalAmount,
      totalOrders: totalOrders ?? this.totalOrders,
      totalClients: totalClients ?? this.totalClients,
      clients: clients ?? this.clients,
    );
  }
}

class DelinquencyClientSummary {
  const DelinquencyClientSummary({
    required this.codcli,
    required this.clientName,
    required this.totalAmount,
    required this.totalOrders,
    required this.orders,
  });

  final String codcli;
  final String clientName;
  final double totalAmount;
  final int totalOrders;
  final List<DelinquencyOrderEntry> orders;

  factory DelinquencyClientSummary.fromJson(Map<String, dynamic> json) {
    final rawOrders = json['orders'];
    return DelinquencyClientSummary(
      codcli: '${json['codcli'] ?? ''}',
      clientName: TextSanitizer.normalize('${json['client_name'] ?? ''}'),
      totalAmount: DelinquencyOverview._toDouble(json['total_amount']),
      totalOrders: DelinquencyOverview._toInt(json['total_orders']),
      orders: rawOrders is List
          ? rawOrders
                .whereType<Map>()
                .map(
                  (row) => DelinquencyOrderEntry.fromJson(
                    row.map((key, value) => MapEntry('$key', value)),
                  ),
                )
                .toList()
          : const <DelinquencyOrderEntry>[],
    );
  }

  DelinquencyClientSummary copyWith({
    String? codcli,
    String? clientName,
    double? totalAmount,
    int? totalOrders,
    List<DelinquencyOrderEntry>? orders,
  }) {
    return DelinquencyClientSummary(
      codcli: codcli ?? this.codcli,
      clientName: clientName ?? this.clientName,
      totalAmount: totalAmount ?? this.totalAmount,
      totalOrders: totalOrders ?? this.totalOrders,
      orders: orders ?? this.orders,
    );
  }
}

class DelinquencyOrderEntry {
  const DelinquencyOrderEntry({
    required this.numped,
    required this.dtemissao,
    required this.dtvenc,
    required this.prestacao,
    required this.duplicata,
    required this.tipo,
    required this.valor,
  });

  final String numped;
  final DateTime? dtemissao;
  final DateTime? dtvenc;
  final String prestacao;
  final String duplicata;
  final String tipo;
  final double valor;

  factory DelinquencyOrderEntry.fromJson(Map<String, dynamic> json) {
    return DelinquencyOrderEntry(
      numped: '${json['numped'] ?? ''}',
      dtemissao: _parseDate(json['dtemissao']),
      dtvenc: _parseDate(json['dtvenc']),
      prestacao: '${json['prestacao'] ?? ''}',
      duplicata: '${json['duplicata'] ?? ''}',
      tipo: TextSanitizer.normalize('${json['tipo'] ?? ''}'),
      valor: DelinquencyOverview._toDouble(json['valor']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
