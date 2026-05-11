import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_vendas/models/bi_module.dart';
import 'package:gestao_vendas/models/bi_module_filter.dart';
import 'package:gestao_vendas/models/user_module_filter_value.dart';
import 'package:gestao_vendas/utils/power_bi_url_builder.dart';

void main() {
  test('builds Power BI url with filter metadata', () {
    const filter = BiModuleFilter(
      id: 'filter-1',
      moduleId: 'module-1',
      filterTable: 'dVendedor',
      filterColumn: 'codusur',
    );
    const module = BiModule(
      id: 'module-1',
      name: 'Pedidos',
      panelUrl: 'https://example.com/report',
      filters: <BiModuleFilter>[filter],
    );
    const filterValue = UserModuleFilterValue(
      id: 'value-1',
      accessId: 'access-1',
      moduleFilterId: 'filter-1',
      filterValue: '1716',
      moduleFilter: filter,
    );

    final url = PowerBiUrlBuilder.build(module, const [filterValue]);

    expect(url, contains('filter=dVendedor%2Fcodusur+eq+1716'));
    expect(url, contains('autoAuth=true'));
    expect(url, contains('chromeless=true'));
  });
}
