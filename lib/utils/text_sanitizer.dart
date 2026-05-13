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

    const replacements = <String, String>{
      'Ã¡': 'á',
      'Ã ': 'à',
      'Ã¢': 'â',
      'Ã£': 'ã',
      'Ã¤': 'ä',
      'Ã©': 'é',
      'Ãª': 'ê',
      'Ã­': 'í',
      'Ã³': 'ó',
      'Ã´': 'ô',
      'Ãµ': 'õ',
      'Ã¶': 'ö',
      'Ãº': 'ú',
      'Ã¼': 'ü',
      'Ã§': 'ç',
      'Ã\u0081': 'Á',
      'Ã\u0080': 'À',
      'Ã\u0082': 'Â',
      'Ã\u0083': 'Ã',
      'Ã\u0089': 'É',
      'Ã\u008A': 'Ê',
      'Ã\u008D': 'Í',
      'Ã\u0093': 'Ó',
      'Ã\u0094': 'Ô',
      'Ã\u0095': 'Õ',
      'Ã\u009A': 'Ú',
      'Ã\u0087': 'Ç',
      'â€¢': '•',
      'â€“': '–',
      'â€”': '—',
      'â€˜': '\'',
      'â€™': '\'',
      'â€œ': '"',
      'â€\u009d': '"',
      'Usu�rio': 'Usuário',
      'usu�rio': 'usuário',
      'M�dulo': 'Módulo',
      'm�dulo': 'módulo',
      'Libera��o': 'Liberação',
      'libera��o': 'liberação',
      'Exibi��o': 'Exibição',
      'exibi��o': 'exibição',
      'Configura��o': 'Configuração',
      'configura��o': 'configuração',
      'N�o': 'Não',
      'n�o': 'não',
    };

    for (final entry in replacements.entries) {
      value = value.replaceAll(entry.key, entry.value);
    }

    return value;
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
