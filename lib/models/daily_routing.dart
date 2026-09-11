class DailyRouting {
  const DailyRouting({
    required this.available,
    required this.applicable,
    required this.planned,
    required this.purchased,
    required this.filteredCount,
    required this.items,
    this.percent,
    this.snapshotId,
    this.updatedAt,
    this.referenceDate,
    this.profileSlug = '',
  });

  final bool available;
  final bool applicable;
  final int planned;
  final int purchased;
  final int filteredCount;
  final double? percent;
  final String? snapshotId;
  final DateTime? updatedAt;
  final String? referenceDate;
  final String profileSlug;
  final List<DailyRoutingCustomer> items;
  int get pending => planned - purchased;

  factory DailyRouting.fromJson(Map<String, dynamic> json) => DailyRouting(
    available: json['available'] == true,
    applicable: json['applicable'] == true,
    planned: (json['planned'] as num?)?.toInt() ?? 0,
    purchased: (json['purchased'] as num?)?.toInt() ?? 0,
    filteredCount: (json['filtered_count'] as num?)?.toInt() ?? 0,
    percent: (json['percent'] as num?)?.toDouble(),
    snapshotId: json['snapshot_id'] as String?,
    referenceDate: json['reference_date'] as String?,
    updatedAt: DateTime.tryParse('${json['source_updated_at'] ?? ''}'),
    profileSlug: '${json['effective_profile_slug'] ?? ''}',
    items: (json['items'] as List? ?? [])
        .map(
          (e) => DailyRoutingCustomer.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList(),
  );
}

class DailyRoutingCustomer {
  const DailyRoutingCustomer({
    required this.code,
    required this.name,
    required this.sellerCode,
    required this.sellerName,
    required this.purchased,
  });
  final String code;
  final String name;
  final String sellerCode;
  final String sellerName;
  final bool purchased;
  factory DailyRoutingCustomer.fromJson(Map<String, dynamic> json) =>
      DailyRoutingCustomer(
        code: '${json['customer_code']}',
        name: '${json['customer_name'] ?? ''}',
        sellerCode: '${json['seller_code']}',
        sellerName: '${json['seller_name'] ?? ''}',
        purchased: json['purchased'] == true,
      );
}
