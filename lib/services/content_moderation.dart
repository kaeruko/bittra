class ContentModeration {
  ContentModeration._();

  static const List<String> _blockedTerms = [
    '死ね',
    'しね',
    '殺す',
    'ころす',
    '消えろ',
    'くたばれ',
    'レイプ',
    '強姦',
    'セックス',
    'ちんこ',
    'まんこ',
    'fuck',
    'fucking',
    'nigger',
    'nigga',
  ];

  static bool containsBlockedContent(String value) {
    final normalized = value.trim().toLowerCase();
    return _blockedTerms.any(normalized.contains);
  }

  static String? validate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    if (containsBlockedContent(value)) {
      return '不適切な表現が含まれているため送信できません';
    }
    return null;
  }
}
