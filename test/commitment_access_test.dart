import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_vendas/models/app_profile.dart';

void main() {
  AppProfile profile(String slug) =>
      AppProfile(id: slug, name: slug, slug: slug);

  test('commitment access is limited to leadership profiles', () {
    expect(profile(AppProfile.supervisorSlug).canAccessCommitment, isTrue);
    expect(profile(AppProfile.coordinatorSlug).canAccessCommitment, isTrue);
    expect(profile(AppProfile.boardSlug).canAccessCommitment, isTrue);
    expect(profile(AppProfile.othersSlug).canAccessCommitment, isTrue);
    expect(profile(AppProfile.managementSlug).canAccessCommitment, isTrue);

    expect(profile(AppProfile.sellerSlug).canAccessCommitment, isFalse);
    expect(profile(AppProfile.adminSlug).canAccessCommitment, isFalse);
    expect(profile(AppProfile.unassignedSlug).canAccessCommitment, isFalse);
  });
}
