import 'app_profile.dart';
import '../utils/text_sanitizer.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.code,
    required this.technicalEmail,
    required this.isActive,
    required this.requiresAdminPasswordDefinition,
    this.loginAlias,
    this.displayName,
    this.profile,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String code;
  final String technicalEmail;
  final bool isActive;
  final bool requiresAdminPasswordDefinition;
  final String? loginAlias;
  final String? displayName;
  final AppProfile? profile;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get login {
    if (loginAlias?.trim().isNotEmpty == true) {
      return loginAlias!;
    }
    return code;
  }

  String get label {
    final parts = <String>[];
    if (code.trim().isNotEmpty) {
      parts.add(code);
    }
    if (displayName?.trim().isNotEmpty == true) {
      parts.add(displayName!);
    }
    if (parts.isNotEmpty) {
      return parts.join(' - ');
    }
    if (loginAlias?.trim().isNotEmpty == true) {
      return loginAlias!;
    }
    return technicalEmail;
  }

  bool get isAdmin => profile?.isAdmin ?? false;
  String get profileName => profile?.name ?? 'Sem perfil';
  String get profileSlug => profile?.slug ?? AppProfile.unassignedSlug;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final profileJson = json['profile'];
    return AppUser(
      id: json['auth_user_id'] as String? ?? json['id'] as String,
      code: json['code'] as String? ?? '',
      technicalEmail: json['technical_email'] as String,
      isActive: json['is_active'] as bool? ?? true,
      requiresAdminPasswordDefinition:
          json['requires_admin_password_definition'] as bool? ?? false,
      loginAlias: TextSanitizer.normalizeNullable(
        json['login_alias'] as String?,
      ),
      displayName: TextSanitizer.normalizeNullable(
        json['display_name'] as String?,
      ),
      profile: profileJson is Map<String, dynamic>
          ? AppProfile.fromJson(profileJson)
          : null,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'auth_user_id': id,
      'code': code,
      'technical_email': technicalEmail,
      'is_active': isActive,
      'requires_admin_password_definition': requiresAdminPasswordDefinition,
      'login_alias': loginAlias,
      'display_name': displayName,
      'profile': profile?.toJson(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  AppUser copyWith({
    String? id,
    String? code,
    String? technicalEmail,
    bool? isActive,
    bool? requiresAdminPasswordDefinition,
    String? loginAlias,
    String? displayName,
    AppProfile? profile,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearProfile = false,
  }) {
    return AppUser(
      id: id ?? this.id,
      code: code ?? this.code,
      technicalEmail: technicalEmail ?? this.technicalEmail,
      isActive: isActive ?? this.isActive,
      requiresAdminPasswordDefinition:
          requiresAdminPasswordDefinition ??
          this.requiresAdminPasswordDefinition,
      loginAlias: loginAlias ?? this.loginAlias,
      displayName: displayName ?? this.displayName,
      profile: clearProfile ? null : profile ?? this.profile,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
