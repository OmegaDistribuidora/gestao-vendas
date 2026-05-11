import '../utils/text_sanitizer.dart';

class AppProfile {
  const AppProfile({
    required this.id,
    required this.name,
    required this.slug,
    this.isSystem = false,
  });

  static const String adminSlug = 'admin';
  static const String sellerSlug = 'vendedor';
  static const String supervisorSlug = 'supervisor';
  static const String coordinatorSlug = 'coordenador';
  static const String boardSlug = 'diretoria';
  static const String othersSlug = 'outros';
  static const String unassignedSlug = 'sem_perfil';

  final String id;
  final String name;
  final String slug;
  final bool isSystem;

  bool get isAdmin => slug == adminSlug;
  bool get isUnassigned => slug == unassignedSlug;

  factory AppProfile.fromJson(Map<String, dynamic> json) {
    return AppProfile(
      id: json['id'] as String,
      name: TextSanitizer.normalize(json['name'] as String),
      slug: json['slug'] as String,
      isSystem: json['is_system'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'slug': slug,
      'is_system': isSystem,
    };
  }

  AppProfile copyWith({
    String? id,
    String? name,
    String? slug,
    bool? isSystem,
  }) {
    return AppProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      isSystem: isSystem ?? this.isSystem,
    );
  }
}
