import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_vendas/widgets/searchable_user_scope_field.dart';

void main() {
  const option = SearchableUserScopeOption(
    value: 'vendedor|3060',
    title: 'Adrianne Dantas Sousa Costa',
    subtitle: 'Vendedor • 3060',
    code: '3060',
  );

  test('filtro de usuário encontra por nome e por código', () {
    expect(option.matches('adrianne'), isTrue);
    expect(option.matches('3060'), isTrue);
    expect(option.matches('supervisor'), isFalse);
  });
}
