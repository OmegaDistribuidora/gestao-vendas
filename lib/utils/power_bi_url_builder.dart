import '../models/bi_module.dart';
import '../models/user_module_filter_value.dart';

class PowerBiUrlBuilder {
  static String build(
    BiModule module,
    List<UserModuleFilterValue> filterValues,
  ) {
    final uri = Uri.parse(module.panelUrl.trim());
    final currentParams = Map<String, String>.from(uri.queryParameters);

    currentParams['autoAuth'] = 'true';
    currentParams['chromeless'] = 'true';
    currentParams['navContentPaneEnabled'] = 'false';
    currentParams['pageName'] = '';

    final filterClauses = filterValues
        .where(
          (item) =>
              item.filterValue.trim().isNotEmpty &&
              item.moduleFilter != null &&
              item.moduleFilter!.filterTable.trim().isNotEmpty &&
              item.moduleFilter!.filterColumn.trim().isNotEmpty,
        )
        .map(
          (item) =>
              '${item.moduleFilter!.filterTable}/${item.moduleFilter!.filterColumn} eq ${_formatFilterValueForUrl(item.filterValue)}',
        )
        .toList();

    if (filterClauses.isNotEmpty) {
      currentParams['filter'] = filterClauses.join(' and ');
    }

    return uri.replace(queryParameters: currentParams).toString();
  }

  static String _formatFilterValueForUrl(String rawValue) {
    final normalized = _normalizeFilterValue(rawValue);
    if (normalized is num || normalized is bool) {
      return '$normalized';
    }

    final sanitizedValue = '$normalized'.replaceAll('\'', '\'\'');
    return '\'$sanitizedValue\'';
  }

  static Object _normalizeFilterValue(String rawValue) {
    final trimmed = rawValue.trim();
    final parsedNumber = num.tryParse(trimmed);
    if (parsedNumber != null) {
      return parsedNumber;
    }

    final lowercaseValue = trimmed.toLowerCase();
    if (lowercaseValue == 'true') {
      return true;
    }
    if (lowercaseValue == 'false') {
      return false;
    }

    return trimmed;
  }
}
