import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_vendas/models/app_profile.dart';

void main() {
  AppProfile profile(String slug) =>
      AppProfile(id: slug, name: slug, slug: slug);

  test('agenda fica disponível somente para os perfis autorizados', () {
    expect(profile(AppProfile.supervisorSlug).canAccessAgenda, isTrue);
    expect(profile(AppProfile.coordinatorSlug).canAccessAgenda, isTrue);
    expect(profile(AppProfile.boardSlug).canAccessAgenda, isTrue);
    expect(profile(AppProfile.othersSlug).canAccessAgenda, isTrue);
    expect(profile(AppProfile.managementSlug).canAccessAgenda, isTrue);

    expect(profile(AppProfile.sellerSlug).canAccessAgenda, isFalse);
    expect(profile(AppProfile.adminSlug).canAccessAgenda, isFalse);
    expect(profile(AppProfile.unassignedSlug).canAccessAgenda, isFalse);
  });
}
