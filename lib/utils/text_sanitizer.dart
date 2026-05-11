import 'dart:convert';

class TextSanitizer {
  static String normalize(String? rawValue) {
    if (rawValue == null || rawValue.isEmpty) {
      return rawValue ?? '';
    }

    var value = rawValue;
    final repairedUtf8 = _tryRepairUtf8(value);
    if (_mojibakeScore(repairedUtf8) < _mojibakeScore(value)) {
      value = repairedUtf8;
    }

    return value
        .replaceAll('Usu�rio', 'Usuário')
        .replaceAll('usu�rio', 'usuário')
        .replaceAll('M�dulo', 'Módulo')
        .replaceAll('m�dulo', 'módulo')
        .replaceAll('Libera��o', 'Liberação')
        .replaceAll('libera��o', 'liberação')
        .replaceAll('Exibi��o', 'Exibição')
        .replaceAll('exibi��o', 'exibição')
        .replaceAll('Configura��o', 'Configuração')
        .replaceAll('configura��o', 'configuração')
        .replaceAll('N�o', 'Não')
        .replaceAll('n�o', 'não');
  }

  static String? normalizeNullable(String? rawValue) {
    if (rawValue == null) {
      return null;
    }
    return normalize(rawValue);
  }

  static String _tryRepairUtf8(String value) {
    try {
      return utf8.decode(latin1.encode(value), allowMalformed: true);
    } catch (_) {
      return value;
    }
  }

  static int _mojibakeScore(String value) {
    var score = 0;
    for (final char in value.split('')) {
      if (char == '�') {
        score += 3;
      } else if (char == 'Ã' || char == 'Â') {
        score += 1;
      }
    }
    return score;
  }
}
