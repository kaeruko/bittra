class ContentModeration {
  ContentModeration._();

  // びっとらはオフライン/P2Pで動くため、投稿前の安全対策も端末内で行う。
  // 単語そのものを広く禁止すると正常な告知まで誤検知しやすいため、
  // 明確な脅迫・自傷の扇動・強い個人攻撃など、高確度な表現だけを対象にする。
  static final List<RegExp> _highConfidenceAbusePatterns = [
    RegExp(r'(?:死\s*ね|し\s*ね|くたばれ)', caseSensitive: false),
    RegExp(r'(?:殺\s*す|ころ\s*す)(?:ぞ|から|よ)?', caseSensitive: false),
    RegExp(r'(?:自殺|じさつ)\s*(?:しろ|しなよ|して)', caseSensitive: false),
    RegExp(r'\bkill\s+(?:yourself|your self|you)\b', caseSensitive: false),
    RegExp(r'\bkys\b', caseSensitive: false),
    RegExp(r'\bfuck\s+you\b', caseSensitive: false),
  ];

  static bool containsClearlyAbusiveContent(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return false;
    }
    return _highConfidenceAbusePatterns.any(
      (pattern) => pattern.hasMatch(normalized),
    );
  }

  static String? validate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    if (containsClearlyAbusiveContent(value)) {
      return '相手を傷つけるおそれのある表現が含まれているため送信できません';
    }
    return null;
  }
}
