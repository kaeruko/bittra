import 'package:bittora/services/content_moderation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allows ordinary event notices', () {
    expect(ContentModeration.validate('新刊あります'), isNull);
    expect(ContentModeration.validate('西ホールです'), isNull);
  });

  test('rejects blocked Japanese expressions', () {
    expect(ContentModeration.validate('死ね'), isNotNull);
    expect(ContentModeration.validate('殺すぞ'), isNotNull);
  });

  test('rejects blocked English expressions case-insensitively', () {
    expect(ContentModeration.validate('FUCK'), isNotNull);
  });
}
